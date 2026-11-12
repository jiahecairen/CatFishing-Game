# AUTO-001 blocked-ticket review recovery — 2026-11-12

## Recovery contract

Added `reconcile-review --id ID --reason ...`. It accepts only a blocked ticket with a valid existing Phase B approval and test command, completed/in-review dependencies, a readable safe worktree, no queue freeze or pause, and a fresh passing test. It records the delegated reviewer, reason, prior block reason, attempt, and exit code; then commits current evidence and the queue transition separately. The ticket moves only to `in_review`; `needs_human` is preserved. A frozen queue is rejected without modification.

## Regression

Command: `python3 -B tools/auto/runner.py selftest`

Result: exit code 0; 45 checks; final marker `ALL PASS`. T14 verifies successful recovery, the preserved human gate, committed queue status, a clean synthetic worktree, and refusal to recover while frozen. Full output is `reconcile-review-selftest-2026-11-12.log`.

The real UI-001 queue was not changed by these synthetic tests.
