# REL-001 Phase A review

Date: 2026-11-12

## Decision

Approved for the bounded Phase B test orchestrator in `tests/unit/run_rel001_checks.py`.

## Review findings

- The plan adds no game behavior and does not relax any frozen product value.
- Every child command is an existing isolated validation runner; the aggregate runs them serially and validates their exact success markers, exit codes, failure markers, and script-error output.
- SIM-001 is checked from its generated report instead of being represented as a new real-time test. Its 120 virtual runs, replay checks, and fault-injection results remain separately attributed.
- GUI acceptance is supported only by isolated macOS GUI evidence. The current reconciliation covers Finder click-through, drag/restore, sales, hide/resume, FPS, save failure/retry, the external display, and native full-screen coexistence.
- The visible eight-hour run is real elapsed time, uses an isolated project and HOME, and must remain a separate final gate.
- Queue freeze/pause and approval-ledger validation are retained. No freeze is cleared by this review.

## Authorization

The project owner's continuing v0.1 delegation in `tasks/APPROVALS.md` authorizes Codex to approve this local test-only Phase B scope and complete the review without another prompt. This approval does not authorize feature expansion or changes to the release criteria.

PHASE-A-REVIEW-PASS

## AUTO-001 guard regression — 2026-11-12

Executed `python3 -B tools/auto/runner.py selftest` with exit 0; the saved output is `runner-selftest-2026-11-12.log` and ends `ALL PASS`. The synthetic `/tmp` repositories verified queue ownership (runner-written snapshot allowed; agent rewrite, missing fingerprint, and unrelated `tools/auto` edits rejected), exact `icon.svg.import` ownership, import-first CORE smoke-marker enforcement, whitelist-only commits that preserve pre-staged/user evidence, concurrent import-sidecar rewrite rejection, and approval/freeze behavior. These checks did not modify the real queue, approvals, or freeze state.

## CFG-001 import-isolation amendment — 2026-11-12

The first manual REL-001 aggregate rerun exited 0 but its captured CFG-001 command showed `--path /Users/rain/DevGame/Fishing` for `step1-import`; the other CFG steps also used that root. The run generated only ignored `.godot` cache and untracked import metadata/evidence sidecars; no tracked product file, queue, or freeze changed. The candidate runtime remains on its distinct temporary project and stayed alive.

Decision: approve the narrowly scoped `tests/unit/run_cfg001_checks.py` correction under the append-only REL-001 Phase B amendment. The runner now copies the current project to a temporary project tree, omits `.git`, `.godot`, and rolling `tasks/evidence`, uses a separate temporary HOME, pins both `cwd` and every Godot `--path` to that copy, and rejects a mismatched path before starting Godot. No product code or values change. Re-run the direct CFG runner and the full REL aggregate and retain their exact logs before queue acceptance.

Verification completed:

- `python3 -B tests/unit/run_cfg001_checks.py` exited 0. Its saved log shows all three Godot steps using the same `/var/folders/.../run_cfg001_.../project` path, with `CFG001 CONFIG PASS`, `CORE001 SMOKE PASS`, no `SCRIPT ERROR`, and `CFG001 RUNNER PASS`.
- `python3 -B tests/unit/run_rel001_checks.py` exited 0 after the correction. `aggregate-isolation-fixed-2026-11-12.log` shows CFG/FSM/ECO/SAVE/UI/LOG each used isolated project paths; each exact runner PASS marker and `REL001 RUNNER PASS` appears once; there is no `RUNNER FAIL`, `SCRIPT ERROR`, or `--path /Users/rain/DevGame/Fishing`.
- `python3 -B tools/auto/runner.py status` reports model gate PASS, unchanged approval-ledger verification, `paused=False`, `frozen=None`, and REL-001 still `exec_ready` with `needs_human=true`. No queue or freeze transition was performed.
- The separate visible candidate remained alive in its temporary project through this test rerun; no product files or candidate process were changed.
