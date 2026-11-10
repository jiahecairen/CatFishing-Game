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
"""
import importlib
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SIMROOT = "/tmp/dsh-auto-001/selftest"
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
    rc = R.cmd_start("SIM-T-01")
    qq = json.load(open(q))
    check("T4a 模型不可达 exit 60", rc == 60, f"rc={rc}")
    check("T4b 队列被冻结", bool(qq.get("frozen")))
    check("T4c 未发起任何会话", not os.path.isdir(R.session_slug_dir()))

    # ---- T5 成功路径 → commit
    root = make_sim("t5-commit", "ok_write", ledger=True)
    q = write_queue(root, [ticket()])
    R = mk_runner(r, root, q, write_approvals(root))
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
    rc = R.cmd_start("SIM-T-01")
    qq = json.load(open(q))
    check("T7a 篡改账本 → Blocked+冻结", rc == 66 and bool(qq.get("frozen")), f"rc={rc}")
    check("T7b 冻结原因含伪造", "伪造" in (qq.get("frozen") or {}).get("reason", ""))
    check("T7c 不 commit 任何内容", git_n_commits(root) == 1)

    ok = all(c for _, c in RESULTS)
    os.makedirs(SIMROOT, exist_ok=True)
    with open(os.path.join(SIMROOT, "report.txt"), "w") as f:
        f.write(f"AUTO-001 selftest {time.strftime('%F %T %z')}\n")
        for n, c in RESULTS:
            f.write(("PASS " if c else "FAIL ") + n + "\n")
        f.write(f"\n{'ALL PASS' if ok else 'FAILURES PRESENT'} ({len(RESULTS)} checks, {time.time()-t0:.1f}s)\n")
    print(f"\n{'ALL PASS' if ok else 'FAILURES PRESENT'} — report: {SIMROOT}/report.txt")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(run(None))
