# REL-001 candidate resource trend — 2h16

Observed through 2026-11-12 06:18:27 UTC (8,160 seconds from the 04:02:26 UTC start).

Method: parse the live resource CSV, exclude the startup row with RSS below 10,000 KB, and summarize the 136 initialized one-minute samples. CPU values are the monitor's process-average percentage. P90 uses the nearest-rank method. RSS trend is an ordinary least-squares slope over elapsed seconds; this is descriptive evidence, not a fixed acceptance threshold.

- CPU: mean 5.365%, median 5.600%, P90 6.500%, maximum 7.200%.
- RSS: minimum 427,856 KB, maximum 428,192 KB, mean 428,125 KB; first initialized sample 427,904 KB, latest 428,176 KB.
- Linear RSS slope: +67.7 KB/hour across this interval.
- The isolated game process was still alive. Its valid save remained revision 148 with a full 10/10 basket, ten processed catch IDs, no pending candidate, and `IDLE` state; the runtime log still had no `SCRIPT ERROR:` or `ERROR:` lines.

These measurements are the observed baseline so far. The eight-hour run and release acceptance remain open.
