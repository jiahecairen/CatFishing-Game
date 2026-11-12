# UI-001 Finder click-through attempt

Date: 2026-11-12

## Setup

The isolated Godot copy was running with its own temporary `HOME`. Finder was opened to a newly created temporary test folder containing only `click-target.txt`. The production project, production save, and user files were not used as test targets.

## Result

The native desktop changed spaces while preparing the Finder-underlay check. To avoid continuing across the user's active desktop, no synthetic click was sent and no click-through result was observed. This attempt therefore does **not** pass G-UI-1's Finder/browser check; that item remains **NOT RUN**.

Only the isolated Godot test process was stopped. No production process, queue state, approval record, or remote repository was changed.

## Resumed check

On a later read-only check, Finder's active window was titled `project` and showed project-root-looking contents. Its full path could not be confirmed from the safe UI metadata, so no Finder action or synthetic click was sent. The Finder-specific acceptance remains **NOT RUN**; this window was not treated as a verified temporary underlay.
