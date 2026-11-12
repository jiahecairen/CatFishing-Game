# UI-001 external display GUI check

Date: 2026-11-12

## Setup

The GUI run used the isolated project copy at `/var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/fishing-route-accept-rsq9euur/project` and a separate temporary `HOME`. No Godot process used the production project path or production save.

macOS exposed two displays:

| Display | Frame | Backing scale |
|---|---:|---:|
| Main | `(0, 0, 2056, 1329)` | 2.0 |
| Secondary | `(2056, -207, 2049, 1536)` | 1.0 |

Godot 4.7.2 reported the secondary as screen 1 and its viewport window as `220×160` at engine position `(4192, 80)`. The native window list placed the isolated Godot window at `(2096, 40)`, size `110×80` screen points, layer 3. The lower test window was at `(2056, 30)`, size `360×260`, layer 2.

## Results

- The isolated game rendered its status HUD, cat, boat, and basket on the 1× secondary display. The screenshot shows the controlled blue grid through transparent areas around the game content, with no opaque full-window rectangle or visible hit-region offset: `gui7-secondary-display-2026-11-12.png`.
- With the game window above the native test window, a synchronized cursor warp to `(2185, 74)` succeeded (`CGError 0`). A click in the transparent gap changed the underlay label from `SECONDARY UNDERLAY READY` to `SECONDARY UNDERLAY CLICK 1 at 129,216`.
- A subsequent click on the boat at `(2150, 94)` opened the basket in Godot; the underlay count stayed at 1. The boat target therefore received the click while the transparent gap passed it through.
- The isolated Godot log had zero `SCRIPT ERROR` and zero `ERROR:` lines. The visible FPS target remained 30; the instrumented samples included startup values below target and ranged from 1 to 34 during this run, so this run is not used as a standalone FPS acceptance.
- Both isolated GUI processes were stopped after observation. Production processes, saves, approvals, queue state, and remote repositories were not changed.

## Acceptance boundary

The external-display portion of G-UI-7 passed in this controlled run. This also adds native underlay routing evidence on the secondary display. It does not complete G-UI-1's Finder/browser-specific check or accept UI-001 as a whole.
