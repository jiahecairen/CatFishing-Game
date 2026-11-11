# UI-001 isolated GUI sale follow-up

Date: 2026-11-11
Engine: Godot 4.7.2 stable
Source: local `Fishing` working tree
Isolated project: temporary system-directory copy (`fishing-ui-accept-*`)
Isolated app data: `~/Library/Application Support/Godot/app_userdata/Fishing UI Acceptance 20261111/`

## Procedure and result

The clone was imported first with Godot's editor import step. Its `application/config/name` was changed only in the temporary clone so its `user://` save resolved to the separate app-data directory above.

The runtime showed the HUD, cat and boat. Clicking the boat opened the basket. Before sale, the HUD showed 0 gold and 10/10 fish. Clicking **Sell All** changed the HUD to 144 gold and 0/10 fish. After stopping and restarting the isolated run, the HUD still showed 144 gold, confirming the sale was saved before publication. Fishing resumed automatically afterward; later fish counts are not part of the sale assertion.

The isolated save file was independently read after the run and reported wallet 144. The production `Fishing` app-data directory was distinct. No sale action was performed against the production save.

During a separate earlier diagnostic against the production app-data directory, the save was observed at revision 161 with wallet 0 and basket 10/10 (mtime `2026-11-11T21:43:51Z`). This is consistent with automatic fishing reaching capacity while that diagnostic process was active, but does not establish the exact cause. No production fish were sold, and the production save was not edited, restored, or rolled back. This state observation is separate from the isolated sale test above.

## Limits

This was an editor-hosted debug run. Its checkerboard around the game content is the debug viewport's transparency preview; it does not establish macOS desktop click-through. The run therefore does not pass G-UI-1 or G-UI-2. Drag and position restore, measured FPS, GUI save-failure injection, Retina behavior, full-screen coexistence, and the remaining GUI items are still `NOT RUN` or unaccepted. The evidence supports the basket open, Sell All, and durable wallet update only.

The automated UI suite evidence remains `test-current.log`: import first, all seven Godot steps exited 0, each emitted its expected PASS marker, and no `SCRIPT ERROR` was reported.
