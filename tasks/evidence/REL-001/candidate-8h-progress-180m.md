# REL-001 candidate run checkpoint — 180 minutes

Observed at 2026-11-12 07:02:27 UTC, 10,800 seconds after the isolated visible run started at 04:02:26 UTC.

- Godot GUI process PID 1583 was alive at elapsed 03:00:59, and the `Fishing (DEBUG)` window remained open. The latest one-minute resource sample was exactly at 10,800 seconds. The 180 initialized samples exclude the elapsed-zero startup row, whose RSS was a 256 KB sampler placeholder.
- Process-average CPU across initialized samples: mean 5.402%, median 5.500%, nearest-rank P90 6.500%, maximum 7.600%.
- RSS ranged from 427,856 to 428,192 KB; mean 428,129.7 KB and latest 428,112 KB. The ordinary least-squares trend was +33.9 KB/hour. These are descriptive observations, not pass/fail thresholds.
- The isolated save remained v2, revision 148, basket 10/10, wallet 0, no pending candidate, `IDLE`, with 10 processed catch IDs and no processed sales. Its event log remained 1,918 bytes with ten lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. The 36 tracked game-source files still matched the isolated candidate copy by SHA-256, with no missing files.
- Latest recorded Activity Monitor sample remains 06:44 UTC: Energy Impact 11.0, App Nap `No`, `Preventing Sleep` `Yes`, battery 100% on AC. No privileged power sampling was used.
- Queue/approval state was unchanged: REL-001 remains `exec_ready` with `needs_human=true`; the scheduler reports `paused=False`, `frozen=None`. No resume, unfreeze, queue, or approval change was performed.

The eight-hour run and final REL-001 acceptance remain open.
