# REL-001 candidate run checkpoint — 195 minutes

Observed at 2026-11-12 07:17:27 UTC, 11,700 seconds after the isolated visible run started at 04:02:26 UTC.

- Godot GUI process PID 1583 remained alive at elapsed 03:15:56. The `Fishing (DEBUG)` window was present in the Mac UI. The latest one-minute resource sample was exactly at 11,700 seconds. The 195 initialized samples exclude the elapsed-zero startup row, whose RSS was a 256 KB sampler placeholder.
- Process-average CPU across initialized samples: mean 5.315%, median 5.500%, nearest-rank P90 6.600%, maximum 7.600%.
- RSS ranged from 427,856 to 428,192 KB; mean 428,128.9 KB and latest 428,112 KB. The ordinary least-squares trend was +25.3 KB/hour. These are descriptive observations, not pass/fail thresholds.
- The isolated save remained v2, revision 148, basket 10/10, wallet 0, no pending candidate, `IDLE`, with 10 processed catch IDs and no processed sales. The event log remained 1,918 bytes with ten lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. All 36 tracked game-source files still matched the isolated candidate copy by SHA-256, with no missing files.
- Activity Monitor at 07:17:46 showed Energy Impact 10.7, App Nap `No`, `Preventing Sleep` `Yes`, battery 100% on AC. This live relative score is not a cumulative energy measurement or threshold.
- Queue/approval state was unchanged: REL-001 remains `exec_ready` with `needs_human=true`; the scheduler reports `paused=False`, `frozen=None`. No resume, unfreeze, queue, or approval change was performed.

The eight-hour run and final REL-001 acceptance remain open.
