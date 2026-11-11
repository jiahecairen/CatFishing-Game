# UI-001 mouse-region gap regression

Date: 2026-11-11
Engine: Godot 4.7.2 stable
Source: local `Fishing` working tree

## Finding and change

`PlatformAdapter._connector_rects()` joined two hit regions whose projections overlap by using the full shared width or height as the connector. With the closed basket, the cat/boat rectangle and the HUD hide-button rectangle overlap by 12 horizontal pixels while remaining separated vertically. That made a 12-pixel-wide strip of otherwise transparent desktop between them intercept clicks.

The connector now uses a path no wider or taller than one pixel for horizontal or vertical projection overlap, extending half a pixel into both endpoint regions so the polygon remains connected. Diagonal separation continues to use the existing one-pixel L-shaped connector. This keeps the single native polygon connected while leaving adjacent desktop pixels pass-through.

## Regression and result

`tests/unit/test_ui001_ui.gd` now checks both sides of the vertical connector: a point on the one-pixel bridge remains inside the polygon while a nearby point in the old 12-pixel strip is outside. A separate horizontal case checks the same narrow-bridge/pass-through behavior. Existing boat, hide-button, basket, transparent-corner, and diagonal-bridge checks remain.

`python3 -B tests/unit/run_ui001_checks.py` completed with exit code 0 in an isolated project copy and HOME. The runner imported first, then UI-001, SAVE-001, ECO-001, FSM-001, CORE-001, and CFG-001 each emitted its required PASS marker; no `SCRIPT ERROR` appeared. Full output: `test-mouse-gap-fix.log`.

## Acceptance boundary

This fixes a deterministic over-wide hit-region connector and proves its polygon geometry in headless regression. It does **not** establish reliable macOS desktop event routing after focus or menu transitions. G-UI-1/G-UI-2 remain unaccepted until a standalone, non-embedded Godot run consistently routes clicks to an opaque underlay across those transitions. UI-001 remains blocked.
