# UI-001 macOS hide/pause check

Date: 2026-11-11
Engine: Godot 4.7.2 stable
Project source: `/Users/rain/DevGame/Fishing`
GUI run: isolated project copy and isolated HOME under `/var/folders/.../fishing-ui001-final-proof-eetpycx6/`

## Result

The in-game `隐藏` control paused the session and minimized the overlay window. The runtime reported `mode=1` (`MODE_MINIMIZED`); the overlay disappeared from the desktop. A 60-second wait was split into two 30-second intervals. The persisted document stayed byte-for-byte stable in the compared fields:

| Observation | Revision | Clock | Checkpoint elapsed | State | Basket |
|---|---:|---:|---:|---|---:|
| Immediately after hide | 8 | 21.498 s | 20.498 s | WAITING | 0 |
| After 30 seconds | 8 | 21.498 s | 20.498 s | WAITING | 0 |
| After 60 seconds | 8 | 21.498 s | 20.498 s | WAITING | 0 |

The isolated Godot process remained alive, the checkpoint did not advance, and its GUI log contained no `SCRIPT ERROR` or `ERROR:` lines. The runtime log is saved beside this report as `macos-hide-60s.log`.

## Resume status

The restore path now handles both application-focus-in and window-focus-in, avoids restoring during the minimize transition, and restores the overlay's borderless/always-on-top flags after the OS unminimizes it. The headless regression covers this policy and passed.

The GUI window regained focus during the activation attempt. The runtime log recorded `NOTIFICATION_WM_WINDOW_FOCUS_IN` with the window restored to mode 0, followed by the focus signal. A later save read showed revision 92, clock 250.1 s, and five fish, proving the session resumed and continued fishing after the pause. The log contains no `SCRIPT ERROR` or `ERROR:` lines.

The direct Dock-icon click path was not isolated from the window-raise/focus action. The tested window-focus restore path and session continuation passed; keep the Dock-specific interaction as an additional manual check.

## Configuration approval

The project has the six planned display settings plus `display/window/per_pixel_transparency/allowed=true`. The project owner explicitly approved that additional setting in this conversation after the isolated comparison showed transparent background required it. `tests/unit/run_ui001_checks.py` locks the key to exactly one `true` value.

## Automated validation

`python3 -B tests/unit/run_ui001_checks.py` passed after import-first validation. The runner reported exactly one PASS marker for UI-001, SAVE-001, ECO-001, FSM-001, CORE-001, and CFG-001, with zero exit codes and no `SCRIPT ERROR`.

## Window input policy regression

The current UI runner includes a deterministic `DesktopWindow` input-policy case. It verifies that a delivered short click emits one boat-click signal, the native-drag path requests OS drag on press and still classifies an unmoved release as a click, and manual movement records window geometry without emitting a click. The latest `python3 -B tests/unit/run_ui001_checks.py` run passed all steps in an isolated copy. This exercises the controller policy; it does **not** prove macOS mouse pass-through or replace GUI checks G-UI-1/G-UI-2.

An earlier OS-coordinate click attempt was inconclusive. In a controlled run, an isolated Godot window and an opaque helper were verified at identical bounds `(818, 39, 110, 80)`, with Godot above the helper. After fixing the helper's AppKit event loop, a click at a transparent point `(921, 49)` reached the helper marker. This confirms pass-through at that point only; it does not complete G-UI-1. A click at the estimated boat point `(875, 98)` also reached the helper, while the runtime reports the boat rectangle at `(38, 76)` in a `220x160` viewport on a 2x display. The coordinate mapping for that point is unresolved, so boat interaction is unverified. A later HUD-point probe produced neither a game log nor a helper marker, and macOS reported Preview as frontmost afterward; that probe is inconclusive and no further clicks were sent. A final setup found the helper on a different display and was stopped before clicking. All game state was isolated under a temporary HOME and project copy; the real project and save were not used. No screenshot was taken. Remaining GUI items are G-UI-1, G-UI-2, G-UI-3, and G-UI-5 through G-UI-8; G-UI-4 is the hide/resume observation documented above.

## Visual render check

A subsequent GUI run from the same isolated project copy showed the compact status HUD, cat, and boat rendered over the editor canvas. The cropped capture is `macos-overlay-render.png`; it excludes the surrounding desktop. This confirms the CORE-001 placeholder-only/blank presentation is gone in the current UI build. It does not cover the remaining manual items G-UI-1, G-UI-2, G-UI-3, and G-UI-5 through G-UI-8.
