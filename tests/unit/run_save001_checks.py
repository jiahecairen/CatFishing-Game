#!/usr/bin/env python3
"""SAVE-001 自动验收 runner（仅 Python 标准库，镜像 run_eco001_checks.py 约定）。

用法（项目根）：python3 -B tests/unit/run_save001_checks.py

按 tasks/evidence/SAVE-001/plan.md §3/§5.3 的契约串行执行（单 runner 串行，无并行）：
  step1  Godot --headless --path <副本> --editor --quit        （先导入再测）
  step2  Godot --headless --path <副本> --script res://tests/unit/test_save001_save.gd
  step3  Godot --headless --path <副本> --script res://tests/unit/test_eco001_economy.gd （ECO 回归）
  step4  Godot --headless --path <副本> --script res://tests/unit/test_core001_smoke.gd  （CORE 回归）
  step5  Godot --headless --path <副本> --script res://tests/unit/test_cfg001_config.gd  （CFG 回归）
  step6  Godot --headless --path <副本> --script res://tests/unit/test_fsm001_fsm.gd     （FSM 回归）

判定（全部满足才退出 0，否则退出 1 并打印 SAVE001 RUNNER FAIL；不伪造退出码）：
  每步真实退出码 0；step2 stdout 恰含一次 "SAVE001 SAVE PASS" 且不含 "SAVE001 SAVE FAIL"；
  step3/4/5/6 分别恰含一次 "ECO001 ECONOMY PASS" / "CORE001 SMOKE PASS" / "CFG001 CONFIG PASS"
  / "FSM001 FSM PASS"（前置红即整票红）；任一步出现 "SCRIPT ERROR" 即判失败。
前置（全过才进入 Godot 步骤，plan §5.3）：
  - 交付文件齐全（scripts/save/ 三文件 + 本票测试 + 回归测试与 CFG 夹具）；
  - value-lock：data/*.json == examples/*.json 逐值、20/60/30/10/鱼价权重锁（R-4 同款）；
  - examples/save_v01.json 仍为 save_version 1 且逐值不变（v1 legacy 合同输入）；
  - schemas/game-save.schema.json 为 v2 契约：additionalProperties false、save_version const 2、
    顶层 required 恰为 13 键（与 SaveValidate.DOC_KEYS 常量表一致）；
  - 无类名冲突：scripts/io/save_service.gd 仍只声明 SaveService；AtomicSaveService/
    SaveValidate/SaveFaults 在 scripts/ 全局唯一（R-1）。

每次测试先把项目复制到系统临时目录，排除 Git、Godot 缓存及任务证据；所有 Godot 导入/测试均在
同一副本串行执行。HOME/XDG 也位于临时目录。副本与用户态临时目录通过 finally 清理，主工程完全
不作为 Godot --path/cwd。GODOT_BIN 可覆盖引擎路径。本票不新增 GUI spike：S0–S8 全为纯业务
内存数据 + headless 单测 + 临时目录文件断言。
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
TIMEOUT_SEC = 600
TAIL_LINES = 40

DELIVERABLES = [
    "scripts/save/save_service.gd",
    "scripts/save/save_validate.gd",
    "scripts/save/save_faults.gd",
    "tests/unit/test_save001_save.gd",
    "tests/unit/run_save001_checks.py",
]
REGRESSIONS = [
    "tests/unit/test_eco001_economy.gd",
    "tests/unit/test_core001_smoke.gd",
    "tests/unit/test_cfg001_config.gd",
    "tests/unit/test_fsm001_fsm.gd",
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

# v1 legacy 合同示例（examples/save_v01.json 必须逐值不变，plan §3「examples 不改」）。
EXPECTED_V1_EXAMPLE = {
    "save_version": 1,
    "revision": 0,
    "wallet_gold": 0,
    "basket_capacity": 10,
    "basket": [],
    "processed_catch_ids": [],
    "processed_sale_ids": [],
    "fishing_checkpoint": {"state": "IDLE", "event_id": None, "wait_seconds": None,
                           "elapsed_effective_seconds": 0},
    "desktop_window": {"x": 80, "y": 80, "width": 220, "height": 160, "display_hint": None},
}

# v2 顶层 13 键（与 SaveValidate.DOC_KEYS / schema required 一致，plan §4.1）。
V2_REQUIRED_KEYS = ["save_version", "revision", "wallet_gold", "basket_capacity", "basket",
                    "processed_catch_ids", "processed_sale_ids", "fishing_checkpoint",
                    "desktop_window", "economy_ledger", "rng_snapshot", "clock_snapshot",
                    "pending_candidate"]

CLASS_NAME_PATTERN = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)


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

def check_v1_example(problems):
    """examples/save_v01.json 仍 save_version 1 且逐值不变（迁移测试的合同输入）。"""
    path = os.path.join(ROOT, "examples", "save_v01.json")
    try:
        example = load_json(path)
        if example.get("save_version") != 1:
            problems.append("v1-lock: examples/save_v01.json save_version != 1")
        if example != EXPECTED_V1_EXAMPLE:
            problems.append("v1-lock: examples/save_v01.json drifted from frozen v1 contract")
    except Exception as exc:  # noqa: BLE001
        problems.append("v1-lock: cannot read examples/save_v01.json: %r" % exc)

def check_schema_v2(problems):
    """schema 为 v2 契约：additionalProperties false、save_version const 2、恰 13 必需键。"""
    path = os.path.join(ROOT, "schemas", "game-save.schema.json")
    try:
        schema = load_json(path)
        if schema.get("additionalProperties") is not False:
            problems.append("schema-lock: additionalProperties must be false")
        version_spec = (schema.get("properties") or {}).get("save_version") or {}
        if version_spec.get("const") != 2:
            problems.append("schema-lock: save_version must be const 2")
        required = schema.get("required") or []
        if sorted(required) != sorted(V2_REQUIRED_KEYS) or len(required) != len(V2_REQUIRED_KEYS):
            problems.append("schema-lock: top-level required must be exactly the 13 v2 keys")
    except Exception as exc:  # noqa: BLE001
        problems.append("schema-lock: cannot read schemas/game-save.schema.json: %r" % exc)

def check_class_names(problems):
    """R-1 类名冲突回归：SaveService 仅在 scripts/io 骨架出现一次；本票三类名全局唯一。"""
    found = {}
    scripts_dir = os.path.join(ROOT, "scripts")
    for base, _dirs, files in os.walk(scripts_dir):
        for name in files:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    text = handle.read()
            except OSError as exc:
                problems.append("class-lock: cannot read %s: %r" % (path, exc))
                continue
            for match in CLASS_NAME_PATTERN.finditer(text):
                found.setdefault(match.group(1), []).append(os.path.relpath(path, ROOT))
    for cls in ("SaveService", "AtomicSaveService", "SaveValidate", "SaveFaults"):
        holders = found.get(cls, [])
        if len(holders) != 1:
            problems.append("class-lock: class_name %s must appear exactly once, got %r" % (cls, holders))
    if found.get("SaveService") != [os.path.join("scripts", "io", "save_service.gd")]:
        problems.append("class-lock: SaveService skeleton must stay exactly at scripts/io/save_service.gd")

def check_files(problems):
    for rel in DELIVERABLES + REGRESSIONS:
        if not os.path.isfile(os.path.join(ROOT, rel)):
            problems.append("deliverable missing: %s" % rel)
    for name in FIXTURES:
        path = os.path.join(ROOT, "tests", "unit", "fixtures", "cfg001", name)
        if not os.path.isfile(path):
            problems.append("fixture missing: %s (CFG-001 回归交界依赖)" % name)

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
    print("SAVE-001 source root: %s" % ROOT)
    print("Godot binary: %s" % GODOT)
    problems = []
    check_files(problems)
    check_value_lock(problems)
    check_v1_example(problems)
    check_schema_v2(problems)
    check_class_names(problems)
    if problems:
        for problem in problems:
            print("PRE-FAIL: %s" % problem)
        print("SAVE001 RUNNER FAIL (pre-flight)")
        return 1
    print("pre-flight: deliverables present, value-lock frozen, v1 example frozen, "
          "schema v2 locked, class names unique, fixtures present")

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
        with tempfile.TemporaryDirectory(prefix="run_save001_") as temp_root:
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
                ("step2-save001", godot_base + ["--script", "res://tests/unit/test_save001_save.gd"],
                 "SAVE001 SAVE PASS", ("SAVE001 SAVE FAIL",)),
                ("step3-eco001-regression", godot_base + ["--script", "res://tests/unit/test_eco001_economy.gd"],
                 "ECO001 ECONOMY PASS", ("ECO001 ECONOMY FAIL",)),
                ("step4-core001-regression", godot_base + ["--script", "res://tests/unit/test_core001_smoke.gd"],
                 "CORE001 SMOKE PASS", ("CORE001 SMOKE FAIL",)),
                ("step5-cfg001-regression", godot_base + ["--script", "res://tests/unit/test_cfg001_config.gd"],
                 "CFG001 CONFIG PASS", ("CFG001 CONFIG FAIL",)),
                ("step6-fsm001-regression", godot_base + ["--script", "res://tests/unit/test_fsm001_fsm.gd"],
                 "FSM001 FSM PASS", ("FSM001 FSM FAIL",)),
            ]
            for name, cmd, marker, forbidden in steps:
                if not run_step(name, cmd, env, project_root,
                                want_marker=marker, forbid_markers=forbidden):
                    print("SAVE001 RUNNER FAIL")
                    return 1

        print("cleaned isolated project and HOME")
        print("SAVE001 RUNNER PASS")
        return 0
    except (OSError, shutil.Error) as exc:
        print("SAVE001 RUNNER FAIL (isolated copy): %r" % exc)
        return 1

if __name__ == "__main__":
    sys.exit(main())
