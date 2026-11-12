# REL-001 candidate run checkpoint — 420 minutes

Observed at 2026-11-12 11:03:19 UTC; the isolated visible run started at 2026-11-12 04:02:26 UTC. The latest one-minute resource sample is exactly at 25,200 seconds.

- Godot GUI process PID 1583 remained alive (1583 07:00:52). The 420 initialized samples exclude the elapsed-zero startup row, whose RSS was a 256 KB sampler placeholder.
- Process-average CPU across initialized samples: mean 5.489%, median 5.500%, nearest-rank P90 6.700%, maximum 8.600%.
- RSS ranged from 427,856 to 428,688 KB; mean 428,364.0 KB and latest 428,592 KB. The ordinary least-squares trend was +102.7 KB/hour. These are descriptive observations, not fixed pass/fail thresholds.
- The isolated save remained v2, revision 148, basket 10/10, wallet 0, no pending candidate, `IDLE`, with 10 processed catch IDs and 0 processed sales. The event log remained 1,918 bytes with 10 lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. All 36 tracked game-source files still matched the isolated candidate copy by SHA-256; mismatches or missing files: 0.
- Activity Monitor at 2026-11-12T11:02:40Z showed Energy Impact 10.0, App Nap `No`, `Preventing Sleep` `Yes`, battery 100% on AC. This live relative score is not a cumulative energy measurement or threshold.
- REL-001 remains `exec_ready` with `needs_human=true`; existing scheduler and approval safeguards remain in place. No queue, pause/freeze, or approval change was made.

The eight-hour run and final REL-001 acceptance remain open.
