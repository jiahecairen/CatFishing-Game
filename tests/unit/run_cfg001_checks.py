#!/usr/bin/env python3
"""CFG-001 自动验收 runner（仅 Python 标准库）。

用法（项目根）：python3 -B tests/unit/run_cfg001_checks.py

按 tasks/evidence/CFG-001/plan.md §5 与 review.md 的契约串行执行：
  先复制工程到系统临时目录，再对副本运行以下步骤：
  step1  Godot --headless --path <isolated-project> --editor --quit （导入/刷新全局类缓存）
  step2  Godot --headless --path <isolated-project> --script res://tests/unit/test_cfg001_config.gd
  step3  Godot --headless --path <isolated-project> --script res://tests/unit/test_core001_smoke.gd （CORE-001 回归）

判定（全部满足才退出 0，否则退出 1；不伪造退出码）：
  - 每步退出码为 0；
  - step2 stdout 含 "CFG001 CONFIG PASS" 且不含 "CFG001 CONFIG FAIL"；
  - step3 stdout 含 "CORE001 SMOKE PASS" 且不含 "CORE001 SMOKE FAIL"；
  - 任一步 stdout/stderr 出现 "SCRIPT ERROR" 即判失败（拒绝对应 FAIL 标记与脚本错误）；
  - 前置：data/ 两份配置与 examples/ 逐值一致（R-4 经济参数防误改，Python 独立复核）。

每步都强制校验 `--path` 与 `cwd` 指向同一隔离副本；若目标是主工程或其他路径，执行前即失败。
临时 HOME 与副本放在同一系统临时目录，排除 `.git`、`.godot` 和滚动写入中的 `tasks/evidence`。
结束后删除该临时目录。本 runner 不会在主工程导入 Godot 资源。GODOT_BIN 环境变量可覆盖引擎路径。
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

CATALOG_FIXTURES = [
    "dup_id.json", "zero_weight.json", "neg_weight.json", "neg_price.json",
    "bad_id.json", "bad_rarity.json", "missing_field.json", "bad_version.json",
    "invalid_json.json", "empty_species.json",
]
RUNTIME_FIXTURES = ["min_gt_max.json", "fps_not_30.json"]


def tail(text, limit=TAIL_LINES):
    lines = (text or "").splitlines()
    return "\n".join(lines[-limit:]) if lines else "(no output)"


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def check_value_lock(problems):
    """data/ 与 examples/ 逐值一致（键序/空白可不同，值必须全等）。"""
    for name in ("fish_species.json", "runtime_config.json"):
        data_path = os.path.join(ROOT, "data", name)
        example_path = os.path.join(ROOT, "examples", name)
        try:
            if load_json(data_path) != load_json(example_path):
                problems.append("value-lock: data/%s != examples/%s (R-4)" % (name, name))
        except Exception as exc:  # noqa: BLE001 - 记录为失败而非崩溃
            problems.append("value-lock: cannot compare %s: %r" % (name, exc))


def check_fixtures(problems):
    fixture_dir = os.path.join(ROOT, "tests", "unit", "fixtures", "cfg001")
    for name in CATALOG_FIXTURES + RUNTIME_FIXTURES:
        path = os.path.join(fixture_dir, name)
        if not os.path.isfile(path):
            problems.append("fixture missing: %s" % name)
            continue
        if name == "invalid_json.json":
            try:
                load_json(path)
                problems.append("fixture %s must stay invalid JSON" % name)
            except json.JSONDecodeError:
                pass
        else:
            try:
                load_json(path)
            except json.JSONDecodeError as exc:
                problems.append("fixture %s is not valid JSON: %s" % (name, exc))


def ignore_copy_artifacts(directory, names):
    ignored = {name for name in names if name in {".git", ".godot"}}
    if os.path.realpath(directory) == os.path.join(os.path.realpath(ROOT), "tasks"):
        if "evidence" in names:
            ignored.add("evidence")
    return ignored


def run_step(step_name, cmd, env, project_root, want_marker=None, forbid_markers=()):
    print("=" * 72)
    print("[%s] $ %s" % (step_name, " ".join(cmd)))
    sys.stdout.flush()
    try:
        path_index = cmd.index("--path")
        command_project = os.path.realpath(cmd[path_index + 1])
    except (ValueError, IndexError):
        print("[%s] FAILED: Godot command has no valid --path" % step_name)
        return False
    expected_project = os.path.realpath(project_root)
    if expected_project == os.path.realpath(ROOT) or command_project != expected_project:
        print("[%s] FAILED: refusing non-isolated Godot project path %s" % (
            step_name, command_project
        ))
        return False
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
    print("CFG-001 runner root: %s" % ROOT)
    print("Godot binary: %s" % GODOT)
    problems = []
    check_value_lock(problems)
    check_fixtures(problems)
    if problems:
        for problem in problems:
            print("PRE-FAIL: %s" % problem)
        print("CFG001 RUNNER FAIL (pre-flight)")
        return 1
    print("pre-flight: data==examples (value-identical), 12 fixtures present")

    run_dir = tempfile.mkdtemp(prefix="run_cfg001_")
    project_dir = os.path.join(run_dir, "project")
    home_dir = os.path.join(run_dir, "home")
    try:
        shutil.copytree(ROOT, project_dir, ignore=ignore_copy_artifacts)
        if os.path.realpath(project_dir) == os.path.realpath(ROOT):
            print("CFG001 RUNNER FAIL: isolated project aliases the source root")
            return 1
        os.makedirs(home_dir)
        env = dict(os.environ)
        env["HOME"] = home_dir
        env["XDG_CONFIG_HOME"] = os.path.join(home_dir, ".config")
        env["XDG_CACHE_HOME"] = os.path.join(home_dir, ".cache")
        print("isolated project copy: %s" % project_dir)
        print("isolated HOME: %s" % home_dir)

        godot_base = [GODOT, "--headless", "--path", project_dir]
        ok = True
        ok = run_step("step1-import", godot_base + ["--editor", "--quit"], env, project_dir) and ok
        ok = run_step(
            "step2-cfg001",
            godot_base + ["--script", "res://tests/unit/test_cfg001_config.gd"],
            env,
            project_dir,
            want_marker="CFG001 CONFIG PASS",
            forbid_markers=("CFG001 CONFIG FAIL",),
        ) and ok
        ok = run_step(
            "step3-core001-regression",
            godot_base + ["--script", "res://tests/unit/test_core001_smoke.gd"],
            env,
            project_dir,
            want_marker="CORE001 SMOKE PASS",
            forbid_markers=("CORE001 SMOKE FAIL",),
        ) and ok
    finally:
        shutil.rmtree(run_dir, ignore_errors=True)
        print("cleaned isolated project and HOME: %s" % run_dir)

    if ok:
        print("CFG001 RUNNER PASS")
        return 0
    print("CFG001 RUNNER FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
