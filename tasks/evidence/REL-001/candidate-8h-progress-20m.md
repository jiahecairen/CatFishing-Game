# REL-001 candidate run checkpoint — 20 minutes

Observed: 2026-11-12 04:22:27 UTC, approximately 20 minutes after the visible run started.

- Godot 4.7.2 stable, Metal 4.0 Forward+, Apple M4 Max; macOS 27.2.1 build 26B131.
- The visible isolated game rendered the HUD, cat, and boat. It reached a full basket and stayed in the intended IDLE/full-basket stop state.
- 21 resource samples were recorded. Excluding the startup sample before the process finished initializing, RSS ranged from 427,856 to 428,144 KB; latest process-average CPU was 3.5%.
- The isolated save was revision 148 with 10/10 fish, 10 unique processed catch IDs, and no pending candidate. The production HOME/save was not used.
- Local event logging had one 1,918-byte JSONL file, within its 262,144-byte and five-file defaults.
- The runtime log contained no actual `SCRIPT ERROR:` or `ERROR:` lines at this checkpoint.
- Activity Monitor recorded Energy Impact 0.0, App Nap `No`, Preventing Sleep `Yes`, battery 100% and connected to AC; see `candidate-8h-20261112T040226Z-energy.csv`.

This is an interim observation only. The eight-hour acceptance remains open until at least 28,800 real seconds have elapsed and the final logs, resources, save, and error state are reviewed.
