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
