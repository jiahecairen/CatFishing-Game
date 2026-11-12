#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AUTO-001 selftest — 调度器门禁的确定性回归（/tmp 合成工程 + dsh stub，不依赖真实模型）。

必须全绿才可开始真实工单：
  T1 范围检查：越界文件与 APPROVALS.md 改动必被识别
  T2 批准解析：人工记录通过；示例注释/错票号不通过
  T3 无批准记录 → Phase B 拒绝启动（exit 65），零代码改动
  T4 模型门禁失败 → exit 60 + 队列冻结 + 不发起任何会话
  T5 成功路径 → 自动 commit + TASKS.md 记录 + in_review（dsh stub 写码）
  T6 持续测试失败 → 首跑+重试2次后 Blocked + 冻结 + 不 commit + 证据保留
  T7 会话篡改 APPROVALS.md → 立即 Blocked + 冻结（防伪造批准）
  T8 tracked/untracked queue 归属校验，tools/auto 其他文件仍受范围保护
  T9 仅允许随 icon.svg 生成的 icon.svg.import
  T10 CORE smoke 先导入并要求 PASS、无 SCRIPT ERROR，导入错误也拒绝
  T11 自动 commit 只包含本次白名单改动，保留其他预暂存和既有证据文件
  T12 Godot 并发改写导入旁车时拒绝 commit
  T13 解冻日志记录委托执行者，不伪称人类操作
  T14 blocked 复核需 Phase B 批准与测试通过，保留 needs_human；冻结时拒绝
