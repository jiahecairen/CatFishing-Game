# v0.1 automated regression pass — 2026-11-12

## Run conditions

- Source snapshot: commit `a6599c9` (`git archive HEAD`), copied to a disposable directory under `/tmp`.
- Engine: Godot 4.7.2 stable, Apple M4 Max / Metal 4.0.
- Each Python runner used `python3 -B` with a temporary `HOME`; wrappers used their own isolated test projects where specified. No production save or checkout cache was used.
- Raw stdout/stderr logs are stored beside this report.

## Results

| Runner | Exit | Final marker | FAIL / SCRIPT ERROR / ERROR markers in raw log |
|---|---:|---|---:|
| `run_cfg001_checks.py` | 0 | `CFG001 RUNNER PASS` | 0 / 0 / 0 |
| `run_eco001_checks.py` | 0 | `ECO001 RUNNER PASS` | 0 / 0 / 0 |
| `run_fsm001_checks.py` | 0 | `FSM001 RUNNER PASS` | 0 / 0 / 0 |
| `run_save001_checks.py` | 0 | `SAVE001 RUNNER PASS` | 0 / 0 / 0 |
| `run_ui001_checks.py` | 0 | `UI001 RUNNER PASS` | 0 / 0 / 0 |

All five runner logs end with their expected PASS marker. The UI runner also executed its bundled CORE, CFG, FSM, ECO, and SAVE regressions in its isolated copy.

## Limits

This is evidence for the listed automated runners only. It does not complete LOG-001, the REL-001 candidate 8-hour stability run, or the final owner acceptance gate. No queue or approval-ledger state was changed by this run.
