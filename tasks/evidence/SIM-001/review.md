# SIM-001 Phase A 独立审查

Date: 2026-11-11
Reviewer: Codex, under the project owner's explicit continuous-execution delegation
Source plan: `tasks/evidence/SIM-001/plan.md`

## Review result

**Phase B approved** for the exact queue allowlist `tools/sim/**` and `tasks/evidence/SIM-001/**`.

The plan reuses the accepted fishing FSM, deterministic RNG, virtual clock, economy transaction ledger, and save fault-injection seam. Its run matrix is 20 fixed seeds × two explicitly named strategies × 1h/4h/8h virtual horizons. It covers cycle and first-fill distributions, species counts/value, idempotent retry invariants, full-basket cast rejection, and an isolated save-failure/retry case. The runner must use a temporary project copy and HOME, import before Godot scripts, parse real JSON from stdout, and fail on wrong exit codes, missing or repeated PASS markers, FAIL markers, or `SCRIPT ERROR`.

The review found and corrected one workflow error in the plan: AUTO-001 Phase A does not fill an empty `test_cmd`. The delegated reviewer must record approval, set `test_cmd` to `python3 -B tools/sim/run_sim001_checks.py`, and set `SIM-001` to `exec_ready` before starting Phase B.

## Conditions

- Preserve `20–60s`, the existing species weights and prices, 30 FPS, and capacity 10; the report may present observations but cannot tune values.
- Keep the periodic sale interval as a simulation-only strategy constant, clearly labeled as such.
- For the fault-injection case, arm a save fault immediately before a guaranteed catch or sale transaction, verify `PERSIST_FAILED` and byte/value-equivalent authoritative state, disarm, then retry the same transaction ID and prove one successful effect. Count only commits while the fault is armed; do not claim recovery from an unexercised injection.
- Record each seed/scenario/horizon independently, including censored first-fill cases as `null` with an explicit reason. Include the full run identity in the JSON rather than a single ambiguous row per seed.
- The runner and GDScript simulator may add files only under the approved allowlist. The simulation must not write to production `user://`; its only persistent fault-injection state belongs under its temporary directory.
- This ticket does not resolve or relabel UI-001's separate GUI gate.

No SDD scope, product parameter, schema, production code, or data file change is approved here. Approval follows the owner's explicit instruction to complete the frozen local v0.1 workflow autonomously.
