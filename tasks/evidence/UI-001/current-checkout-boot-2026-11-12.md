# Current checkout boot check — 2026-11-12

## Isolation

- Source: current `main` checkout at commit `14dfe98`.
- Engine: Godot 4.7.2 stable on Apple M4 Max / Metal 4.0.
- The project was copied to `/tmp/fishing-ui-current.tAesRj/project`; `HOME` pointed to `/tmp/fishing-ui-current.tAesRj/home` for both import and runtime. No production save was used.
- Import-first headless editor startup exited 0 and imported `icon.svg`. The visible game then ran from the same isolated copy and exited 0 after Ctrl-C.

## Observation

The runtime window was `Fishing (DEBUG)`, 110×80 screen points at (40, 40), corresponding to the 220×160 pixel screenshot `current-checkout-boot-2026-11-12.png`. It visibly rendered the status HUD (gold, basket count, state), cat, and boat; the image is not blank. At capture, HUD showed gold 0, basket 2/10, `WAITING`.

The isolated Godot log contained only the engine and Metal startup lines; no `SCRIPT ERROR` or `ERROR` was observed. The isolated save was created only under the temporary HOME directory.

## Relevance

The user's earlier screenshot showed `PlaceholderLabel` and the `CORE-001 skeleton` label. The current committed `scenes/main.tscn` instead attaches `UIRoot`, and this isolated current-checkout run rendered that UI. The earlier screenshot therefore reflects an older scene/runtime state than this checkout. UI-001 remains subject to its existing human acceptance gate; this evidence does not change queue or approvals state.
