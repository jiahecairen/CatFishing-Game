# REL-001 — v0.1 release acceptance

Date: 2026-11-12

Reviewer: Codex under the project owner's continuing local v0.1 delegation

Decision: **ACCEPT**

## Automated release regression

`python3 -B tests/unit/run_rel001_checks.py` exited 0. Its full captured output is in `final-regression-20261112.log`.

- SIM-001 preflight passed: 20 fixed seeds, [1, 4, 8] virtual-hour coverage, 120 runs, deterministic replay, and all required duplicate-transaction, full-basket-cast, wait-range, and fault-recovery invariants at zero.
- CFG-001, FSM-001, ECO-001, SAVE-001, UI-001, and LOG-001 each emitted their exact aggregate PASS marker once. `REL001 RUNNER PASS` occurred once; the output contains no `RUNNER FAIL` or `SCRIPT ERROR`.
- The child runners imported and tested isolated project copies with isolated HOME directories. The active visible candidate was separate from these short tests.
- CORE-001 smoke verification passed within CFG/SAVE/UI regression runs.

## Desktop acceptance

The delegated UI-001 review in `../UI-001/delegated-review-2026-11-12.md` records G-UI-1 through G-UI-8 as passed using isolated GUI evidence. It also records the current-checkout boot capture with HUD, cat, and boat. Headless regression is supplemental to those GUI checks.

## Visible eight-hour candidate

The visible Godot candidate used project copy `/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/fishing_rel001_candidate_kusyos8b/project` and isolated HOME `/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/fishing_rel001_candidate_kusyos8b/home`.

- Godot 4.7.2.stable.official.ed1daf0bf; macOS 27.2.1 (26B131); renderer Metal 4.0 Forward+ on Apple M4 Max.
- Start: 2026-11-12T04:02:26.122448+00:00; ended: 2026-11-12T12:02:27.868399+00:00; elapsed: 28,800.0 seconds against the 28,800-second target. The monitor records `completed_8h=true`; exit `-15` was the planned stop at the exact target, not an early crash.
- All 480 initialized one-minute resource samples are present through 28,800 seconds. Process-average CPU: mean 5.582%, median 5.600%, nearest-rank P90 6.900%, maximum 8.600%.
- RSS ranged from 427,856 to 428,688 KB (mean 428,392.5 KB, final 428,592 KB); the full-run least-squares trend was +87.5 KB/hour. The observed total range was 832 KB across a roughly 428 MB process, with a stable plateau in the final hours. These are recorded measurements, not invented pass/fail thresholds.
- Runtime summary reports 0 script errors and 0 error lines; the runtime log contains no `SCRIPT ERROR:` or `ERROR:`. The isolated save remained v2, revision 148, basket 10/10, wallet 0, state `IDLE`, no pending candidate, 10 processed catch IDs and 0 sales. Its event log is 1,918 bytes across 10 lines.
- SHA-256 comparison confirms all 36 tracked game-source files matched the running candidate copy at the final check.

## Safeguards and final status

Under the continuing delegation recorded in `tasks/APPROVALS.md`, the required evidence is complete and REL-001 is accepted. The queue records only this ticket as `done` with its `needs_human` gate fulfilled. The approval ledger is unchanged (SHA-256 prefix `697468f6f23f58e6`); the pause/freeze mechanism and prior audit history remain intact. No pause was active and no queue freeze was cleared. No remote force-push or destructive Git operation was used.
