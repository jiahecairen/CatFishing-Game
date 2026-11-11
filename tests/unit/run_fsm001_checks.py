#!/usr/bin/env python3
"""FSM-001 自动验收 runner（仅 Python 标准库，镜像 run_cfg001_checks.py 约定）。

用法（项目根）：python3 -B tests/unit/run_fsm001_checks.py

按 tasks/evidence/FSM-001/plan.md §5 的契约串行执行：
  step1  Godot --headless --path <repo> --editor --quit      （导入/刷新全局类缓存）
  step2  Godot --headless --path <repo> --script res://tests/unit/test_fsm001_fsm.gd
  step3  Godot --headless --path <repo> --script res://tests/unit/test_core001_smoke.gd （CORE-001 回归）
  step4  Godot --headless --path <repo> --script res://tests/unit/test_cfg001_config.gd （CFG-001 回归）

判定（全部满足才退出 0，否则退出 1；不伪造退出码）：
  - 每步真实退出码为 0；
  - step2 stdout 含 "FSM001 FSM PASS" 且不含 "FSM001 FSM FAIL"；
  - step3/4 分别含 "CORE001 SMOKE PASS" / "CFG001 CONFIG PASS"（无对应 FAIL 标记）；
  - 任一步 stdout/stderr 出现 "SCRIPT ERROR" 即判失败；
  - 前置：scripts/fishing 与 tests/unit 交付文件齐全；data/ 与 examples/ 逐值一致
    （R-4 经济参数防误改，Python 独立复核）；cfg001 交界夹具存在。

按 queue 要求把 HOME 指向本票 evidence 目录内的临时目录，隔离 Godot 编辑器用户态；
结束后删除该临时目录。本 runner 对项目树零写入。GODOT_BIN 环境变量可覆盖引擎路径。
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
EVIDENCE = os.path.join(ROOT, "tasks", "evidence", "FSM-001")
TIMEOUT_SEC = 600
TAIL_LINES = 40

DELIVERABLES = [
    "scripts/fishing/deterministic_rng.gd",
    "scripts/fishing/virtual_clock.gd",
    "scripts/fishing/fishing_state_machine.gd",
    "tests/unit/test_fsm001_fsm.gd",
]
FIXTURES = ["min_gt_max.json", "fps_not_30.json", "dup_id.json"]


def tail(text, limit=TAIL_LINES):
    lines = (text or "").splitlines()
    return "\n".join(lines[-limit:]) if lines else "(no output)"


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def check_value_lock(problems):
    """data/ 与 examples/ 逐值一致（R-4：20/60/30/10 与鱼价权重防误改，Python 独立复核）。"""
    for name in ("fish_species.json", "runtime_config.json"):
        data_path = os.path.join(ROOT, "data", name)
        example_path = os.path.join(ROOT, "examples", name)
        try:
            if load_json(data_path) != load_json(example_path):
                problems.append("value-lock: data/%s != examples/%s (R-4)" % (name, name))
        except Exception as exc:  # noqa: BLE001 - 记录为失败而非崩溃
            problems.append("value-lock: cannot compare %s: %r" % (name, exc))


def check_files(problems):
    for rel in DELIVERABLES:
        if not os.path.isfile(os.path.join(ROOT, rel)):
            problems.append("deliverable missing: %s" % rel)
    for name in FIXTURES:
        path = os.path.join(ROOT, "tests", "unit", "fixtures", "cfg001", name)
        if not os.path.isfile(path):
            problems.append("fixture missing: %s (F8/T-CONF-01 交界依赖)" % name)


def run_step(step_name, cmd, env, want_marker=None, forbid_markers=()):
    print("=" * 72)
    print("[%s] $ %s" % (step_name, " ".join(cmd)))
    sys.stdout.flush()
    try:
        proc = subprocess.run(
            cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=TIMEOUT_SEC
        )
    except subprocess.TimeoutExpired:
        print("[%s] TIMEOUT after %ds" % (step_name, TIMEOUT_SEC))
        return False
    except OSError as exc:
        print("[%s] cannot execute Godot (%s): %r" % (step_name, GODOT, exc))
        return False

    failures = []
    print("[%s] exit_code=%d" % (step_name, proc.returncode))
    if proc.returncode != 0:
        failures.append("non-zero exit code %d" % proc.returncode)
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    for marker in ("SCRIPT ERROR",) + tuple(forbid_markers):
        if marker in combined:
            failures.append("forbidden marker %r" % marker)
    if want_marker is not None and want_marker not in (proc.stdout or ""):
        failures.append("missing required marker %r" % want_marker)

    print("[%s] stdout(tail):\n%s" % (step_name, tail(proc.stdout)))
    err = tail(proc.stderr)
    if err != "(no output)":
        print("[%s] stderr(tail):\n%s" % (step_name, err))
    if failures:
        print("[%s] FAILED: %s" % (step_name, "; ".join(failures)))
        return False
    print("[%s] OK" % step_name)
    return True


def main():
    print("FSM-001 runner root: %s" % ROOT)
    print("Godot binary: %s" % GODOT)
    problems = []
    check_files(problems)
    check_value_lock(problems)
    if problems:
        for problem in problems:
            print("PRE-FAIL: %s" % problem)
        print("FSM001 RUNNER FAIL (pre-flight)")
        return 1
    print("pre-flight: deliverables present, data==examples (value-identical), fixtures present")

    home_dir = tempfile.mkdtemp(prefix="run_fsm001_home_", dir=EVIDENCE)
    env = dict(os.environ)
    env["HOME"] = home_dir
    env["XDG_CONFIG_HOME"] = os.path.join(home_dir, ".config")
    env["XDG_CACHE_HOME"] = os.path.join(home_dir, ".cache")
    print("isolated HOME (ticket-local temp): %s" % home_dir)

    godot_base = [GODOT, "--headless", "--path", ROOT]
    try:
        ok = True
        ok = run_step("step1-import", godot_base + ["--editor", "--quit"], env) and ok
        ok = run_step(
            "step2-fsm001",
            godot_base + ["--script", "res://tests/unit/test_fsm001_fsm.gd"],
            env,
            want_marker="FSM001 FSM PASS",
            forbid_markers=("FSM001 FSM FAIL",),
        ) and ok
        ok = run_step(
            "step3-core001-regression",
            godot_base + ["--script", "res://tests/unit/test_core001_smoke.gd"],
            env,
            want_marker="CORE001 SMOKE PASS",
            forbid_markers=("CORE001 SMOKE FAIL",),
        ) and ok
        ok = run_step(
            "step4-cfg001-regression",
            godot_base + ["--script", "res://tests/unit/test_cfg001_config.gd"],
            env,
            want_marker="CFG001 CONFIG PASS",
            forbid_markers=("CFG001 CONFIG FAIL",),
        ) and ok
    finally:
        shutil.rmtree(home_dir, ignore_errors=True)
        print("cleaned isolated HOME: %s" % home_dir)

    if ok:
        print("FSM001 RUNNER PASS")
        return 0
    print("FSM001 RUNNER FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
