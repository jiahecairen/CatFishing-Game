# REL-001 candidate run checkpoint — 105 minutes

Observed at 2026-11-12 05:47:27 UTC, 105 minutes after the visible isolated run started at 04:02:26 UTC.

- Godot 4.7.2 GUI process PID 1583 remained alive in the isolated project copy.
- The resource log contained 105 initialized samples. RSS ranged from 427,856 to 428,192 KB; the latest process-average CPU sample was 6.0% and RSS was 428,160 KB.
- The isolated v2 save remained at revision 148 with ten processed catch IDs, a full 10/10 basket, no pending candidate, and the expected `IDLE` full-basket stop state.
- The event log remained 1,918 bytes with ten lines. The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines.
- The eight-hour gate remains open. The run must reach 28,800 real seconds before final release review.
