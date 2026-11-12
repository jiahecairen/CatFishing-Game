# UI-001 macOS input, drag, FPS, and save-failure retest

Date: 2026-11-11

Godot: 4.7.2 stable

Project: isolated copy of the current `Fishing` tree

App data: isolated `HOME` under `/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/fishing-route-accept-rsq9euur/`

No GUI run used the production project path or production `user://` directory. The only temporary permission change was on the isolated save directory; its original `0755` mode was restored to `0755` immediately after the failure was observed. No production app, Finder, browser, or user save was changed.

## Corrected input-probe method

The earlier contradictory routing probe posted click events at screen coordinates while the physical cursor remained on the other display. Godot's macOS pass-through polling therefore saw an unrelated cursor location. This run first moved the real cursor with `CGWarpMouseCursorPosition` (return code 0), then posted the mouse event at that same point. The isolated Godot window was above a neutral opaque AppKit probe window; the probe reported received clicks through its visible counter.

## Routing and panel results

| Action | Observed result |
|---|---|
| Click boat at game-local `(100, 90)` | Basket opened in Godot; underlay counter stayed at 9. |
| Click transparent gap `(178, 68)` | Underlay counter increased `9 → 10`; game UI did not change. |
| Move back to boat and click after underlay received focus | Basket opened again; underlay counter stayed at 10. This reproduces the focus transition with the physical cursor synchronized and does not reproduce the earlier failure. |
| Click transparent corner `(218, 20)` | Underlay counter increased `10 → 11`; the open basket stayed visible. |
| Click a fish checkbox inside the basket | The row selection toggled; underlay counter stayed at 11. |

At the first routing pass the Godot window measured `110×80` screen points at `(13,39)` and the probe occupied the main display below it. The main display reports a Retina scale factor of `2.0`. The game-local points were converted using that scale and the measured window origin.

These results verify native routing against a controlled lower application window. The lower app was a probe rather than Finder or a browser, so the specific Finder/browser part of G-UI-1 remains partial.

## Native drag, saved position, and frame rate

The isolated game started at screen bounds `(13,39,110,80)`. A real mouse-down / held-move / mouse-up sequence moved it to `x=38` while `y=39` remained unchanged. The isolated save recorded `desktop_window.x=76` at the engine's 2× scale. After restarting the isolated game with the same isolated `HOME`, the window returned to `(38,39)` and startup logged the matching engine position `(76,3496)`.

A second controlled drag logged:

```text
DEBUG_DRAG_BEFORE supported=true engine_fps=30
DEBUG_DRAG_AFTER native=true target=60 engine_fps=60
DEBUG_FPS observed=42.0 target=60
DEBUG_FPS observed=57.0 target=60
DEBUG_DRAG_FINISH moved=50.0 was_drag=true engine_fps=30
```

The pointer was held and moved across the boat for about two seconds. The window moved from screen `x=40` to `x=65`; after release the engine target returned to 30. Idle samples were 28–30 FPS with target 30. The 60 FPS drag target ramped to 57 FPS in the observed sample window. This covers the click-versus-drag, move, release, position persistence, and FPS-target transitions in G-UI-2/G-UI-5.

## Sale and save-failure results

- With the isolated save directory changed from `0755` to `0555`, clicking **Sell All** produced the red `存档失败：经济已暂停（可重试）` banner and retry button. The visible wallet stayed at 0 and the basket stayed at 10/10; no uncommitted sale was shown as successful.
- After restoring directory mode `0755`, clicking **重试保存** committed the pending sale. The HUD showed 120 gold, an empty basket, and no failure banner.
- A later **Sell Selected** action changed the isolated wallet from 120 to 184 while reducing the basket from 4 to 2.
- A double-click on **Sell All** produced one further sale transaction; the immediate HUD showed 240 gold and an empty basket. The isolated save recorded three processed sale IDs for the three sale intents exercised. Fishing then continued in the isolated run, so subsequent basket reads can include newly caught fish.

This exercises G-UI-3/G-UI-6 in the isolated runtime. The `game-fps-drag.log` run had no `SCRIPT ERROR` or `ERROR:` entries.

## Acceptance boundary

- **G-UI-1:** partial. Transparent regions reached the lower native probe, while boat and basket controls received clicks, including after focus returned. Finder/browser-specific routing was not tested.
- **G-UI-2:** passed for click, native drag, release, geometry save, and restart restoration in the isolated run.
- **G-UI-3:** selected sale, all sale, and repeated-click behavior exercised in the isolated run.
- **G-UI-4:** prior isolated 60-second hide/resume evidence remains in `macos-hide-60s.md`; not repeated here.
- **G-UI-5:** idle and drag target/sample observations recorded above.
- **G-UI-6:** isolated permission failure and successful retry passed.
- **G-UI-7:** primary Retina display only; external-display behavior remains untested.
- **G-UI-8:** full-screen coexistence remains **NOT RUN**.

UI-001 is still not accepted as a whole. Its `needs_human=true` setting and queue state were left untouched; G-UI-1's Finder/browser variant, G-UI-7 external-display coverage, and G-UI-8 remain open.
