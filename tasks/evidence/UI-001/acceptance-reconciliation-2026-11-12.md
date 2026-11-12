# UI-001 current acceptance evidence reconciliation

Date: 2026-11-12

This report reconciles the current GUI evidence with the older per-run reports. It does not alter the AUTO-001 queue, approval ledger, or `needs_human` gate.

## GUI criteria

| Check | Current evidence | Result and boundary |
|---|---|---|
| G-UI-1 | `gui1-finder-click-through-2026-11-12.md` | **PASS, Finder path.** Clicking the transparent gap selected the single temporary Finder test file; clicking the boat opened the basket and left Finder's selection unchanged. A browser underlay was not separately tested. |
| G-UI-2 | `gui-routing-drag-failure-retest-2026-11-11.md` | **PASS.** Click versus native drag, release, saved position, and restart restoration were exercised in the isolated run. |
| G-UI-3 | `gui-routing-drag-failure-retest-2026-11-11.md`; `gui-sale-isolated-2026-11-11.md` | **PASS.** Selected/all sales, repeated intent handling, and durable sale state were exercised in isolated app data. |
| G-UI-4 | `macos-hide-60s.md` | **PASS for the tested window-focus resume path.** The hidden 60-second interval did not advance the checkpoint; focus restored the overlay and the session continued. A Dock-specific restore click was not isolated. |
| G-UI-5 | `gui-routing-drag-failure-retest-2026-11-11.md` | **PASS.** Idle samples were 28–30 FPS against target 30; the drag target rose to 60, reached 57 in the observed sample, and returned to 30 after release. |
| G-UI-6 | This report, below; `gui-routing-drag-failure-retest-2026-11-11.md` | **PASS in the isolated save-failure run.** The failure banner and retry control appeared; the failed sale left the saved wallet/basket bytes unchanged; retry succeeded after permissions were restored. No transient OS notification window was observed. |
| G-UI-7 | `gui7-secondary-display-2026-11-12.md`; `macos-overlay-render.png` | **PASS for the tested 2× primary and 1× secondary displays.** The cat/boat/HUD remained visible without an opaque full-window rectangle or observed alignment offset. |
| G-UI-8 | `gui8-fullscreen-acceptance-2026-11-12.md` | **PASS with a neutral native full-screen probe.** The game did not cover its full-screen content or take focus. No third-party full-screen application was tested. |

## G-UI-6 retest details

The run used the isolated project `/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/ui001-gui6-retest-t60bmst7/project` and a copied temporary `HOME`. The game ran on the secondary display; its native window was above the desktop. Production project files and production app data were not used.

Before fault injection, the copied save was wallet `0`, basket `10/10`, revision `156`, SHA-256 `75d3b1ab842ccf371bc49afa1a59e295795a9513563ae0dff7e0ef4aff215cc2`. The isolated app-data directory was temporarily changed from mode `0755` to `0555`. Clicking **Sell All** displayed the in-game save-error/retry state. While the failure was active, the save still had the same hash, wallet `0`, basket `10/10`, and revision `156`.

The on-screen window inventory during the failure listed only the existing Notification Center widgets (`Featured`, `Weather`, `Month`), not a transient notification window. The captured desktop crop showed the game error/retry state without a system banner over it. This observation is scoped to the test session and display state.

The test directory was restored to `0755`. Clicking **Retry Save** cleared the error and showed wallet `96`, basket `0/10`. The process later auto-caught one fish before it was stopped; the final isolated save was wallet `96`, basket `1/10`, revision `174`, with no pending candidate. No sale was repeated and no production save was touched. The isolated Godot process exited normally; its log contained no `SCRIPT ERROR` or `ERROR:` entries.

## Automated regression

`test-final-2026-11-12.log` records the import-first `python3 -B tests/unit/run_ui001_checks.py` run. Import and each of UI-001, SAVE-001, ECO-001, FSM-001, CORE-001, and CFG-001 exited 0 with exactly one expected PASS marker and no `SCRIPT ERROR`; the run ended with `UI001 RUNNER PASS`.

## Workflow state

The original blocked snapshot above predates the later Finder, secondary-display, and full-screen checks. On 2026-11-12, the delegated review in `delegated-review-2026-11-12.md` reconciled those later records and accepted UI-001. Its queue state is now `done`, with `needs_human=false` because the delegated GUI review was completed. The approval ledger and freeze/pause implementation remain intact; no freeze was cleared. LOG-001 is separately accepted, while REL-001 remains open pending the visible eight-hour candidate run and final release review.
