# REL-001 candidate run checkpoint — 150 minutes

Observed at 2026-11-12 06:32:27 UTC, 9,000 seconds after the visible isolated run started at 04:02:26 UTC. The latest resource sample at review time was 9,060 seconds.

- Godot 4.7.2 GUI process PID 1583 remained alive in the isolated project copy. The two-hour live screenshot showed the cat, boat, HUD, full basket, and `IDLE` state.
- There were 151 initialized one-minute resource samples. Process-average CPU mean was 5.403%, median 5.600%, nearest-rank P90 6.500%, maximum 7.200%.
- RSS ranged from 427,856 to 428,192 KB; mean was 428,130 KB and the latest sample was 428,176 KB. The ordinary least-squares RSS slope over elapsed time was +60.3 KB/hour; this remains descriptive baseline evidence, not a fixed threshold.
- The isolated v2 save remained at revision 148 with ten processed catch IDs, a full 10/10 basket, no pending candidate, and `IDLE` state. The event log remained 1,918 bytes with ten lines.
- The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines. The eight-hour run and final REL-001 acceptance remain open.
