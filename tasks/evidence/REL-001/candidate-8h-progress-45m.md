# REL-001 candidate run checkpoint — approximately 45 minutes

Observed at 2026-11-12 04:48:27 UTC, 46 minutes after the visible isolated run started at 04:02:26 UTC.

- The Godot 4.7.2 GUI process remained alive in the isolated project copy (PID 1583; 46:00 elapsed at the latest sample). No production project or HOME was used.
- The resource log contained 47 samples. Excluding its 256 KB startup sample, RSS ranged from 427,856 to 428,144 KB across 46 initialized samples. The latest process-average CPU sample was 5.6% and RSS was 428,144 KB.
- The isolated v2 save remained at revision 148 with a full 10/10 basket, ten processed catch IDs, no pending candidate, and the intended IDLE/full-basket stop state.
- The isolated event log remained 1,918 bytes with ten lines. The runtime log had no `SCRIPT ERROR:` or `ERROR:` lines at this checkpoint.
- The required eight-hour runtime is still in progress; final acceptance remains open until 28,800 real seconds elapse and all final evidence is reviewed.
