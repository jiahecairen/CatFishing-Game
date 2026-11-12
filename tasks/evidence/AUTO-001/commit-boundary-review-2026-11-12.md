# AUTO-001 commit boundary fix — 2026-11-12

## Change

The runner now snapshots Git's pre-session changed paths and their content hashes. A commit candidate contains only files first changed during this runner instance. Existing untracked evidence stays untouched and is excluded; if a pre-existing file changes during the session, the runner blocks instead of combining it into its commit. The approvals ledger remains protected by the existing scope and hash checks.

## Regression

Command: `python3 -B tools/auto/runner.py selftest`

Result: exit code 0; 42 checks; final marker `ALL PASS`. New T11c creates an untracked evidence archive before runner initialization, then proves the generated code is committed while that archive remains untracked and absent from the commit. Existing T11a/T11b whitelist and pre-staged-file cases also pass.

Raw output: `commit-boundary-selftest-2026-11-12.log`.

## State preserved

The real `tools/auto/queue.json` and `tasks/APPROVALS.md` were not modified. Tests used synthetic repositories under a temporary directory; no real ticket was started or unfreezed.
