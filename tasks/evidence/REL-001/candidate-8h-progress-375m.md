# REL-001 candidate run checkpoint — 375 minutes

Observed at 2026-11-12 10:20:34 UTC; the isolated visible run started at 2026-11-12 04:02:26 UTC. The latest one-minute resource sample is exactly at 22,500 seconds.

- Godot GUI process PID 1583 remained alive (1583 06:18:07). The 375 initialized samples exclude the elapsed-zero startup row, whose RSS was a 256 KB sampler placeholder.
- Process-average CPU across initialized samples: mean 5.413%, median 5.500%, nearest-rank P90 6.600%, maximum 8.600%.
- RSS ranged from 427,856 to 428,688 KB; mean 428,337.0 KB and latest 428,560 KB. The ordinary least-squares trend was +115.2 KB/hour. These are descriptive observations, not fixed pass/fail thresholds.
- The isolated save remained v2, revision 148, basket 10/10, wallet 0, no pending candidate, `IDLE`, with 10 processed catch IDs and 0 processed sales. The event log remained 1,918 bytes with 10 lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. All 36 tracked game-source files still matched the isolated candidate copy by SHA-256; mismatches or missing files: 0.
- Activity Monitor at 10:20:43 UTC showed Energy Impact 9.4, App Nap `No`, `Preventing Sleep` `Yes`, battery 100% on AC. This live relative score is not a cumulative energy measurement or threshold.
- The scheduler and approvals remain under the existing safeguards. REL-001 is still `exec_ready` and `needs_human=true`; this checkpoint does not change queue, pause/freeze state, or approval ledger.

The eight-hour run and final REL-001 acceptance remain open.
