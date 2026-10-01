# Project Freedom — The Greywater March

A local, native 3D campaign-map visual prototype. This is the first visual checkpoint, not a complete strategy game or a claim of matching Total War's finished art quality.

## Location

The project lives at `C:\Users\Owner\dev\project-freedom` (repository: https://github.com/jwerdel/Project-Freedom), not on the OneDrive Desktop. Never create or keep project files inside OneDrive; syncing corrupts Git repositories and uploads the engine and caches.

## Play

Double-click **Play Project Freedom.cmd** in this folder. No account, network connection, or audio is required at runtime. Allow several seconds for the first scene to build.

On a fresh clone, first fetch the pinned engine (Godot 4.7.2, about 86 MB download, checksum-verified) into `runtime/`:

```
powershell -ExecutionPolicy Bypass -File scripts\get_godot.ps1
```

The launcher imports project assets automatically on the first run.

## Explore

| Control | Action |
|---|---|
| WASD / arrow keys | Move across the map |
| Right mouse drag | Orbit and tilt |
| Middle mouse drag | Pan |
| Mouse wheel | Zoom |
| Home | Return to the overview |
| Tab | Hide/show the interface |
| Escape | Close the selection panels and show the interface |
| Left click | Select a settlement (province panel) or the commander (army panel) |
| Hover | Tooltip with name, faction and province for settlements, the commander and unit cards |
| C | Select the commander and open the army panel |
| Space | Pause/resume trade traffic and mill |
| F12 | Save a real in-engine screenshot in captures |
| G | Jump the camera to Goldspire Rock (bookmark) |
| F6 | Debug: cycle Goldspire Rock through its three stages |
| F5 | Debug: cycle Greyhaven through its three stages |
| F7 | Debug: cycle roads (dirt, gravel, stone) |
| L | Toggle daylight / late afternoon |
| End Turn button | Advance the year by one (adds "Year X begins" to Event Messages) |

The campaign UI is modeled on Total War: Warhammer III (see constitution.md). Click a settlement to open its province stats and the province panel (settlement tabs with building slot cards); click the commander for the army panel with unit cards. Economy, events, province stats and buildings are mock values from `data/mock_ui.json`, read through `core/ui_data.gd`. Greyhaven and road stages (F5, F7) alter the actual 3D geometry. Pause affects traffic and the windmill; ambient water and cloth continue moving.

## Included

- Textured coastal terrain, mountain backdrop, forest, farms, rocks, and sea.
- Greyhaven, Crownwatch fortress, and Willowmere farming village with a hedgerowed farmland patchwork.
- Goldspire Rock, the first landmark settlement (docs/world.md #2): a sea cliff fortress with three stages (mine tunnels and summit tower; carved halls, harbor and walls; terraced rock face).
- Campaign map overlays: faction banners on settlements (emblem, name, level pips), glowing territory borders with a faction tint, and a clickable minimap. Provinces, regions and faction ownership come from `data/provinces.json` and `data/factions.json`.
- A first gameplay system: End Turn runs a yearly turn loop (income, expenses, population growth, chronicle). Treasury, income, population and province stats in the UI are real; the treasury tooltip breaks income down; the Chronicle button (top-left, book) opens the Grey Scribes' log. Numbers are placeholders in `data/economy.json`.
- Seven placeholder unit types with auto-rendered card portraits, and an eight-unit army led by the map commander.
- Three settlement stages and three road stages.
- Six moving caravans, four sailing vessels, docks, a lighthouse, and an animated mill.
- A procedurally constructed armored commander with moving banner and cape.
- Free camera, settlement inspection, daylight control, and screenshot capture.

## Honest limitations

Buildings, ships, caravans, and the commander are prototype models. Architecture, terrain composition, and character art still need an art-development pass to meet the intended Total War-inspired benchmark. There is one environment and one architectural style. The commander is a static pose rather than an animated production character. Traffic illustrates routes; it does not yet simulate trade. Development changes reset when you close the application. There is no economy, diplomacy, army command, battle deployment, population, or save-game system yet.

## Development

Built with Godot 4.7.2, using Forward+ rendering. Open project.godot in Godot to edit. Everything used at runtime is local.

| Path | Contents |
|---|---|
| `main.gd`, `Main.tscn` | Prototype map: terrain, sea, coastal rocks, world layout and tree placement, traffic routes, camera, UI |
| `data/asset_manifest.json` | Maps visual IDs (city stages, fortress, village, harbor, farmland, forest trees, coastal rocks, road stages, commander, wagon, ship) to scenes, and landmark settlements (Goldspire Rock) to their own stage scenes |
| `core/asset_manifest.gd` | Loads the manifest and instantiates visuals by ID |
| `visuals/` | One scene per visual; `visuals/common/proto_kit.gd` holds the shared prototype palette and builders |
| `*.gdshader` | Terrain, sea, and cloth shaders |
| `assets/` | Third-party textures and models (see ASSETS.md) |
| `scripts/get_godot.ps1` | Downloads the pinned engine into `runtime/` |

The runtime, generated caches, local settings, and screenshots are ignored by Git; the engine is not versioned as source.

See CLAUDE.md for working rules, constitution.md for design, ASSETS.md for asset provenance, and VALIDATION.md for checks and measured limitations.
