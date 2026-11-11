#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AUTO-001 串行工单调度器 — DeepSeek Harness headless CLI + 本机 Qwen Flash。

硬约束（代码级强制）：
  * 单实例：O_EXCL 锁文件；已持锁 exit 75。
  * 单模型：每个 headless 会话必带 --patch（local llama.cpp provider），绝不走云默认模型。
  * 每票每次尝试都是全新会话；从不使用 --resume/--session。
  * 禁子 Agent / 并行 / 后台任务（提示词显式禁止 + headless 无委派插件 + 单实例锁）。
  * tasks/APPROVALS.md 只读：本程序任何路径都不写它；Phase B 写码前先校验批准。
  * 只有 测试+范围+批准 三项全过才自动 commit（不 push）；失败保留证据、不 commit、冻结队列。

用法：
  python3 tools/auto/runner.py start [--id ID] [--timeout 1800]
  python3 tools/auto/runner.py check|status|log [-n N]|pause|resume|unfreeze --reason "..."
  python3 tools/auto/runner.py selftest   # /tmp 合成项目回归（不碰真实工单）
"""
import argparse
import datetime
import fnmatch
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT_DEFAULT = "/Users/rain/DevGame/Fishing"
MODEL_ID = "ggml-org/Qwen3.8-Flash-Next-GGUF:IQ4_NL"
DSH = os.environ.get("AUTO001_DSH", "/opt/homebrew/bin/dsh")
BASE_DEFAULT = "http://127.0.0.1:9931/v1"
MAX_RETRIES = 2  # 每票最多自动重试 2 次（含首跑最多 3 次尝试）
SESSIONS_ROOT = os.path.expanduser("~/.dsh/sessions")
HERE = os.path.dirname(os.path.abspath(__file__))

# 退出码
EXIT_OK, EXIT_LOCK, EXIT_MODEL, EXIT_APPROVAL, EXIT_BLOCKED, EXIT_FROZEN, EXIT_USAGE = 0, 75, 60, 65, 66, 76, 2


def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


class Runner:
    def __init__(self, args):
        self.root = os.path.realpath(args.root or ROOT_DEFAULT)
        self.queue_path = os.path.realpath(args.queue or os.path.join(self.root, "tools/auto/queue.json"))
        self.queue_relpath = os.path.relpath(self.queue_path, self.root).replace(os.sep, "/")
        self._queue_fingerprint = self.file_fingerprint(self.queue_path)
        self.approvals_path = args.approvals or os.path.join(self.root, "tasks/APPROVALS.md")
        self.patch = args.patch or os.path.join(HERE, "headless-local-qwen.patch.yml")
        self.base = args.base_url or BASE_DEFAULT
        self.timeout = args.timeout or 1800
        self.log_dir = os.path.join(self.root, "tasks/evidence/_runner")
        self.lock = os.path.join(self.log_dir, "runner.lock")
        self.pause_flag = os.path.join(self.log_dir, "PAUSE")

    # ---------- 基础设施 ----------
    def log(self, msg):
        os.makedirs(self.log_dir, exist_ok=True)
        line = f"[{now()}] {msg}"
        with open(os.path.join(self.log_dir, "runner.log"), "a") as f:
            f.write(line + "\n")
        print(line, flush=True)

    def acquire_lock(self):
        os.makedirs(self.log_dir, exist_ok=True)
        try:
            fd = os.open(self.lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            self._lock_fd = fd
            return True
        except FileExistsError:
            try:
                pid = int(open(self.lock).read().strip())
                os.kill(pid, 0)  # 仍存活?
                return False
            except Exception:
                os.unlink(self.lock)  # 陈旧锁，抢占
                return self.acquire_lock()

    def release_lock(self):
        try:
            os.unlink(self.lock)
        except OSError:
            pass

    def q(self):
        with open(self.queue_path) as f:
            return json.load(f)

    def save_q(self, q):
        q["updated"] = now()
        tmp = self.queue_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(q, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.queue_path)
        self._queue_fingerprint = self.file_fingerprint(self.queue_path)

    @staticmethod
    def file_fingerprint(path):
        try:
            with open(path, "rb") as f:
                return hashlib.sha256(f.read()).hexdigest()
        except OSError:
            return None

    @staticmethod
    def stable_file_fingerprint(path, retries=4, interval=0.1):
        for attempt in range(retries):
            try:
                before = os.stat(path)
                fingerprint = Runner.file_fingerprint(path)
                after = os.stat(path)
            except OSError:
                return None
            before_state = (before.st_ino, before.st_size, before.st_mtime_ns)
            after_state = (after.st_ino, after.st_size, after.st_mtime_ns)
            if fingerprint is not None and before_state == after_state:
                return fingerprint
            if attempt + 1 < retries:
                time.sleep(interval)
        return None

    def ticket(self, q, tid):
        for t in q["tickets"]:
            if t["id"] == tid:
                return t
        return None

    def freeze(self, q, reason):
        q["frozen"] = {"reason": reason, "at": now()}
        self.save_q(q)
        self.log(f"FROZEN: {reason}")

    # ---------- 门禁 ----------
    def gate_model(self):
        health_url = self.base.replace("/v1", "") + "/health"
        try:
            with urllib.request.urlopen(health_url, timeout=5) as r:
                h = json.load(r)
            if h.get("status") != "ok":
                return False, f"health={h}"
            with urllib.request.urlopen(self.base + "/models", timeout=10) as r:
                m = json.load(r)
            ids = [x.get("id") for x in m.get("data", [])]
            if MODEL_ID not in ids:
                return False, f"{MODEL_ID} 不在 /v1/models: {ids}"
            return True, "health ok; model listed"
        except Exception as e:
            return False, f"{type(e).__name__}: {e}"

    APPRO_RE = re.compile(r"BEGIN-APPROVAL\s+ID=(\S+)\s+PHASE=(\S+)\s*\n(.*?)END-APPROVAL", re.S)

    def approval(self, tid, phase):
        if not os.path.exists(self.approvals_path):
            return None
        txt = open(self.approvals_path, encoding="utf-8").read()
        for m in self.APPRO_RE.finditer(txt):
            if m.group(1) == tid and m.group(2) == phase:
                body = m.group(3)
                if re.search(r"^APPROVED\s*$", body, re.M) and re.search(r"^by:\s*\S+", body, re.M):
                    return m.group(0)
        return None

    def approvals_hash(self):
        if not os.path.exists(self.approvals_path):
            return "MISSING"
        import hashlib
        return hashlib.sha256(open(self.approvals_path, "rb").read()).hexdigest()[:16]

    def git(self, *a):
        p = subprocess.run(["git", "-C", self.root] + list(a), capture_output=True, text=True)
        return p.returncode, p.stdout, p.stderr  # 不得 strip：porcelain 首行 XY 列依赖前导空格

    @staticmethod
    def in_glob(path, g):
        if g.endswith("/**"):
            return path.startswith(g[:-2]) or path == g[:-3]
        return path == g or fnmatch.fnmatch(path, g)

    def changed_files(self):
        rc, out, _ = self.git("status", "--porcelain=v1", "--untracked-files=all")
        if rc != 0:
            return None
        files = []
        for line in out.splitlines():
            if not line.strip():
                continue
            xy, path = line[:2], line[3:].strip().strip('"')
            files.append((xy, path))
        return files

    @staticmethod
    def ignored(path):
        # 测试构建产物不算 agent 改动（Godot/Python 常见副产物）
        return path.endswith(".pyc") or "__pycache__/" in path or path.startswith(".godot")

    def scope_violations(self, allowed):
        bad = []
        files = self.changed_files() or []
        always = list(allowed) + ["tasks/evidence/**"]
        for xy, path in files:
            untracked = xy == "??"
            if self.ignored(path):
                continue
            if path == self.queue_relpath:
                current = self.file_fingerprint(os.path.join(self.root, path))
                if (self._queue_fingerprint is not None and current is not None
                        and current == self._queue_fingerprint):
                    continue  # 只豁免与 runner 最近一次读写快照完全一致的队列状态
                bad.append((xy, path, "队列文件被 runner 会话或外部进程改动"))
                continue
            if path == "tasks/APPROVALS.md":
                if not untracked:  # 账本被"改动"才算伪造；未跟踪=人工尚未 commit 的新账本
                    bad.append((xy, path, "批准账本被改动"))
                continue
            if self.allowed_icon_import(path, allowed) or any(self.in_glob(path, g) for g in always):
                continue
            bad.append((xy, path, "超出 allowed_files"))
        return files, bad

    @staticmethod
    def allowed_icon_import(path, allowed):
        # Godot 生成的 icon.svg.import 仅随明确允许的 icon.svg 一起归属本票。
        return path == "icon.svg.import" and any(Runner.in_glob("icon.svg", g) for g in allowed)

    # ---------- 会话 ----------
    def session_slug_dir(self):
        # 实测 harness 会话目录命名: "-" + path(/→-) + "--"（末尾双横线）
        return os.path.join(SESSIONS_ROOT, "-" + self.root.replace("/", "-") + "--")

    def archive_session(self, t0, ev_dir, tag):
        d = self.session_slug_dir()
        if not os.path.isdir(d):
            return None
        best = None
        for name in os.listdir(d):
            f = os.path.join(d, name, "session.v4.jsonl.zstd")
            if os.path.isfile(f) and os.path.getmtime(f) >= t0 - 2:
                if best is None or os.path.getmtime(f) > os.path.getmtime(best):
                    best = f
        if not best:
            return None
        dst = os.path.join(ev_dir, f"{tag}.session.v4.jsonl.zstd")
        shutil.copy2(best, dst)
        return dst

    def run_session(self, prompt, ev_dir, tag):
        env = dict(os.environ)
        env.pop("DSH_PROFILE", None)
        env.setdefault("LOCAL_QWEN2_API_KEY", "local-dev-key")
        if not os.path.exists(self.patch):
            raise SystemExit("缺少 --patch 文件，拒绝启动（可能回落到云默认模型）: " + self.patch)
        cmd = [os.environ.get("AUTO001_DSH", DSH), "--profile", "headless", "--patch", self.patch, prompt]
        self.log(f"launch headless session tag={tag}")
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=self.root, env=env, capture_output=True, text=True, timeout=self.timeout)
            rc, out, err = p.returncode, p.stdout, p.stderr
        except subprocess.TimeoutExpired:
            rc, out, err = -9, "(TIMEOUT)", ""
        time.sleep(2)  # 等会话落盘
        os.makedirs(ev_dir, exist_ok=True)
        with open(os.path.join(ev_dir, f"{tag}.out"), "w", encoding="utf-8") as f:
            f.write(out + "\n---STDERR---\n" + err)
        sess = self.archive_session(t0, ev_dir, tag)
        self.log(f"session done tag={tag} rc={rc} archived={bool(sess)}")
        return rc, out

    # ---------- 模板 ----------
    def fill(self, tmpl, ticket, ev, test_rc_hint="", retry_note=""):
        tpl_path = os.path.join(HERE, "prompts", tmpl)
        text = open(tpl_path, encoding="utf-8").read()
        brief = ticket.get("brief") or self.brief_from_tasks(ticket["id"])
        reps = {
            "{ID}": ticket["id"],
            "{TITLE}": ticket.get("title", ""),
            "{ALLOWED}": ", ".join(ticket.get("allowed_files", [])),
            "{EVID}": ev,
            "{TESTCMD}": ticket.get("test_cmd", "true"),
            "{BRIEF}": brief,
            "{RETRY}": retry_note,
        }
        for k, v in reps.items():
            text = text.replace(k, v)
        return text

    def brief_from_tasks(self, tid):
        p = os.path.join(self.root, "tasks/TASKS.md")
        if not os.path.exists(p):
            return ""
        txt = open(p, encoding="utf-8").read()
        m = re.search(rf"^## {re.escape(tid)}.*?(?=^## |\Z)", txt, re.S | re.M)
        return m.group(0) if m else ""

    @staticmethod
    def blocked_reason(out):
        for line in reversed(out.splitlines()):
            if line.strip().startswith("BLOCKED:"):
                return line.strip()
        return None

    # ---------- 阶段 ----------
    def evidence_dir(self, tid):
        d = os.path.join(self.root, "tasks/evidence", tid)
        os.makedirs(d, exist_ok=True)
        return d

    def phase_a(self, q, t):
        ev = self.evidence_dir(t["id"])
        files, bad = self.scope_violations(t.get("allowed_files", []))
        if bad:
            self.block(q, t, f"Phase A 前工作树已越界: {bad}")
            return EXIT_BLOCKED
        rc, out = self.run_session(self.fill("phaseA.txt.tmpl", t, ev), ev, "phaseA")
        reason = self.blocked_reason(out)
        if reason:
            self.block(q, t, "Agent 报 BLOCKED: " + reason)
            return EXIT_BLOCKED
        _, bad2 = self.scope_violations(t.get("allowed_files", []))
        if rc != 0 or "PHASE-A-DONE" not in out or bad2:
            self.block(q, t, f"Phase A 失败或越界 rc={rc} violations={bad2}")
            return EXIT_BLOCKED
        t["status"] = "awaiting_approval"
        t.pop("blocked_reason", None)
        self.save_q(q)
        self.log(f"{t['id']}: plan 完成 → awaiting_approval（人工批准: 编辑 APPROVALS.md 后把 status 改为 exec_ready）")
        return EXIT_OK

    def phase_b(self, q, t):
        ap = self.approval(t["id"], "B")
        if not ap:
            self.log(f"APPROVAL MISSING: {t['id']} 无 Phase B 人工批准记录 → 拒绝启动任何写码会话")
            return EXIT_APPROVAL
        self.log(f"approval verified for {t['id']} (ledger sha {self.approvals_hash()})")
        if not t.get("test_cmd"):
            self.block(q, t, "缺少 test_cmd：无法自动验证，禁止执行；请人工填写测试命令后再转 exec_ready")
            return EXIT_BLOCKED
        ev = self.evidence_dir(t["id"])
        ap_hash0 = self.approvals_hash()
        retry_note = ""
        for attempt in range(1, MAX_RETRIES + 2):
            tag = f"phaseB-{attempt}"
            rc, out = self.run_session(self.fill("phaseB.txt.tmpl", t, ev, retry_note=retry_note), ev, tag)
            reason = self.blocked_reason(out)
            if reason:
                self.block(q, t, "Agent 报 BLOCKED: " + reason)
                return EXIT_BLOCKED
            if self.approvals_hash() != ap_hash0:
                self.block(q, t, "APPROVALS.md 在会话期间被改动 — 疑似伪造批准")
                return EXIT_BLOCKED
            trc = self.run_test(t, ev, attempt)
            files, bad = self.scope_violations(t.get("allowed_files", []))
            if rc == 0 and trc == 0 and not bad:
                return self.commit_success(q, t, ev, attempt, trc)
            self.log(f"{t['id']} attempt {attempt} 失败 test_rc={trc} session_rc={rc} 越界={bad}")
            t["retries"] = attempt
            self.save_q(q)
            if attempt <= MAX_RETRIES:
                retry_note = (f"\n这是第 {attempt + 1} 次尝试（最多重试 {MAX_RETRIES} 次）。"
                              f"上次失败：test_exit={trc}，日志 {ev}/test-{attempt}.log，"
                              f"会话输出 {ev}/{tag}.out。先诊断再修，勿扩大范围。\n")
        self.block(q, t, f"重试 {MAX_RETRIES} 次后仍失败；证据在 {ev}/，未 commit 任何代码")
        return EXIT_BLOCKED

    def run_test(self, t, ev, attempt):
        if not t.get("test_cmd"):
            return 127  # 无测试命令一律视为失败，禁止静默通过
        command = t["test_cmd"]
        try:
            argv = shlex.split(command)
        except ValueError:
            argv = []
        smoke_script = "res://tests/unit/test_core001_smoke.gd"
        is_core_smoke = (
            argv and os.path.basename(argv[0]).lower().startswith("godot") and
            any(argv[i] in ("--script", "-s") and argv[i + 1] == smoke_script
                for i in range(len(argv) - 1))
        )

        temp_dir = None
        cwd = self.root
        env = None
        test_command = command
        import_command = None
        if is_core_smoke:
            temp_dir = tempfile.mkdtemp(prefix="auto001-core-smoke-")
            project_copy = os.path.join(temp_dir, "project")

            def copy_ignored(directory, names):
                ignored = {name for name in names
                           if name in (".git", ".godot", "__pycache__") or name.endswith(".pyc")}
                if os.path.realpath(directory) == os.path.realpath(os.path.join(self.root, "tasks")):
                    ignored.add("evidence")
                return ignored

            try:
                shutil.copytree(self.root, project_copy, ignore=copy_ignored)
                home = os.path.join(temp_dir, "home")
                os.makedirs(home)
                sensitive_markers = ("API_KEY", "ACCESS_KEY", "PRIVATE_KEY", "TOKEN",
                                     "SECRET", "PASSWORD", "CREDENTIAL")
                env = {key: value for key, value in os.environ.items()
                       if not any(marker in key.upper() for marker in sensitive_markers)}
                env["HOME"] = home
                env["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
                env["XDG_CACHE_HOME"] = os.path.join(home, ".cache")
                cwd = project_copy
                test_command = self.with_godot_project_path(argv, project_copy)
                for i, arg in enumerate(argv[:-1]):
                    if arg in ("--script", "-s") and argv[i + 1] == smoke_script:
                        import_command = self.with_godot_project_path(
                            argv[:i] + argv[i + 2:] + ["--editor", "--quit"], project_copy)
                        break
            except OSError as exc:
                shutil.rmtree(temp_dir, ignore_errors=True)
                self.log(f"{t['id']} test attempt {attempt} isolated project copy failed: {exc}")
                with open(os.path.join(ev, f"test-{attempt}.log"), "w", encoding="utf-8") as f:
                    f.write(f"ISOLATED_COPY_FAIL={exc}\nEXIT=1\n")
                return 1

        chunks = []
        try:
            if import_command:
                imported = subprocess.run(import_command, cwd=cwd, env=env,
                                          capture_output=True, text=True)
                import_output = imported.stdout + "\n---STDERR---\n" + imported.stderr
                chunks.append("=== GODOT IMPORT PREFLIGHT ===\n" + import_output +
                              f"\nIMPORT_EXIT={imported.returncode}\n")
                if imported.returncode != 0 or self.has_script_error(import_output):
                    effective_rc = imported.returncode or 1
                    with open(os.path.join(ev, f"test-{attempt}.log"), "w", encoding="utf-8") as f:
                        f.write("\n".join(chunks) + f"\nEXIT={effective_rc}\n")
                    self.log(f"{t['id']} test attempt {attempt} import preflight failed")
                    return effective_rc

            p = subprocess.run(test_command, shell=not isinstance(test_command, list),
                               cwd=cwd, env=env, capture_output=True, text=True)
            test_output = p.stdout + "\n---STDERR---\n" + p.stderr
            chunks.append("=== TEST ===\n" + test_output)
            effective_rc = p.returncode
            if is_core_smoke and (
                    "CORE001 SMOKE PASS" not in p.stdout or
                    "CORE001 SMOKE FAIL" in p.stdout or
                    self.has_script_error(test_output)):
                effective_rc = effective_rc or 1
            with open(os.path.join(ev, f"test-{attempt}.log"), "w", encoding="utf-8") as f:
                f.write("\n".join(chunks) + f"\nEXIT={effective_rc}\n")
            self.log(f"{t['id']} test attempt {attempt} exit={effective_rc}")
            return effective_rc
        finally:
            if temp_dir:
                shutil.rmtree(temp_dir, ignore_errors=True)

    @staticmethod
    def with_godot_project_path(argv, project_root):
        command = list(argv)
        for index, arg in enumerate(command[1:], start=1):
            if arg == "--path" and index + 1 < len(command):
                command[index + 1] = project_root
                return command
            if arg.startswith("--path="):
                command[index] = "--path=" + project_root
                return command
        command[1:1] = ["--path", project_root]
        return command

    @staticmethod
    def has_script_error(output):
        return re.search(r"(?im)^\s*SCRIPT ERROR:", output) is not None

    def commit_success(self, q, t, ev, attempt, trc):
        # 先记录 TASKS.md（Git 可追踪的状态变更），再一次性 commit
        rec = (
            f"\n```text\nID: {t['id']}\nStatus: In Review（AUTO-001 自动通过测试/范围/批准检查，待人工验收）\n"
            f"Owner: AUTO-001 scheduler + headless Qwen Flash (serial)\n"
            f"Executed commands + exit codes: test_cmd={t.get('test_cmd','')} -> {trc}; attempt={attempt}\n"
            f"Test result & evidence: tasks/evidence/{t['id']}/ (会话归档+日志+diff)\n"
            f"Risks & unresolved decisions: 见 tasks/evidence/{t['id']}/phaseA.out 与 report.md\n"
            f"Recorded by AUTO-001 at {now()}\n```\n"
        )
        tasks_md = os.path.join(self.root, "tasks/TASKS.md")
        with open(tasks_md, "a", encoding="utf-8") as f:
            f.write(rec)
        files = self.changed_files_all()
        allowed = t.get("allowed_files", [])
        add = [p for _, p in files if p == "tasks/TASKS.md" or p.startswith(f"tasks/evidence/{t['id']}/")
               or self.allowed_icon_import(p, allowed)
               or any(self.in_glob(p, g) for g in allowed)]
        if add:
            for path in add:
                if self.allowed_icon_import(path, allowed):
                    before = self.stable_file_fingerprint(os.path.join(self.root, path))
                    if before is None:
                        self.block(q, t, f"Godot 导入元数据正在变化或不可读，拒绝提交: {path}")
                        return EXIT_BLOCKED
            add_rc, _, add_err = self.git("add", "--", *add)
            if add_rc != 0:
                self.block(q, t, f"git add 白名单文件失败: {add_err}")
                return EXIT_BLOCKED
            for path in add:
                if self.allowed_icon_import(path, allowed):
                    current = self.stable_file_fingerprint(os.path.join(self.root, path))
                    index_rc, index_blob, _ = self.git("rev-parse", f":{path}")
                    work_rc, work_blob, _ = self.git("hash-object", os.path.join(self.root, path))
                    if current != before or index_rc != 0 or work_rc != 0 or index_blob.strip() != work_blob.strip():
                        self.block(q, t, f"Godot 编辑器并发改写导入元数据，拒绝提交: {path}")
                        return EXIT_BLOCKED
        rc, _, err = self.git("commit", "--only", "--no-verify", "-m",
                              f"AUTO-001 {t['id']}: {t.get('title','')} (tests pass, scope clean)",
                              "--", *add)
        if rc != 0:
            self.block(q, t, f"自动 commit 失败: {err}")
            return EXIT_BLOCKED
        rc2, head, _ = self.git("rev-parse", "--short", "HEAD")
        t["status"] = "in_review"
        t["retries"] = attempt
        t.pop("blocked_reason", None)
        self.save_q(q)
        self.log(f"{t['id']}: 成功 → commit {head} → in_review（不 push）")
        return EXIT_OK

    def changed_files_all(self):
        return self.changed_files() or []

    def block(self, q, t, reason):
        t["status"] = "blocked"
        t["blocked_reason"] = reason
        t["blocked_at"] = now()
        ev = self.evidence_dir(t["id"])
        with open(os.path.join(ev, "BLOCK_REPORT.md"), "a", encoding="utf-8") as f:
            f.write(f"\n# {t['id']} BLOCKED @ {now()}\n\n{reason}\n")
        self.freeze(q, f"{t['id']}: {reason}")

    # ---------- 子命令 ----------
    def cmd_check(self):
        q = self.q()
        ok, why = self.gate_model()
        print(f"model gate: {'PASS' if ok else 'FAIL'} — {why}")
        print(f"patch: {self.patch} exists={os.path.exists(self.patch)}")
        print(f"approvals ledger: {self.approvals_path} sha={self.approvals_hash()}")
        print(f"paused={os.path.exists(self.pause_flag)} frozen={q.get('frozen')}")
        for t in q["tickets"]:
            print(f"  {t['id']:12s} {t['status']:18s} retries={t.get('retries', 0)} {t.get('blocked_reason', '')}")
        return EXIT_OK if ok else EXIT_MODEL

    def cmd_status(self):
        return self.cmd_check()

    def cmd_log(self, n):
        p = os.path.join(self.log_dir, "runner.log")
        if os.path.exists(p):
            tail = open(p, encoding="utf-8").read().splitlines()[-n:]
            print("\n".join(tail))
        return EXIT_OK

    def cmd_pause(self):
        os.makedirs(self.log_dir, exist_ok=True)
        open(self.pause_flag, "w").write(now() + "\n")
        print("PAUSE 已设置：调度器将在下一张票/下一次会话前停止")
        return EXIT_OK

    def cmd_resume(self):
        if os.path.exists(self.pause_flag):
            os.unlink(self.pause_flag)
            print("PAUSE 已清除")
        else:
            print("PAUSE 不存在")
        return EXIT_OK

    def cmd_unfreeze(self, reason):
        q = self.q()
        if not q.get("frozen"):
            print("队列未冻结")
            return EXIT_OK
        q["unfrozen"] = {
            "actor": "Codex (delegated by project owner)",
            "at": now(),
            "reason": reason or "(未注明)",
        }
        q.pop("frozen", None)
        self.save_q(q)
        print("队列已解冻（记录执行者与原因）；blocked 工单状态不会自动改变")
        return EXIT_OK

    def cmd_start(self, only_id):
        if not self.acquire_lock():
            self.log("另一实例正持有锁 → exit 75（单实例串行）")
            return EXIT_LOCK
        try:
            if not os.path.exists(self.patch):
                self.log("缺少 patch 文件，拒绝启动（防云模型回落）")
                return EXIT_MODEL
            if os.path.exists(self.pause_flag):
                self.log("PAUSE 存在 → 不启动；先 resume")
                return EXIT_OK
            q = self.q()
            if q.get("frozen"):
                self.log(f"队列冻结: {q['frozen']} → 需人工 unfreeze")
                return EXIT_FROZEN
            ok, why = self.gate_model()
            if not ok:
                q["frozen"] = {"reason": f"模型门禁失败: {why}", "at": now()}
                self.save_q(q)
                self.log(f"model gate FAIL: {why} → 冻结，不启动任何会话")
                return EXIT_MODEL
            self.log(f"model gate PASS: {why}")
            processed = 0
            while True:
                q = self.q()
                if q.get("frozen"):
                    self.log(f"队列冻结: {q['frozen']['reason']}")
                    return EXIT_FROZEN
                if os.path.exists(self.pause_flag):
                    self.log("检测到 PAUSE → 停止取新票")
                    return EXIT_OK
                todo = [t for t in q["tickets"] if t["status"] in ("ready", "exec_ready")
                        and (not only_id or t["id"] == only_id)]
                if not todo:
                    self.log("无可执行工单（held/awaiting_approval/in_review/blocked 均跳过）")
                    return EXIT_OK
                t = todo[0]
                if any(self.ticket(q, d) is None or self.ticket(q, d)["status"] not in ("in_review", "done")
                       for d in t.get("deps", [])):
                    unmet = [d for d in t.get("deps", [])
                             if self.ticket(q, d) is None or self.ticket(q, d)["status"] not in ("in_review", "done")]
                    self.block(q, t, f"依赖未 Accepted/In-Review: {unmet}")
                    return EXIT_BLOCKED
                processed += 1
                if t["status"] == "ready":
                    rc = self.phase_a(q, t)
                else:
                    rc = self.phase_b(q, t)
                if rc != EXIT_OK:
                    return rc
                if only_id:
                    return EXIT_OK
        finally:
            self.release_lock()


class _Args:
    pass


def main():
    ap = argparse.ArgumentParser(description="AUTO-001 串行工单调度器")
    ap.add_argument("cmd", choices=["start", "check", "status", "log", "pause", "resume", "unfreeze", "selftest"])
    ap.add_argument("--root", default=None)
    ap.add_argument("--queue", default=None)
    ap.add_argument("--approvals", default=None)
    ap.add_argument("--patch", default=None)
    ap.add_argument("--base-url", default=None)
    ap.add_argument("--id", default=None)
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--reason", default=None)
    ap.add_argument("-n", type=int, default=40)
    a = ap.parse_args()
    if a.cmd == "selftest":
        import selftest  # noqa: 同目录
        sys.exit(selftest.run(a))
    r = Runner(a)
    if a.cmd in ("start",):
        sys.exit(r.cmd_start(a.id))
    if a.cmd == "check" or a.cmd == "status":
        sys.exit(r.cmd_check())
    if a.cmd == "log":
        sys.exit(r.cmd_log(a.n))
    if a.cmd == "pause":
        sys.exit(r.cmd_pause())
    if a.cmd == "resume":
        sys.exit(r.cmd_resume())
    if a.cmd == "unfreeze":
        sys.exit(r.cmd_unfreeze(a.reason))


if __name__ == "__main__":
    main()
