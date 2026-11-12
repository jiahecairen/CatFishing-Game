# UI-001 delegated acceptance review

Date: 2026-11-12
Reviewer: Codex under the project owner's continuing v0.1 delegation recorded in `tasks/APPROVALS.md`.

## Evidence reviewed

| Acceptance item | Evidence | Review result |
|---|---|---|
| G-UI-1 transparent click-through and boat interaction | `gui1-finder-click-through-2026-11-12.md`; `gui7-secondary-display-2026-11-12.md` | PASS. Finder's isolated test file received a click through the transparent gap; the boat received its click. The secondary-display native underlay probe independently reproduced both routes. |
| G-UI-2 click, drag, release, save and restore position | `gui-routing-drag-failure-retest-2026-11-11.md` | PASS. The synchronized physical cursor run exercised the native drag and persisted geometry across restart. |
| G-UI-3 sale and idempotent repeat intent | `gui-routing-drag-failure-retest-2026-11-11.md`; `gui-sale-isolated-2026-11-11.md` | PASS. Selected/all sales, durable wallet update, and repeated click behavior were observed with isolated app data. |
| G-UI-4 hide for 60 seconds and resume | `macos-hide-60s.md` | PASS for the tested focus-restore path. The hidden interval did not advance fishing; resume continued from the saved checkpoint. |
| G-UI-5 idle/drag frame-rate policy | `gui-routing-drag-failure-retest-2026-11-11.md` | PASS. Idle samples were 28–30 FPS; drag target switched to 60 and returned to 30 on release. |
| G-UI-6 save failure and retry | `acceptance-reconciliation-2026-11-12.md` | PASS. The isolated failed sale did not publish income; the persistent in-game banner appeared; retry after restoring the isolated directory succeeded. |
| G-UI-7 Retina and display placement | `gui-routing-drag-failure-retest-2026-11-11.md`; `gui7-secondary-display-2026-11-12.md` | PASS. Primary 2× and secondary 1× display checks found no opaque rectangle or visible alignment offset; secondary-display click routing also passed. |
| G-UI-8 full-screen coexistence | `gui8-fullscreen-acceptance-2026-11-12.md` | PASS. A native macOS full-screen window remained visible and focused while the isolated overlay stayed behind it; the overlay returned after the test processes ended. |

The current main-scene boot capture (`current-checkout-boot-2026-11-12.png`) visibly contains the HUD, cat, and boat. The earlier CORE-001 placeholder screenshot is not representative of the current checkout. The import-first automated run in `test-final-2026-11-12.log` passed UI/SAVE/ECO/FSM/CORE/CFG with exact success markers and no script errors.

## Decision

Accept UI-001. The remaining differences are alternate test surfaces, not unmet acceptance steps: Finder was used for the underlay check, a native AppKit probe for the secondary display/full-screen checks, and focus restoration for the 60-second resume check. All GUI actions used isolated project copies and app data. No production save or unrelated user window was used.

The `needs_human` gate is fulfilled under the owner's explicit delegated-review authorization. The approval ledger remains intact, and the queue's pause/freeze mechanism is unchanged. This is acceptance of UI-001 only; REL-001 still requires its running eight-hour candidate and aggregate release review.
