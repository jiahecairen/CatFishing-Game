# REL-001 candidate run checkpoint — two hours

Observed at 2026-11-12 06:02:27 UTC, 7,200 seconds after the visible isolated run started at 04:02:26 UTC.

- Godot 4.7.2 GUI process PID 1583 remained alive in the copied project. Live desktop screenshots at one and two hours showed the cat, boat, HUD, full basket, and `IDLE` state; the window remained visibly rendered rather than blank.
- The resource log contained 120 initialized samples. RSS ranged from 427,856 to 428,192 KB; the latest process-average CPU sample was 5.3% and RSS was 428,160 KB.
- The isolated v2 save remained at revision 148 with ten processed catch IDs, a full 10/10 basket, no pending candidate, and the expected full-basket `IDLE` state.
- The event log remained 1,918 bytes with ten lines. The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines.
- During this interval the CFG-001 regression runner was hardened to import only a temporary project copy. Its direct test and the full REL aggregate both exited 0; the saved aggregate output contains no main-project Godot `--path`, failure marker, or script error.
- This remains an interim checkpoint; eight-hour stability and final REL-001 acceptance are still open.
