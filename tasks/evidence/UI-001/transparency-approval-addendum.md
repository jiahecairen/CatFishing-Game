# UI-001 transparency setting approval addendum

Date: 2026-11-11

The project owner explicitly approved adding the single setting demonstrated as necessary by `gui-transparency-retest.md`:

```ini
[display]
window/per_pixel_transparency/allowed=true
```

This amends SC-1 in `plan.md` from six to seven exact `[display]` window keys. No other project setting or path was approved. The tracked `project.godot` contains this key once with value `true`; `tests/unit/run_ui001_checks.py` locks that exact value. `run/max_fps=30` and the main scene setting remain unchanged.

The change does not edit `tasks/APPROVALS.md`, change `tools/auto/queue.json`, clear a queue freeze, or satisfy the remaining Mac GUI acceptance items. UI-001 remains `blocked` and `needs_human=true` while window pass-through, drag, and other GUI checks remain incomplete.
