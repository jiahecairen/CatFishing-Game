# REL-001 candidate source identity check

Observed at 2026-11-12 06:36:27 UTC, with candidate PID 1583 still running from the isolated project copy. The latest resource sample was at elapsed 02:34:00.

Compared SHA-256 for all 36 tracked Godot game-source files selected from `project.godot`, `icon.svg`, `data/`, `examples/`, `scenes/`, `schemas/`, and `scripts/` between the working checkout and the running candidate copy. All 36 matched; no selected candidate file was missing. The set comprises 25 scripts, 3 schemas, 3 examples, 2 data files, 1 scene, and the project configuration and icon.

This confirms those tracked runtime sources have not drifted since the candidate copy was prepared. The candidate remains live; no source, queue, approval, or freeze state was changed by this check. This is an intermediate identity check, not final REL-001 acceptance.
