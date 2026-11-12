# REL-001 candidate run checkpoint — 315 minutes

Observed at 2026-11-12 09:17:27 UTC, 18,900 seconds after the isolated visible run started at 04:02:26 UTC.

- Godot GUI process PID 1583 remained alive at elapsed 05:17:05. The `Fishing (DEBUG)` window was present in the Mac UI. The latest one-minute resource sample was exactly at 18,900 seconds. The 315 initialized samples exclude the elapsed-zero startup row, whose RSS was a 256 KB sampler placeholder.
- Process-average CPU across initialized samples: mean 5.405%, median 5.500%, nearest-rank P90 6.600%, maximum 7.900%.
- RSS ranged from 427,856 to 428,688 KB; mean 428,287.8 KB and latest 428,608 KB. The ordinary least-squares trend was +127.7 KB/hour. This remains descriptive evidence, not a fixed pass/fail threshold.
- The isolated save remained v2, revision 148, basket 10/10, wallet 0, no pending candidate, `IDLE`, with 10 processed catch IDs and no processed sales. The event log remained 1,918 bytes with ten lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. All 36 tracked game-source files still matched the isolated candidate copy by SHA-256, with no missing files.
- Activity Monitor at 09:18:48 showed Energy Impact 9.6, App Nap `No`, `Preventing Sleep` `Yes`, battery 100% on AC. This live relative score is not a cumulative energy measurement or threshold.
- Queue and approval ledger were unchanged: REL-001 remains `exec_ready` with `needs_human=true`; scheduler reports `paused=False`, `frozen=None`; approval ledger hash prefix remains `697468f6f23f58e6`. No resume, unfreeze, queue, or approval change was performed.

The eight-hour run and final REL-001 acceptance remain open.