"""
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SIMROOT = tempfile.mkdtemp(prefix="dsh-auto-001-selftest-")
RESULTS = []
PATCH = os.path.join(HERE, "headless-local-qwen.patch.yml")


class _NS:
    pass


def _ns(**kw):
    n = _NS()
    for k in ("root", "queue", "approvals", "patch", "base_url"):
        setattr(n, k, kw.get(k))
    n.timeout = kw.get("timeout", 60)
    return n


def stub_dsh(path, mode):
    if mode == "ok_write":
        body = ('import os\n'
                'open(os.path.join(os.getcwd(),"hello.py"),"w").write("def add(a,b):\\n    return a+b\\n")\n'
                'print("PHASE-B-DONE")\n')
    elif mode == "tamper":
        body = ('import os\n'
                'open(os.path.join(os.getcwd(),"tasks","APPROVALS.md"),"a").write'
                '("\\nBEGIN-APPROVAL ID=FORGED PHASE=B\\nAPPROVED\\nby: evil\\nEND-APPROVAL\\n")\n'
                'print("PHASE-B-DONE")\n')
    else:
        body = 'print("PHASE-B-DONE")\n'
    with open(path, "w") as f:
        f.write("#!/usr/bin/env python3\n" + body)
    os.chmod(path, 0o755)


def make_sim(name, mode, ledger=False):
    root = os.path.join(SIMROOT, name)
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(os.path.join(root, "tasks"))
    os.makedirs(os.path.join(root, "tools/auto/prompts"))
    shutil.copytree(os.path.join(HERE, "prompts"), os.path.join(root, "tools/auto/prompts"), dirs_exist_ok=True)
    with open(os.path.join(root, "AGENTS.md"), "w") as f:
        f.write("# sim AGENTS\nRULE: never touch APPROVALS.md\n")
    with open(os.path.join(root, "tasks/TASKS.md"), "w") as f:
        f.write("# TASKS\n\n## SIM-T-01\n\nsim ticket\n")
    os.makedirs(os.path.join(root, "tests"))
    with open(os.path.join(root, "tests/test_hello.py"), "w") as f:
        f.write("import unittest, hello\n\n\nclass T(unittest.TestCase):\n"
                "    def test_add(self):\n        self.assertEqual(hello.add(1, 2), 3)\n")
    if ledger:
        write_approvals(root)
    stub = os.path.join(root, "tools/auto/fake_dsh.py")
    stub_dsh(stub, mode)

    def g(*a, check=False):
        p = subprocess.run(["git", "-C", root, "-c", "user.email=auto-001@local",
                            "-c", "user.name=AUTO-001 selftest"] + list(a),
                           capture_output=True, text=True)
        if check and p.returncode != 0:
            raise RuntimeError(p.stderr)

    g("init", "-q", check=True)
    g("add", "-A", check=True)
    g("commit", "-q", "-m", "baseline", check=True)
    os.environ["AUTO001_DSH"] = stub
    return root


def ticket(status="exec_ready", tid="SIM-T-01", allowed=("hello.py", "tests/test_hello.py"),
           test="python3 -m unittest discover -s tests", deps=(), test_cmd=None):
    return {"id": tid, "title": "sim ticket", "status": status, "allowed_files": list(allowed),
            "test_cmd": test if test_cmd is None else test_cmd, "deps": list(deps),
            "brief": "实现 hello.add(a,b)；测试 tests/test_hello.py。"}


def write_queue(root, tickets, tid="SIM-T-01"):
    q = {"version": 1, "updated": "", "tickets": [dict(t) for t in tickets]}
    p = os.path.join(root, "tools/auto/queue.json")
    with open(p, "w") as f:
        json.dump(q, f, ensure_ascii=False, indent=2)
    return p


def write_approvals(root, tid="SIM-T-01", real=True):
    p = os.path.join(root, "tasks", "APPROVALS.md")
    txt = "# APPROVALS (sim)\n\nBEGIN-EXAMPLE-ONLY ID=SIM-T-01 PHASE=B\nAPPROVED\nby: nobody\nEND-EXAMPLE-ONLY\n"
    if real:
        txt += (f"\nBEGIN-APPROVAL ID={tid} PHASE=B\nAPPROVED\nby: rain\n"
                f"scope: hello.py; tests/**\ndate: 2026-11-10\nEND-APPROVAL\n")
    with open(p, "w") as f:
        f.write(txt)
    return p


def missing_approvals(root):
    return os.path.join(root, "tasks", "APPROVALS-MISSING.md")


def runner_mod():
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    if "runner" in sys.modules:
        del sys.modules["runner"]
    return importlib.import_module("runner")


def mk_runner(r, root, queue, approvals, base=None, timeout=60):
    return r.Runner(_ns(root=root, queue=queue, approvals=approvals, patch=PATCH,
                         base_url=base, timeout=timeout))


def git_n_commits(root):
    p = subprocess.run(["git", "-C", root, "rev-list", "--count", "HEAD"], capture_output=True, text=True)
    return int(p.stdout.strip()) if p.returncode == 0 else -1


def git_dirty(root):
    p = subprocess.run(["git", "-C", root, "status", "--porcelain"], capture_output=True, text=True)
    return [l for l in p.stdout.splitlines() if l.strip()]


def check(name, cond, detail=""):
    RESULTS.append((name, bool(cond)))
    print(("PASS " if cond else "FAIL ") + name + (" — " + detail if detail else ""), flush=True)


def run(_a):
    t0 = time.time()
    r = runner_mod()

    # ---- T1 范围检查
    root = make_sim("t1-scope", "noop", ledger=True)
    R = mk_runner(r, root, write_queue(root, [ticket()]), write_approvals(root))
    with open(os.path.join(root, "evil.txt"), "w") as f:
        f.write("x")
    _, bad = R.scope_violations(["hello.py"])
    check("T1a 越界文件被识别", any(p == "evil.txt" for _, p, _ in bad))
    with open(os.path.join(root, "tasks/APPROVALS.md"), "a") as f:
        f.write("FORGE\n")
    _, bad = R.scope_violations(["hello.py"])
    check("T1b APPROVALS.md 改动永远越界", any(p == "tasks/APPROVALS.md" for _, p, _ in bad))

    # ---- T8 tracked queue: runner 自有状态可变，Agent 篡改仍越界
    root = make_sim("t8-queue-ownership", "noop")
    qpath = write_queue(root, [ticket()])
    gargs = ["git", "-C", root, "-c", "user.email=auto-001@local", "-c",
             "user.name=AUTO-001 selftest"]
    subprocess.run(gargs + ["add", "--", "tools/auto/queue.json"], check=True,
                   capture_output=True, text=True)
    subprocess.run(gargs + ["commit", "-q", "-m", "track queue"], check=True,
                   capture_output=True, text=True)
    R = mk_runner(r, root, qpath, write_approvals(root))
    qdata = json.load(open(qpath))
    qdata["runner_state_test"] = "saved-by-runner"
    R.save_q(qdata)
    _, bad = R.scope_violations(["hello.py"])
    check("T8a runner 更新 tracked queue 不触发越界", not any(p == "tools/auto/queue.json" for _, p, _ in bad))
    with open(qpath, "a") as f:
        f.write("\n")
    _, bad = R.scope_violations(["hello.py"])
    check("T8b 会话改写 tracked queue 必被拦截",
          any(p == "tools/auto/queue.json" and "队列文件" in why for _, p, why in bad))

    root = make_sim("t8b-auto-dir", "noop")
    qpath = write_queue(root, [ticket()])
    R = mk_runner(r, root, qpath, write_approvals(root))
    with open(os.path.join(root, "tools/auto/fake_dsh.py"), "a") as f:
        f.write("# unexpected edit\n")
    _, bad = R.scope_violations(["hello.py"])
    check("T8c tools/auto 其他文件仍受范围门禁保护",
          any(p == "tools/auto/fake_dsh.py" for _, p, _ in bad))
    with open(qpath, "a") as f:
        f.write("\\n")
    _, bad = R.scope_violations(["hello.py"])
    check("T8d untracked queue 被会话改写也必拦截",
          any(p == "tools/auto/queue.json" and "队列文件" in why for _, p, why in bad))

    # ---- T8e tracked queue 缺少可信初始指纹时 fail closed
    root = make_sim("t8e-missing-queue-fingerprint", "noop")
    qpath = write_queue(root, [ticket()])
    subprocess.run(["git", "-C", root, "-c", "user.email=auto-001@local", "-c",
                    "user.name=AUTO-001 selftest", "add", "--", "tools/auto/queue.json"],
                   check=True, capture_output=True, text=True)
    subprocess.run(["git", "-C", root, "-c", "user.email=auto-001@local", "-c",
                    "user.name=AUTO-001 selftest", "commit", "-q", "-m", "track queue"],
                   check=True, capture_output=True, text=True)
    os.unlink(qpath)
    R = mk_runner(r, root, qpath, write_approvals(root))
    _, bad = R.scope_violations(["hello.py"])
    check("T8e 初始队列指纹缺失时 tracked 删除仍被拦截",
          any(p == "tools/auto/queue.json" and "队列文件" in why for _, p, why in bad))

    # ---- T9 Godot 允许文件的唯一明确导入旁车
    root = make_sim("t9-import-sidecar", "noop")
    qpath = write_queue(root, [ticket(allowed=("icon.svg",))])
    R = mk_runner(r, root, qpath, write_approvals(root))
    with open(os.path.join(root, "icon.svg.import"), "w") as f:
        f.write('[remap]\\nimporter="texture"\\n')
    _, bad = R.scope_violations(["icon.svg"])
    check("T9a icon.svg.import 随允许的 icon.svg 归属", not any(p == "icon.svg.import" for _, p, _ in bad))
    with open(os.path.join(root, "unrelated.svg.import"), "w") as f:
        f.write("not allowed\\n")
    _, bad = R.scope_violations(["icon.svg"])
    check("T9b 其他 import 文件不因旁车规则获豁免",
          any(p == "unrelated.svg.import" for _, p, _ in bad))

    # ---- T10 CORE 冒烟测试必须先导入、输出 PASS 且无 SCRIPT ERROR
    root = make_sim("t10-smoke-contract", "noop")
    with open(os.path.join(root, "project.godot"), "w") as f:
        f.write("config_version=5\n")
    os.makedirs(os.path.join(root, ".godot"), exist_ok=True)
    with open(os.path.join(root, ".godot", "must_not_copy"), "w") as f:
        f.write("editor cache\n")
    qpath = write_queue(root, [ticket()])
    R = mk_runner(r, root, qpath, write_approvals(root))
    ev = os.path.join(root, "tasks/evidence/SIM-T-01")
    os.makedirs(ev, exist_ok=True)
    smoke_ticket = ticket(test_cmd=("/Applications/Godot.app/Contents/MacOS/Godot --headless "
                                    f"--path {root} --script res://tests/unit/test_core001_smoke.gd"))
    calls = []
    copy_observation = {}
    fake_result = {"stdout": "CORE001 SMOKE PASS\n", "stderr": ""}
    fake_import_result = {"stdout": "Godot import complete\\n", "stderr": ""}
    original_run = subprocess.run
    secret_env_name = "AUTO001_SELFTEST_API_KEY"
    had_secret_env = secret_env_name in os.environ
    previous_secret_env = os.environ.get(secret_env_name)

    def path_arg(call):
        cmd = call[1]
        for i, arg in enumerate(cmd[:-1]):
            if arg == "--path":
                return cmd[i + 1]
        return next((arg.split("=", 1)[1] for arg in cmd if arg.startswith("--path=")), None)

    def fake_run(command, **kwargs):
        if isinstance(command, list) and "--editor" in command:
            calls.append(("import", command, kwargs))
            project_path = path_arg(calls[-1])
            copy_observation.update({
                "path": bool(project_path and project_path != root and os.path.isdir(project_path)),
                "project_file": bool(project_path and os.path.isfile(os.path.join(project_path, "project.godot"))),
                "git_excluded": bool(project_path and not os.path.exists(os.path.join(project_path, ".git"))),
                "godot_cache_excluded": bool(project_path and not os.path.exists(os.path.join(project_path, ".godot"))),
                "evidence_excluded": bool(project_path and not os.path.exists(os.path.join(project_path, "tasks", "evidence"))),
            })
            return subprocess.CompletedProcess(command, 0, fake_import_result["stdout"], fake_import_result["stderr"])
        calls.append(("test", command, kwargs))
        return subprocess.CompletedProcess(command, 0, fake_result["stdout"], fake_result["stderr"])

    try:
        os.environ[secret_env_name] = "selftest sentinel"
        subprocess.run = fake_run
        rc = R.run_test(smoke_ticket, ev, 1)
        import_call = next((call for call in calls if call[0] == "import"), None)
        test_call = next((call for call in calls if call[0] == "test"), None)
        isolated_path = path_arg(import_call) if import_call else None
        copy_checks = dict(copy_observation)
        copy_ok = all(copy_checks.values())
        env_import = import_call[2].get("env", {}) if import_call else {}
        env_test = test_call[2].get("env", {}) if test_call else {}
        isolated_env = bool(import_call and test_call and
                            import_call[2].get("cwd") == isolated_path and
                            test_call[2].get("cwd") == isolated_path and
                            env_import.get("HOME", "") != os.path.expanduser("~") and
                            secret_env_name not in env_import and
                            env_import == env_test)
        check("T10a CORE 先在隔离副本导入，再执行 smoke", rc == 0 and
              import_call is not None and test_call is not None and
              "--editor" in import_call[1] and "--quit" in import_call[1] and
              path_arg(test_call) == isolated_path and copy_ok and isolated_env,
              f"rc={rc}; copy_checks={copy_checks}; isolated_env={isolated_env}")
        check("T10a2 CORE 测试结束后删除临时副本", bool(isolated_path) and not os.path.exists(isolated_path))
        fake_result["stdout"] = "Godot Engine started but script did not run\\n"
        rc_missing = R.run_test(smoke_ticket, ev, 2)
        check("T10b 缺少 CORE001 SMOKE PASS 即失败", rc_missing != 0)
        fake_result["stdout"] = "CORE001 SMOKE PASS\n"
        fake_result["stderr"] = "SCRIPT ERROR: parse failed\\n"
        rc_script_error = R.run_test(smoke_ticket, ev, 3)
        check("T10c 有 SCRIPT ERROR 即失败，即使退出码为零", rc_script_error != 0)
        calls.clear()
        fake_import_result["stderr"] = "SCRIPT ERROR: import failed\\n"
        rc_import_error = R.run_test(smoke_ticket, ev, 4)
        check("T10d 导入阶段脚本错误时不执行 smoke", rc_import_error != 0 and
              len(calls) == 1 and calls[0][0] == "import")
    finally:
        subprocess.run = original_run
        if had_secret_env:
            os.environ[secret_env_name] = previous_secret_env
        else:
            os.environ.pop(secret_env_name, None)

    # ---- T11 自动提交只提交白名单路径，保留预先暂存的越界文件
    root = make_sim("t11-commit-whitelist", "noop")
    qpath = write_queue(root, [ticket(allowed=("hello.py", "icon.svg"))])
    qdata = json.load(open(qpath))
    R = mk_runner(r, root, qpath, write_approvals(root))
    ev = os.path.join(root, "tasks/evidence/SIM-T-01")
    os.makedirs(ev, exist_ok=True)
    with open(os.path.join(root, "evil.txt"), "w") as f:
        f.write("must stay staged and uncommitted\\n")
    subprocess.run(gargs[:2] + [root] + gargs[3:] + ["add", "--", "evil.txt"],
                   check=True, capture_output=True, text=True)
    with open(os.path.join(root, "hello.py"), "w") as f:
        f.write("def add(a, b): return a + b\\n")
    with open(os.path.join(root, "icon.svg"), "w") as f:
        f.write("<svg></svg>\\n")
    with open(os.path.join(root, "icon.svg.import"), "w") as f:
        f.write('[remap]\\nimporter="texture"\\n')
    ticket_data = ticket(allowed=("hello.py", "icon.svg"))
    commit_rc = R.commit_success(qdata, ticket_data, ev, 1, 0)
    shown = subprocess.run(["git", "-C", root, "show", "--format=", "--name-only", "HEAD"],
                           check=True, capture_output=True, text=True).stdout.splitlines()
    staged = subprocess.run(["git", "-C", root, "diff", "--cached", "--name-only"],
                            check=True, capture_output=True, text=True).stdout.splitlines()
    check("T11a 自动提交只含白名单及 icon 对应导入旁车",
          commit_rc == 0 and set(shown) == {"hello.py", "icon.svg", "icon.svg.import", "tasks/TASKS.md"}, str(shown))
    check("T11b 越界预暂存文件保留且未混入 commit", "evil.txt" not in shown and "evil.txt" in staged,
          f"commit={shown}; staged={staged}")

    # ---- T11c 启动前已存在的未跟踪工单证据不得被本次提交带入
    root = make_sim("t11c-preserve-existing-evidence", "noop")
    qpath = write_queue(root, [ticket(allowed=("hello.py",))])
    ev = os.path.join(root, "tasks/evidence/SIM-T-01")
    os.makedirs(ev, exist_ok=True)
    preexisting = os.path.join(ev, "user-session.jsonl.zst")
    with open(preexisting, "wb") as f:
        f.write(b"pre-existing user evidence\\n")
    qdata = json.load(open(qpath))
    R = mk_runner(r, root, qpath, write_approvals(root))
    with open(os.path.join(root, "hello.py"), "w") as f:
        f.write("def add(a, b): return a + b\\n")
    rc = R.commit_success(qdata, ticket(allowed=("hello.py",)), ev, 1, 0)
    shown = subprocess.run(["git", "-C", root, "show", "--format=", "--name-only", "HEAD"],
                           check=True, capture_output=True, text=True).stdout.splitlines()
    porcelain = subprocess.run(["git", "-C", root, "status", "--porcelain=v1", "--untracked-files=all"],
                               check=True, capture_output=True, text=True).stdout
    check("T11c 启动前未跟踪证据保留且不进入本次 commit",
          rc == 0 and preexisting not in shown and
          "tasks/evidence/SIM-T-01/user-session.jsonl.zst" in porcelain,
          f"commit={shown}; status={porcelain.splitlines()}")

    # ---- T12 导入期间被 Godot 编辑器改写时拒绝自动提交
    root = make_sim("t12-import-race", "noop")
    qpath = write_queue(root, [ticket(allowed=("icon.svg",))])
    qdata = json.load(open(qpath))
    R = mk_runner(r, root, qpath, write_approvals(root))
    ev = os.path.join(root, "tasks/evidence/SIM-T-01")
    os.makedirs(ev, exist_ok=True)
    with open(os.path.join(root, "icon.svg"), "w") as f:
        f.write("<svg></svg>\\n")
    with open(os.path.join(root, "icon.svg.import"), "w") as f:
        f.write('[remap]\\nimporter="texture"\\n')
    fingerprints = iter(("stable-before", "changed-during-add"))
    R.stable_file_fingerprint = lambda _path: next(fingerprints)
    race_rc = R.commit_success(qdata, ticket(allowed=("icon.svg",)), ev, 1, 0)
    check("T12 并发改写导入旁车时冻结且不 commit",
          race_rc == 66 and git_n_commits(root) == 1)

    # ---- T13 解冻审计记录应区分委托执行者与直接人工命令
    root = make_sim("t13-unfreeze-audit", "noop")
    qpath = write_queue(root, [ticket()])
    R = mk_runner(r, root, qpath, write_approvals(root))
    qdata = R.q()
    qdata["frozen"] = {"reason": "selftest simulated freeze"}
    R.save_q(qdata)
    unfreeze_rc = R.cmd_unfreeze("selftest delegated recovery")
    q_after = R.q()
    check("T13 解冻元数据如实记录 actor/原因",
          unfreeze_rc == 0 and not q_after.get("frozen") and
          q_after.get("unfrozen", {}).get("actor") == "Codex (delegated by project owner)" and
          q_after.get("unfrozen", {}).get("reason") == "selftest delegated recovery")

    # ---- T14 blocked 票只能经批准+重测进入 in_review，保留人工门
    root = make_sim("t14-reconcile-review", "noop", ledger=True)
    blocked_ticket = ticket(status="blocked")
    blocked_ticket.update({"needs_human": True, "retries": 3,
                           "blocked_reason": "stale failure before committed fix"})
    qpath = write_queue(root, [blocked_ticket])
    R = mk_runner(r, root, qpath, write_approvals(root))

    def fake_recovery_test(_ticket, evidence_dir, attempt):
        with open(os.path.join(evidence_dir, f"test-{attempt}.log"), "w") as f:
            f.write("RECOVERY TEST PASS\\nEXIT=0\\n")
        return 0

    R.run_test = fake_recovery_test
    reconcile_rc = R.cmd_reconcile_review("SIM-T-01", "selftest verified approved recovery")
    q_after = R.q()
    recovered = R.ticket(q_after, "SIM-T-01")
    status_after = [line for line in git_dirty(root)
                    if not line.startswith("?? tasks/evidence/_runner/")]
    latest_paths = subprocess.run(["git", "-C", root, "show", "--format=", "--name-only", "HEAD"],
                                  check=True, capture_output=True, text=True).stdout.splitlines()
    check("T14a blocked 复核后进入 in_review 且保留 needs_human",
          reconcile_rc == 0 and recovered["status"] == "in_review" and
          recovered.get("needs_human") is True and
          recovered.get("recovery_history", [{}])[-1].get("reason") ==
          "selftest verified approved recovery")
    check("T14b 复核提交 queue 状态且工作树 clean",
          "tools/auto/queue.json" in latest_paths and status_after == [],
          f"latest={latest_paths}; status={status_after}")

    root = make_sim("t14c-reconcile-frozen", "noop", ledger=True)
    blocked_ticket = ticket(status="blocked")
    qpath = write_queue(root, [blocked_ticket])
    qdata = json.load(open(qpath))
    qdata["frozen"] = {"reason": "must remain frozen"}
    with open(qpath, "w") as f:
        json.dump(qdata, f)
    R = mk_runner(r, root, qpath, write_approvals(root))
    frozen_rc = R.cmd_reconcile_review("SIM-T-01", "must refuse while frozen")
    q_after = R.q()
    check("T14c frozen 队列拒绝复核且不自动解冻",
          frozen_rc == 76 and bool(q_after.get("frozen")) and
          q_after["tickets"][0]["status"] == "blocked")

    # ---- T2 批准解析
    root = make_sim("t2-approval", "noop")
    ap = write_approvals(root, real=False)
    R = mk_runner(r, root, write_queue(root, [ticket()]), ap)
    check("T2a 示例占位不算批准", R.approval("SIM-T-01", "B") is None)
    write_approvals(root, real=True)
    check("T2b 人工批准记录通过解析", R.approval("SIM-T-01", "B") is not None)
    check("T2c 错票号不通过", R.approval("OTHER-001", "B") is None)

    # ---- T3 无批准记录 → 拒绝 Phase B
    root = make_sim("t3-noapprove", "noop")
    q = write_queue(root, [ticket()])
    R = mk_runner(r, root, q, missing_approvals(root))
    R.gate_model = lambda: (True, "selftest stub")
    rc = R.cmd_start("SIM-T-01")
    dirty = [l for l in git_dirty(root) if "tools/auto/" not in l and "tasks/evidence/" not in l]
    qq = json.load(open(q))
    check("T3a 无批准 exit 65 且不启动会话", rc == 65, f"rc={rc}")
    check("T3b 零代码改动", dirty == [], f"dirty={dirty}")
    check("T3c 工单仍为 exec_ready（未被自动批准）", qq["tickets"][0]["status"] == "exec_ready")

    # ---- T4 模型门禁
    root = make_sim("t4-model", "noop")
    q = write_queue(root, [ticket(status="ready")])
    R = mk_runner(r, root, q, write_approvals(root), base="http://127.0.0.1:59999/v1")
    R.gate_model = lambda: (False, "selftest model unavailable")
    rc = R.cmd_start("SIM-T-01")
    qq = json.load(open(q))
    check("T4a 模型不可达 exit 60", rc == 60, f"rc={rc}")
    check("T4b 队列被冻结", bool(qq.get("frozen")))
    check("T4c 未发起任何会话", not os.path.isdir(R.session_slug_dir()))

    # ---- T5 成功路径 → commit
    root = make_sim("t5-commit", "ok_write", ledger=True)
    q = write_queue(root, [ticket()])
    R = mk_runner(r, root, q, write_approvals(root))
    R.gate_model = lambda: (True, "selftest stub")
    n0 = git_n_commits(root)
    rc = R.cmd_start("SIM-T-01")
    qq = json.load(open(q))
    ev = os.path.join(root, "tasks/evidence/SIM-T-01")
    check("T5a 成功路径 exit 0", rc == 0, f"rc={rc}")
    check("T5b 代码文件由会话写出", os.path.exists(os.path.join(root, "hello.py")))
    check("T5c 自动 commit 生成", git_n_commits(root) == n0 + 1)
    check("T5d TASKS.md 含 AUTO-001 记录", "Recorded by AUTO-001" in open(os.path.join(root, "tasks/TASKS.md")).read())
    check("T5e 状态 in_review", qq["tickets"][0]["status"] == "in_review")
    check("T5f 证据齐全(test/session-tag/out)", all(os.path.exists(os.path.join(ev, x))
          for x in ("test-1.log", "phaseB-1.out")))

    # ---- T6 持续失败 → 重试上限后冻结，不 commit
    root = make_sim("t6-retry", "noop", ledger=True)
    q = write_queue(root, [ticket()])
    R = mk_runner(r, root, q, write_approvals(root))
    R.gate_model = lambda: (True, "selftest stub")
    n0 = git_n_commits(root)
    rc = R.cmd_start("SIM-T-01")
    qq = json.load(open(q))
    ev = os.path.join(root, "tasks/evidence/SIM-T-01")
    logs = [x for x in os.listdir(ev) if x.startswith("test-")] if os.path.isdir(ev) else []
    check("T6a 重试耗尽后 exit 66", rc == 66, f"rc={rc}")
    check("T6b 共 3 次尝试(首跑+2 重试)", sorted(logs) == ["test-1.log", "test-2.log", "test-3.log"], str(logs))
    check("T6c 无自动 commit 失败代码", git_n_commits(root) == n0)
    check("T6d 队列冻结", bool(qq.get("frozen")))
    check("T6e BLOCK_REPORT 与 diff 证据保留", os.path.exists(os.path.join(ev, "BLOCK_REPORT.md")))

    # ---- T7 会话篡改批准账本
    root = make_sim("t7-tamper", "tamper", ledger=True)
    q = write_queue(root, [ticket(test="python3 -c pass")])
    ap = write_approvals(root)
    R = mk_runner(r, root, q, ap)
    R.gate_model = lambda: (True, "selftest stub")
    rc = R.cmd_start("SIM-T-01")
    qq = json.load(open(q))
    check("T7a 篡改账本 → Blocked+冻结", rc == 66 and bool(qq.get("frozen")), f"rc={rc}")
    check("T7b 冻结原因含伪造", "伪造" in (qq.get("frozen") or {}).get("reason", ""))
    check("T7c 不 commit 任何内容", git_n_commits(root) == 1)

    ok = all(c for _, c in RESULTS)
    with open(os.path.join(SIMROOT, "report.txt"), "w") as f:
        f.write(f"AUTO-001 selftest {time.strftime('%F %T %z')}\n")
        for n, c in RESULTS:
            f.write(("PASS " if c else "FAIL ") + n + "\n")
        f.write(f"\n{'ALL PASS' if ok else 'FAILURES PRESENT'} ({len(RESULTS)} checks, {time.time()-t0:.1f}s)\n")
    print(f"\n{'ALL PASS' if ok else 'FAILURES PRESENT'} — report: {SIMROOT}/report.txt")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(run(None))
