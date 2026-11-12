# REL-001 candidate run checkpoint — approximately 35 minutes

Observed at 2026-11-12 04:36:27 UTC, approximately 34 minutes after the visible run started at 04:02:26 UTC.

- The isolated Godot 4.7.2 GUI process remained alive in the temporary project copy; the production project and HOME were not used.
- 35 resource samples had been recorded. At the latest sample, process-average CPU was 3.9% and RSS was 428,048 KB; the prior samples showed stable RSS around 428 MB.
- The isolated save remained a valid v2 save at revision 148, with a full 10/10 basket, ten distinct processed catch IDs, no pending candidate, and the intended IDLE/full-basket stop state.
- The run log had no `SCRIPT ERROR:` or `ERROR:` lines at this checkpoint.
- Source files in the candidate copy had previously been hash-compared with the accepted checkout and matched. No product source changes have been made since that comparison.
- The eight-hour runtime gate remains open until the full 28,800 seconds elapse and final process, log, save, and resource evidence is reviewed.

This is an interim observation, not a final REL-001 acceptance.
