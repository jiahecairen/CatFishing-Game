#!/usr/bin/env python3
"""ECO-001 自动验收 runner（仅 Python 标准库，镜像 run_fsm001_checks.py 约定）。

用法（项目根）：python3 -B tests/unit/run_eco001_checks.py

按 tasks/evidence/ECO-001/plan.md §3/§5 的契约串行执行（R-5：单 runner 串行，无并行）：
  step1  Godot --headless --path <repo> --editor --quit      （导入/刷新全局类缓存）
  step2  Godot --headless --path <repo> --script res://tests/unit/test_eco001_economy.gd
  step3  Godot --headless --path <repo> --script res://tests/unit/test_core001_smoke.gd  （CORE-001 回归）
  step4  Godot --headless --path <repo> --script res://tests/unit/test_cfg001_config.gd  （CFG-001 回归）
  step5  Godot --headless --path <repo> --script res://tests/unit/test_fsm001_fsm.gd     （FSM-001 回归）

判定（全部满足才退出 0，否则退出 1；不伪造退出码）：每步真实退出码为 0；step2 stdout 含
"ECO001 ECONOMY PASS" 且不含 "ECO001 ECONOMY FAIL"；step3/4/5 分别含 "CORE001 SMOKE PASS" /
"CFG001 CONFIG PASS" / "FSM001 FSM PASS"（前置失败即判本票失败，不得带红提交）；任一步出现
"SCRIPT ERROR" 即判失败；前置：scripts/economy 与 tests/unit 交付文件齐全；data/ 与 examples/
逐值一致且显式锁 20/60/30/10 与鱼价/权重（R-4 经济参数防误改，Python 独立复核）；cfg001 交界
夹具 min_gt_max.json 存在（E9 依赖）。

每次测试先把项目复制到系统临时目录，排除 Git、Godot 缓存及任务证据；所有 Godot 导入/测试均在
同一副本串行执行。HOME/XDG 也位于临时目录。副本与用户态临时目录通过 finally 清理，主工程完全
不作为 Godot --path/cwd。GODOT_BIN 可覆盖引擎路径。本票不新增 GUI spike：E0–E11 全为纯业务
内存数据 + headless 单测（plan R-6）。
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
TIMEOUT_SEC = 600
TAIL_LINES = 40

DELIVERABLES = [
    "scripts/economy/fish_instance.gd",
    "scripts/economy/economy_service.gd",
    "tests/unit/test_eco001_economy.gd",
]
FIXTURES = ["min_gt_max.json"]

# R-4 数值锁（SDD-172/173/175/177 + 2026-11-11 委托冻结）：任何改动即 runner 红。
EXPECTED_RUNTIME = {
    "config_version": 1, "visible_fps": 30, "bite_wait_min_sec": 20,
    "bite_wait_max_sec": 60, "basket_capacity": 10,
}
EXPECTED_SPECIES = {
    "river_carp": {"catch_weight": 60, "base_price": 8},
    "silver_perch": {"catch_weight": 30, "base_price": 16}, "golden_trout": {"catch_weight": 10, "base_price": 32},
}

def tail(text, limit=TAIL_LINES):
    lines = (text or "").splitlines()
    return "\n".join(lines[-limit:]) if lines else "(no output)"

def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)

def check_value_lock(problems):
    """data/ 与 examples/ 逐值一致 + 显式常量锁（R-4：20/60/30/10 与鱼价权重防误改）。"""
    for name in ("fish_species.json", "runtime_config.json"):
        data_path = os.path.join(ROOT, "data", name)
        example_path = os.path.join(ROOT, "examples", name)
        try:
            if load_json(data_path) != load_json(example_path):
                problems.append("value-lock: data/%s != examples/%s (R-4)" % (name, name))
        except Exception as exc:  # noqa: BLE001 - 记录为失败而非崩溃
            problems.append("value-lock: cannot compare %s: %r" % (name, exc))
    try:
        if load_json(os.path.join(ROOT, "data", "runtime_config.json")) != EXPECTED_RUNTIME:
            problems.append("value-lock: runtime_config != frozen 20/60/30/10 v1 (R-4)")
    except Exception as exc:  # noqa: BLE001
        problems.append("value-lock: cannot read runtime_config: %r" % exc)
    try:
        species = {e["id"]: e for e in load_json(os.path.join(ROOT, "data", "fish_species.json"))["species"]}
        if set(species) != set(EXPECTED_SPECIES):
            problems.append("value-lock: species id set drifted (R-4)")
        for sid, want in EXPECTED_SPECIES.items():
            got = species.get(sid, {})
            if got.get("catch_weight") != want["catch_weight"] or got.get("base_price") != want["base_price"]:
                problems.append("value-lock: species %s weight/price drifted (R-4)" % sid)
    except Exception as exc:  # noqa: BLE001
        problems.append("value-lock: cannot read fish_species: %r" % exc)

def check_files(problems):
    for rel in DELIVERABLES:
        if not os.path.isfile(os.path.join(ROOT, rel)):
            problems.append("deliverable missing: %s" % rel)
    for name in FIXTURES:
        path = os.path.join(ROOT, "tests", "unit", "fixtures", "cfg001", name)
        if not os.path.isfile(path):
            problems.append("fixture missing: %s (E9/T-CONF-01 交界依赖)" % name)

def run_step(step_name, cmd, env, project_root, want_marker=None, forbid_markers=()):
    print("=" * 72)
    print("[%s] $ %s" % (step_name, " ".join(cmd)))
    sys.stdout.flush()
    try:
        proc = subprocess.run(
            cmd, cwd=project_root, env=env, capture_output=True, text=True, timeout=TIMEOUT_SEC
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
    if want_marker is not None and (proc.stdout or "").count(want_marker) != 1:
        failures.append("required marker %r must appear exactly once" % want_marker)

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
    print("ECO-001 source root: %s" % ROOT)
    print("Godot binary: %s" % GODOT)
    problems = []
    check_files(problems)
    check_value_lock(problems)
    if problems:
        for problem in problems:
            print("PRE-FAIL: %s" % problem)
        print("ECO001 RUNNER FAIL (pre-flight)")
        return 1
    print("pre-flight: deliverables present, value-lock frozen, fixtures present")

    sensitive_markers = ("API_KEY", "ACCESS_KEY", "PRIVATE_KEY", "TOKEN",
                         "SECRET", "PASSWORD", "CREDENTIAL")
    env = {key: value for key, value in os.environ.items()
           if not any(marker in key.upper() for marker in sensitive_markers)}

    def copy_ignored(directory, names):
        ignored = {name for name in names
                   if name in (".git", ".godot", "__pycache__") or name.endswith(".pyc")}
        if os.path.realpath(directory) == os.path.realpath(os.path.join(ROOT, "tasks")):
            ignored.add("evidence")
        return ignored

    try:
        with tempfile.TemporaryDirectory(prefix="run_eco001_") as temp_root:
            project_root = os.path.join(temp_root, "project")
            shutil.copytree(ROOT, project_root, ignore=copy_ignored)
            home_dir = os.path.join(temp_root, "home"); os.makedirs(home_dir)
            env["HOME"] = home_dir
            env["XDG_CONFIG_HOME"] = os.path.join(home_dir, ".config")
            env["XDG_CACHE_HOME"] = os.path.join(home_dir, ".cache")
            print("isolated project copy: %s" % project_root)
            print("isolated HOME: %s" % home_dir)

            godot_base = [GODOT, "--headless", "--path", project_root]
            steps = [
                ("step1-import", godot_base + ["--editor", "--quit"], None, ()),
                ("step2-eco001", godot_base + ["--script", "res://tests/unit/test_eco001_economy.gd"],
                 "ECO001 ECONOMY PASS", ("ECO001 ECONOMY FAIL",)),
                ("step3-core001-regression", godot_base + ["--script", "res://tests/unit/test_core001_smoke.gd"],
                 "CORE001 SMOKE PASS", ("CORE001 SMOKE FAIL",)),
                ("step4-cfg001-regression", godot_base + ["--script", "res://tests/unit/test_cfg001_config.gd"],
                 "CFG001 CONFIG PASS", ("CFG001 CONFIG FAIL",)),
                ("step5-fsm001-regression", godot_base + ["--script", "res://tests/unit/test_fsm001_fsm.gd"],
                 "FSM001 FSM PASS", ("FSM001 FSM FAIL",)),
            ]
            for name, cmd, marker, forbidden in steps:
                if not run_step(name, cmd, env, project_root,
                                want_marker=marker, forbid_markers=forbidden):
                    print("ECO001 RUNNER FAIL")
                    return 1

        print("cleaned isolated project and HOME")
        print("ECO001 RUNNER PASS")
        return 0
    except (OSError, shutil.Error) as exc:
        print("ECO001 RUNNER FAIL (isolated copy): %r" % exc)
        return 1

if __name__ == "__main__":
    sys.exit(main())
