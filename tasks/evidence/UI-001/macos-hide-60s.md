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
