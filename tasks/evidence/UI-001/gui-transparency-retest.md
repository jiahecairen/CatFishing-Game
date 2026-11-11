# UI-001 GUI transparency retest

Date: 2026-11-11

## Follow-up status

The approval boundary below records the state when this comparison was first written. On 2026-11-11, the project owner approved the one additional setting demonstrated by this test. The exact seven-key limit is now recorded in `plan.md` and `transparency-approval-addendum.md`; the tracked project contains the approved key. No other setting or path was approved.

## Result

The UI renders in the isolated GUI run, but the current six approved `[display]` keys do not make its background transparent. A controlled comparison isolated the missing setting:

- `gui-transparency-disabled.png`: isolated copy with the current project settings and runtime `Window.transparent` / `Viewport.transparent_bg` calls; the window background is opaque black.
- `gui-transparency-runtime-attempt.png`: isolated copy that additionally calls `ProjectSettings.set_setting("display/window/per_pixel_transparency/allowed", true)` at runtime; still opaque black.
- `gui-transparency-enabled.png`: otherwise equivalent isolated copy with `display/window/per_pixel_transparency/allowed=true` set before startup; the magenta window beneath the game is visible through the transparent areas, while the HUD and cat/boat remain visible.

The GUI tests used isolated project copies and an isolated `HOME`; no game process was started against the real project path. The extra setting was only added to a temporary copy.

Godot's [ProjectSettings documentation](https://docs.godotengine.org/en/4.5/classes/class_projectsettings.html) says `display/window/per_pixel_transparency/allowed` defaults to `false`, and that `display/window/size/transparent` alone only requests a transparent-capable window. The root viewport must also be transparent. The current controller already sets `Viewport.transparent_bg=true`; the missing allow flag explains the black background. The [overlay application guide](https://docs.godotengine.org/en/4.x/tutorials/ui/creating_applications.html) lists both project settings as prerequisites.

## Validation

`python3 -B tests/unit/run_ui001_checks.py` passed in an isolated copy on 2026-11-11:

1. Editor import
2. UI-001
3. SAVE-001
4. ECO-001
5. FSM-001
6. CORE-001
7. CFG-001

Every step exited 0, emitted its single expected PASS marker, and had no `SCRIPT ERROR`; final marker was `UI001 RUNNER PASS`.

## Approval boundary

At the time of the original comparison, the approved UI-001 plan allowed exactly six conditional `project.godot` window settings and explicitly forbade additional keys. The demonstrated fix required `window/per_pixel_transparency/allowed=true` in `[display]`. This report did not itself amend the plan, approval ledger, or queue. The subsequent owner approval and plan amendment are recorded in `transparency-approval-addendum.md`; the remaining GUI acceptance items still block UI-001.
