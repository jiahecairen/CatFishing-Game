# REL-001 candidate run checkpoint — 165 minutes

Observed at 2026-11-12 06:47:27 UTC, 9,900 seconds after the isolated visible run started at 04:02:26 UTC.

- Godot GUI process PID 1583 remained alive in the isolated project. The latest one-minute sample was at 9,900 seconds. The 165 initialized samples exclude the startup row at elapsed 0, whose RSS field was the sampler's 256 KB placeholder.
- Process-average CPU across initialized samples: mean 5.370%, median 5.500%, nearest-rank P90 6.500%, maximum 7.300%.
- RSS ranged from 427,856 to 428,192 KB; mean 428,131 KB and latest 428,128 KB. The ordinary least-squares trend was +47.4 KB/hour. These are descriptive observations, not pass/fail thresholds.
- The isolated save remained v2, revision 148, basket 10/10, wallet 0, no pending candidate, `IDLE`, with 10 processed catch IDs and no processed sales. The event log remained 1,918 bytes and 10 lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. A prior live screenshot at two hours showed the cat, boat, HUD, full basket, and `IDLE` state; Godot remains running.
- Activity Monitor recorded Energy Impact 0.0 at 04:21 and 11.0 at 06:44; App Nap was `No`, `Preventing Sleep` was `Yes`, and battery remained 100% on AC. Energy Impact is a live relative score, not a cumulative energy measurement or threshold. `powermetrics` requires superuser privileges on this Mac, so no privileged energy sampling was used.

The eight-hour run and final REL-001 acceptance remain open.
