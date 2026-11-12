# UI-001 Finder click-through acceptance

Date: 2026-11-12

## Setup

The GUI run used the isolated project copy at `/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/ui001-finder-click-jow48hu3/project` with a separate temporary `HOME`, cache, and config. Its only test-specific source change positioned the game over Finder; the production project files were not edited or launched.

Finder's verified test window was `ui001-finder-underlay-20261112`. Its only item was `click-test-only.txt`, confirmed in the accessibility tree at `file:///private/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/ui001-finder-underlay-20261112/click-test-only.txt`.

The primary Retina display scale was 2.0. The native window list placed the transparent Godot window at `(291,622)`, size `110×80` screen points, layer 3, above the Finder test window at `(185,561)`, layer 0. The saved screenshot is a crop inside the test Finder window and contains no unrelated desktop document.

The first launch of the clean clone happened before its initial Godot import and reported missing global script classes. That process was stopped. A headless editor import then exited 0; the subsequent GUI run rendered and responded normally, with no startup script or engine error observed.

## Results

- A global click at `(380,656)` landed on the test file through the game's transparent gap (game-local `(178,68)`). Finder then reported `1 of 1 selected` for `click-test-only.txt`.
- A click on the boat at `(348,672)` (game-local `(114,100)`) opened the in-game basket. Finder continued to report the test file selected, confirming the boat received the click while Finder did not.
- No sale action was issued. The isolated game continued its normal automatic fishing while open; its temporary basket state was not written to the production save. The isolated process was stopped after capture.
- Screenshot: `finder-click-through-2026-11-12.png`.

## Acceptance boundary

**G-UI-1 Finder path: PASS** for transparent-gap click-through and boat interaction over Finder. The browser variant was not exercised. This evidence does not change UI-001's queue or human-approval state; no approval, freeze, or remote repository setting was modified.
