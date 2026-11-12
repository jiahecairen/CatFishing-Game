#!/usr/bin/env python3
"""LOG-001 isolated Godot validation runner (Python standard library only).

Run from the project root with: python3 -B tests/unit/run_log001_checks.py
All Godot commands run in a temporary project copy with an isolated HOME
(import first, then LOG/UI/SAVE/CORE regression scripts, one serial step each).
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
TAIL_LINES = 36

LOG_TEST = ("step2-log001", "tests/unit/test_log001_log.gd", "LOG001 LOG PASS", "LOG001 LOG FAIL")
REGRESSIONS = [
    ("step3-ui001", "tests/unit/test_ui001_ui.gd", "UI001 UI PASS", "UI001 UI FAIL"),
    ("step4-save001", "tests/unit/test_save001_save.gd", "SAVE001 SAVE PASS", "SAVE001 SAVE FAIL"),
    ("step5-core001", "tests/unit/test_core001_smoke.gd", "CORE001 SMOKE PASS", "CORE001 SMOKE FAIL"),
]
DELIVERABLES = [
    "scripts/io/event_log.gd",
    "scripts/ui/fishing_session.gd",
    "tests/unit/test_log001_log.gd",
]

# LOG-001 preflight static scan: EventLog must never touch networking or the
# environment (SDD V01-L01 "no silent upload" is enforced structurally).
FORBIDDEN_EVENT_LOG_APIS = [
    "HTTPClient", "HTTPRequest", "WebSocketPeer", "WebRTCMultiplayerPeer",
    "TCPServer", "UDPServer", "OS.get_env", "OS.execute", "OS.read_pipe", "URL",
]

EXPECTED_RUNTIME = {
    "config_version": 1,
    "visible_fps": 30,
    "bite_wait_min_sec": 20,
    "bite_wait_max_sec": 60,
    "basket_capacity": 10,
}
EXPECTED_SPECIES = {
    "river_carp": {"catch_weight": 60, "base_price": 8},
    "silver_perch": {"catch_weight": 30, "base_price": 16},
    "golden_trout": {"catch_weight": 10, "base_price": 32},
}
EXPECTED_V1 = {
    "save_version": 1,
    "revision": 0,
    "wallet_gold": 0,
    "basket_capacity": 10,
    "basket": [],
    "processed_catch_ids": [],
    "processed_sale_ids": [],
    "fishing_checkpoint": {
        "state": "IDLE", "event_id": None, "wait_seconds": None,
        "elapsed_effective_seconds": 0,
    },
    "desktop_window": {"x": 80, "y": 80, "width": 220, "height": 160, "display_hint": None},
}
V2_REQUIRED = [
    "save_version", "revision", "wallet_gold", "basket_capacity", "basket",
    "processed_catch_ids", "processed_sale_ids", "fishing_checkpoint", "desktop_window",
    "economy_ledger", "rng_snapshot", "clock_snapshot", "pending_candidate",
]
CLASS_NAME_PATTERN = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)
SENSITIVE_ENV_MARKERS = (
    "API_KEY", "ACCESS_KEY", "PRIVATE_KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL",
)


def _load_json(relative_path):
    with open(os.path.join(ROOT, relative_path), "r", encoding="utf-8") as handle:
        return json.load(handle)


def _project_setting_values(section, key):
    values = []
    current_section = None
    with open(os.path.join(ROOT, "project.godot"), "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                current_section = line[1:-1]
                continue
            if current_section != section:
                continue
            setting_key, separator, value = line.partition("=")
            if separator and setting_key.strip() == key:
                values.append(value.split(";", 1)[0].strip().lower())
    return values


def _preflight():
    problems = []
    for relative_path in DELIVERABLES:
        if not os.path.isfile(os.path.join(ROOT, relative_path)):
            problems.append("missing deliverable: " + relative_path)

    try:
        transparency_setting = _project_setting_values(
            "display", "window/per_pixel_transparency/allowed")
        if transparency_setting != ["true"]:
            problems.append(
                "project value-lock: display/window/per_pixel_transparency/allowed must occur once and be true")
    except OSError as exc:
        problems.append("project value-lock unreadable: " + repr(exc))

    for name in ("fish_species.json", "runtime_config.json"):
        try:
            if _load_json("data/" + name) != _load_json("examples/" + name):
                problems.append("value-lock: data/" + name + " differs from examples/" + name)
        except Exception as exc:  # validation failure is a red result
            problems.append("value-lock: cannot compare " + name + ": " + repr(exc))

    try:
        if _load_json("data/runtime_config.json") != EXPECTED_RUNTIME:
            problems.append("runtime value-lock changed from 20/60/30/10 v1 values")
    except Exception as exc:
        problems.append("runtime value-lock unreadable: " + repr(exc))

    try:
        species_data = _load_json("data/fish_species.json")
        species = {entry["id"]: entry for entry in species_data["species"]}
        if set(species) != set(EXPECTED_SPECIES):
            problems.append("species value-lock: species IDs changed")
        for species_id, expected in EXPECTED_SPECIES.items():
            item = species.get(species_id, {})
            if any(item.get(key) != value for key, value in expected.items()):
                problems.append("species value-lock: weight/price changed for " + species_id)
    except Exception as exc:
        problems.append("species value-lock unreadable: " + repr(exc))

    try:
        if _load_json("examples/save_v01.json") != EXPECTED_V1:
            problems.append("v1 example changed from the frozen legacy contract")
    except Exception as exc:
        problems.append("v1 example unreadable: " + repr(exc))

    try:
        schema = _load_json("schemas/game-save.schema.json")
        if schema.get("additionalProperties") is not False:
            problems.append("schema lock: additionalProperties must remain false")
        version = (schema.get("properties") or {}).get("save_version") or {}
        if version.get("const") != 2:
            problems.append("schema lock: save_version must remain const 2")
        required = schema.get("required") or []
        if len(required) != len(V2_REQUIRED) or set(required) != set(V2_REQUIRED):
            problems.append("schema lock: required keys must remain the exact v2 set")
    except Exception as exc:
        problems.append("schema unreadable: " + repr(exc))

    declared = {}
    scripts_root = os.path.join(ROOT, "scripts")
    for directory, _subdirs, files in os.walk(scripts_root):
        for filename in files:
            if not filename.endswith(".gd"):
                continue
            path = os.path.join(directory, filename)
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    content = handle.read()
            except OSError as exc:
                problems.append("cannot read class declaration file: " + repr(exc))
                continue
            for class_name in CLASS_NAME_PATTERN.findall(content):
                declared.setdefault(class_name, []).append(os.path.relpath(path, ROOT))
    for class_name, paths in declared.items():
        if len(paths) != 1:
            problems.append("class_name collision: " + class_name + " in " + repr(paths))
    for class_name in ("EventLog", "FishingSession", "AtomicSaveService", "SaveValidate",
                       "SaveFaults", "SaveService"):
        if len(declared.get(class_name, [])) != 1:
            problems.append("class-name lock: expected exactly one " + class_name)
    if declared.get("EventLog") != [os.path.join("scripts", "io", "event_log.gd")]:
        problems.append("class-name lock: EventLog must remain in scripts/io/event_log.gd")
    if declared.get("SaveService") != [os.path.join("scripts", "io", "save_service.gd")]:
        problems.append("class-name lock: SaveService must remain in scripts/io/save_service.gd")

    try:
        with open(os.path.join(ROOT, "scripts", "io", "event_log.gd"), "r", encoding="utf-8") as handle:
            event_log_source = handle.read()
        for api in FORBIDDEN_EVENT_LOG_APIS:
            if api in event_log_source:
                problems.append("static scan: forbidden network/env API in event_log.gd: " + api)
    except OSError as exc:
        problems.append("static scan: cannot read event_log.gd: " + repr(exc))

    if not os.path.isfile(GODOT):
        problems.append("Godot executable not found: " + GODOT)
    return problems


def _tail(text):
    lines = (text or "").splitlines()
    return "\n".join(lines[-TAIL_LINES:]) if lines else "(no output)"


def _run_step(name, command, project_root, env, marker=None, fail_marker=None):
    print("=" * 72)
    print("[" + name + "] $ " + " ".join(command), flush=True)
    try:
        result = subprocess.run(
            command, cwd=project_root, env=env, capture_output=True, text=True,
            timeout=TIMEOUT_SEC,
        )
    except subprocess.TimeoutExpired:
        print("[" + name + "] TIMEOUT after " + str(TIMEOUT_SEC) + "s")
        return False
    except OSError as exc:
        print("[" + name + "] could not start Godot: " + repr(exc))
        return False

    output = (result.stdout or "") + "\n" + (result.stderr or "")
    failures = []
    if result.returncode != 0:
        failures.append("exit code " + str(result.returncode))
    if "SCRIPT ERROR" in output:
        failures.append("SCRIPT ERROR found")
    if marker is not None and (result.stdout or "").count(marker) != 1:
        failures.append("required stdout marker must occur exactly once: " + marker)
    if fail_marker is not None and fail_marker in output:
        failures.append("failure marker found: " + fail_marker)

    print("[" + name + "] exit_code=" + str(result.returncode))
    print("[" + name + "] output tail:\n" + _tail(output))
    if failures:
        print("[" + name + "] FAILED: " + "; ".join(failures))
        return False
    print("[" + name + "] PASS")
    return True


def _ignore_copy(directory, names):
    ignored = {name for name in names if name in (".git", ".godot", "__pycache__") or name.endswith(".pyc")}
    if os.path.realpath(directory) == os.path.realpath(os.path.join(ROOT, "tasks")):
        ignored.add("evidence")
    return ignored


def main():
    print("LOG-001 source root: " + ROOT)
    print("Godot executable: " + GODOT)
    problems = _preflight()
    if problems:
        for problem in problems:
            print("PRE-FAIL: " + problem)
        print("LOG001 RUNNER FAIL (preflight)")
        return 1

    env = {
        key: value for key, value in os.environ.items()
        if not any(marker in key.upper() for marker in SENSITIVE_ENV_MARKERS)
    }
    try:
        with tempfile.TemporaryDirectory(prefix="run_log001_") as temp_root:
            project_root = os.path.join(temp_root, "project")
            home = os.path.join(temp_root, "home")
            os.makedirs(home)
            shutil.copytree(ROOT, project_root, ignore=_ignore_copy)
            env.update({
                "HOME": home,
                "XDG_CONFIG_HOME": os.path.join(home, ".config"),
                "XDG_CACHE_HOME": os.path.join(home, ".cache"),
            })
            print("isolated project copy: " + project_root)
            print("isolated HOME: " + home)
            godot_base = [GODOT, "--headless", "--path", project_root]
            steps = [
                ("step1-import", godot_base + ["--editor", "--quit"], None, None),
                (LOG_TEST[0], godot_base + ["--script", "res://" + LOG_TEST[1]], LOG_TEST[2], LOG_TEST[3]),
            ]
            for name, path, marker, fail_marker in REGRESSIONS:
                steps.append((name, godot_base + ["--script", "res://" + path], marker, fail_marker))
            for name, command, marker, fail_marker in steps:
                if name != "step1-import":
                    command.extend(["--quit-after", "3600"])
                if not _run_step(name, command, project_root, env, marker, fail_marker):
                    print("LOG001 RUNNER FAIL (" + name + ")")
                    return 1
    except (OSError, shutil.Error) as exc:
        print("LOG001 RUNNER FAIL (isolated copy): " + repr(exc))
        return 1

    print("LOG001 RUNNER PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
