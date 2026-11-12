# REL-001 candidate run checkpoint — 75 minutes

Observed at 2026-11-12 05:17:27 UTC, 75 minutes after the visible isolated run started at 04:02:26 UTC.

- Godot 4.7.2 GUI process PID 1583 remained alive in the copied project. The one-hour desktop screenshot had already confirmed the HUD, cat, boat, full basket, and `IDLE` state remained visible.
- The resource log contained 75 initialized samples. RSS ranged from 427,856 to 428,192 KB; the latest process-average CPU sample was 6.6% and RSS was 428,160 KB.
- The isolated v2 save remained at revision 148, with ten processed catch IDs, a full 10/10 basket, no pending candidate, and `IDLE` as expected after the full-basket stop.
- The isolated event log remained 1,918 bytes with ten lines. The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines.
- This is an interim checkpoint. The eight-hour gate and REL-001 release acceptance remain open.
