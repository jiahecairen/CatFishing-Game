# REL-001 Phase A plan — full regression and v0.1 release evidence

Date: 2026-11-12
Source: `tasks/TASKS.md`, `docs/ACCEPTANCE_TESTS.md`, the frozen v0.1 SDD, current queue, and completed ticket evidence.

## Objective

Close the v0.1 release audit without changing product behavior or frozen values. Run every existing core runner serially in its own documented isolated project/HOME flow; verify the completed SIM-001 report; reconcile the actual macOS UI evidence; and complete the separate visible eight-hour candidate run already recorded under this evidence directory.

## Phase B scope

Only add `tests/unit/run_rel001_checks.py` under the existing REL-001 `tests/**` allowlist. The runner will call the existing CFG, FSM, ECO, SAVE, UI, and LOG validation runners serially, require each exact aggregate PASS marker once, exit code 0, and no `RUNNER FAIL` or `SCRIPT ERROR`. It will preflight the committed SIM-001 report for its pass flag, 20 fixed seeds, 1/4/8 virtual-hour coverage, deterministic replay, and zero duplicate transactions, full-basket casts, out-of-range waits, or pre-recovery fault transactions.

Existing ticket runners own their temporary copies and HOME isolation. No REL runner step opens Godot on the production project path or writes production `user://`. The candidate runtime is separate from these short tests and uses a copied project plus isolated HOME.

## Acceptance evidence

- Automated: `python3 -B tests/unit/run_rel001_checks.py`; every child must pass its own import-first and marker gates.
- Simulation: `tasks/evidence/SIM-001/sim_report.json` plus `report.md`; report remains advisory on frozen prices/wait/capacity and does not trigger balance changes.
- Desktop UI: reconcile G-UI-1 through G-UI-8 from the latest isolated GUI records. Headless tests do not substitute for these records.
- Stability: candidate GUI run for at least 28,800 real seconds on the target Mac. Record Godot/macOS/renderer, start/end, periodic process CPU and RSS, runtime errors, and isolated save progress. Any early exit, script error, unrecoverable save state, duplicate settlement, or persistent resource growth is a failure requiring diagnosis.
- Release status: only after all required evidence is present may the delegated reviewer mark v0.1 accepted. The approval ledger and queue freeze/pause controls remain active and auditable throughout.

## Fixed constraints and exclusions

Keep 20–60 second waiting, 30 FPS idle, basket capacity 10, species/price weights, save schema, and placeholder art unchanged. Do not edit runtime source, Godot project settings, save data, requirements, remote settings, or approval/freeze implementation. Do not use `git add -A`, reset, clean, or force-push. Preserve user-owned and runner-owned uncommitted files.

## Review

The only planned code artifact is a test orchestrator. Its child runners already passed individually in the current checkout; the aggregate will be run before it is enabled in the queue and again through the queue's normal scope/test gate. The eight-hour GUI candidate is independent and must finish before final release acceptance.

PHASE-A-DONE
