# REL-001 candidate run checkpoint — one hour

Observed at 2026-11-12 05:03 UTC, with 3,600 seconds recorded by the one-hour resource sample. The visible isolated run started at 04:02:26 UTC.

- The Godot 4.7.2 GUI process remained alive in the copied project (PID 1583). A live desktop screenshot showed the cat, boat, HUD, full 10/10 basket, and `IDLE` state; the game window was not blank.
- The resource log contained 60 initialized samples. RSS ranged from 427,856 to 428,144 KB; the latest process-average CPU sample was 5.6% and RSS was 428,144 KB.
- The isolated v2 save remained at revision 148 with ten processed catch IDs, no pending candidate, and the expected full-basket stop state.
- The isolated event log remained 1,918 bytes with ten lines. The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines.
- The eight-hour runtime gate remains open; continue to 28,800 real seconds, then review final resource, process, error, save, and GUI evidence before REL-001 acceptance.
