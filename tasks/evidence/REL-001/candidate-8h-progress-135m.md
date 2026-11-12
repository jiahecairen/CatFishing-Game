# REL-001 candidate run checkpoint — 135 minutes

Observed at 2026-11-12 06:17:27 UTC, 8,100 seconds after the visible isolated run started at 04:02:26 UTC.

- Godot 4.7.2 GUI process PID 1583 remained alive in the isolated project copy. Screenshots at one and two hours showed the cat, boat, HUD, full basket, and `IDLE` state.
- The resource log contained 135 initialized samples. RSS ranged from 427,856 to 428,192 KB; the latest process-average CPU sample was 5.8% and RSS was 428,176 KB.
- The isolated v2 save remained at revision 148 with ten processed catch IDs, a full 10/10 basket, no pending candidate, and the expected full-basket `IDLE` state.
- The event log remained 1,918 bytes with ten lines. The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines.
- The corrected CFG-001 runner and the full REL aggregate passed in isolated project copies earlier in this run; their committed logs record the exact paths and markers.
- The eight-hour gate remains open; continue the same candidate process and review final evidence before release acceptance.
