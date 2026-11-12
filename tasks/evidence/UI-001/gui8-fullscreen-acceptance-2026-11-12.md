# UI-001 full-screen coexistence retest

Date: 2026-11-12

## Setup and observation

The isolated Fishing overlay was running first with its separate temporary `HOME`. A neutral native AppKit test app with its own bundle ID (`local.codex.fishing-fullscreen-probe`) then entered macOS full-screen mode on the main Retina display. No Finder, browser, document, or other user app was opened or inspected.

The CUA accessibility tree identified the focused window as `UI-001 Fullscreen Acceptance Probe`. Its screenshot showed only the full-screen test background and label; the Fishing overlay did not cover the full-screen content. The window list reported the probe at `(0,39)` with size `2056×1290`, spanning the main display's visible full-screen area. No system notification was visible. The isolated Fishing process remained running while the probe held focus.

After terminating only the two test processes, the full-screen space exited and the isolated Fishing window was visible again. User-owned processes were left running.

## Result

**G-UI-8 passed for a native macOS full-screen window:** the overlay did not appear over the full-screen content or take focus during observation. This is a neutral test app rather than a third-party full-screen app.

The external display was not enumerated during the follow-up run: `NSScreen` exposed one display and Godot reported `DisplayServer.get_screen_count() == 1`. G-UI-7 therefore remains limited to the primary Retina display; external-display behavior is **NOT RUN**.

UI-001 remains blocked overall. G-UI-1's Finder/browser variant and G-UI-7 external-display check remain open. Queue status, `needs_human=true`, approvals, and freeze controls were not changed.
