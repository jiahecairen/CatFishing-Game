#!/usr/bin/env python3
"""Serial release regression gate; each child runner owns its isolated copy/HOME."""

import json
import os
import subprocess
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUNNERS = [
    ("CFG-001", "tests/unit/run_cfg001_checks.py", "CFG001 RUNNER PASS"),
    ("FSM-001", "tests/unit/run_fsm001_checks.py", "FSM001 RUNNER PASS"),
    ("ECO-001", "tests/unit/run_eco001_checks.py", "ECO001 RUNNER PASS"),
    ("SAVE-001", "tests/unit/run_save001_checks.py", "SAVE001 RUNNER PASS"),
    ("UI-001", "tests/unit/run_ui001_checks.py", "UI001 RUNNER PASS"),
    ("LOG-001", "tests/unit/run_log001_checks.py", "LOG001 RUNNER PASS"),
]


def _preflight_simulation_report():
    path = os.path.join(ROOT, "tasks/evidence/SIM-001/sim_report.json")
    try:
        with open(path, "r", encoding="utf-8") as handle:
            report = json.load(handle)
    except (OSError, ValueError) as exc:
        return "cannot read SIM-001 report: " + repr(exc)

    summary = report.get("summary", {})
    failures = []
    if report.get("pass") is not True:
        failures.append("pass flag is not true")
    if len(report.get("seeds", [])) != 20:
        failures.append("expected 20 fixed seeds")
    if report.get("virtual_hours") != [1, 4, 8]:
        failures.append("expected 1/4/8 virtual-hour coverage")
    for key in (
        "duplicate_catch_transactions",
        "duplicate_sale_transactions",
        "casts_started_while_full",
        "wait_seconds_out_of_range",
        "fault_transactions_committed_before_recovery",
    ):
        if summary.get(key) != 0:
            failures.append(key + " must be zero")
    if summary.get("deterministic_replay_identical") is not True:
        failures.append("deterministic replay must be identical")
    return "; ".join(failures)


def main():
    print("REL-001 source root: " + ROOT, flush=True)
    problem = _preflight_simulation_report()
    if problem:
        print("REL001 RUNNER FAIL (SIM-001): " + problem)
        return 1
    print("SIM-001 report preflight PASS", flush=True)

    for ticket, relative_script, marker in RUNNERS:
        script = os.path.join(ROOT, relative_script)
        if not os.path.isfile(script):
            print("REL001 RUNNER FAIL (missing " + relative_script + ")")
            return 1
        command = [sys.executable, "-B", script]
        print("\n===== " + ticket + ": " + " ".join(command) + " =====", flush=True)
        try:
            result = subprocess.run(
                command,
                cwd=ROOT,
                capture_output=True,
                text=True,
                timeout=1200,
            )
        except subprocess.TimeoutExpired:
            print("REL001 RUNNER FAIL (" + ticket + " timeout)")
            return 1
        except OSError as exc:
            print("REL001 RUNNER FAIL (" + ticket + " could not start): " + repr(exc))
            return 1

        stdout = result.stdout or ""
        stderr = result.stderr or ""
        print(stdout, end="" if stdout.endswith("\n") else "\n", flush=True)
        if stderr:
            print("[child stderr]\n" + stderr, end="", flush=True)
        if result.returncode != 0:
            print("REL001 RUNNER FAIL (" + ticket + " exit=" + str(result.returncode) + ")")
            return 1
        if stdout.count(marker) != 1:
            print("REL001 RUNNER FAIL (" + ticket + " expected exactly one " + marker + ")")
            return 1
        combined = stdout + "\n" + stderr
        if "RUNNER FAIL" in combined or "SCRIPT ERROR" in combined:
            print("REL001 RUNNER FAIL (" + ticket + " failure marker or SCRIPT ERROR)")
            return 1
        print(ticket + " PASS", flush=True)

    print("REL001 RUNNER PASS", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
