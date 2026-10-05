# Project Freedom — rules for every session

Godot 4.7.2 fantasy strategy game. Personal project; free and local only.

## Vision

- **"Crusader Kings depth, Total War look and feel."**
- Depth comes through meaningful events and decisions, not management screens full of modifiers. Routine administration runs automatically; the game surfaces what needs attention.
- Battles are complete for V1. No further battle work except bug fixes.

## TW:WH3 UI parity principle

- Everything the player touches must match Total War: Warhammer III as closely as possible: map interactions, camera, UI layout, panels, cards, tooltips, controls, notifications and feedback. Only the game rules differ.
- When unsure how TW:WH3 does something, research it before building. Never invent a UI convention.

## Doc precedence

- `constitution.md` governs confirmed mechanics.
- `docs/game-design.md` is the full design. Items marked **Proposed** need the user's approval before implementation.
- `docs/world-bible-v2.md` is the lore reference.

## Project location (check first, every session)

- The canonical project path is `C:\Users\Owner\dev\project-freedom`. It does not live on the OneDrive Desktop.
- At the start of every session, confirm the working directory is this repo root: `CLAUDE.md` is present and `git remote get-url origin` is `https://github.com/jwerdel/Project-Freedom.git`. If not, stop and tell the user before doing anything else.
- Never create or keep project files inside OneDrive.

## Source of truth

- `constitution.md` is the source of truth for confirmed mechanics (see Doc precedence). Read it, and the relevant sections of `docs/game-design.md`, before design or gameplay work.
- Never implement a mechanic the constitution lists as open, unresolved, or undecided without the user's approval. Ask instead.
- Keep confirmed decisions separate from open questions when editing the constitution.
- `docs/battle-design.md` is the approved battle design (implemented: simulation, campaign battles, deployment screen; numbers are placeholders; section 13 lists open questions to ask about, not decide).
- `docs/v1-scope.md` is the approved V1 content scope (map, races, factions, systems, and what is deferred past V1). Don't build deferred systems for V1 without the user's approval.
- `docs/world-bible-v2.md` is the lore and landmark reference (geography, factions, faiths, landmark settlements); it supersedes `docs/archive/world-v1.md` (kept for history: the prototype map was built from it). `constitution.md` still governs mechanics. Don't invent lore that contradicts the world bible; ask instead.

## Art / data separation (critical)

- Gameplay values (size, footprint, speed, stats, costs) live in data files (Godot Resources or JSON under `data/`). Never derive them from meshes, bounding boxes, or visual scenes.
- Every visual is its own scene under `visuals/` (e.g. `visuals/units/spearman.tscn`), plugged into a generic gameplay scene. Swapping art = swapping the visual scene only; no gameplay code changes.
- One asset manifest, `data/asset_manifest.json`, maps unit / building / road IDs to visual scene paths. Load visuals only through `core/asset_manifest.gd` (`AssetManifest.instantiate(id)`), never by hard-coded scene path in gameplay code.
- Landmarks: the manifest's `landmarks` section maps a settlement ID (e.g. `"crownhaven"`, from `docs/world-bible-v2.md`) to its own `stage_1`/`stage_2`/`stage_3` scenes. Load settlements with `AssetManifest.instantiate_settlement(settlement_id, stage)`; settlements without a landmark entry fall back to the generic `settlement.city.stage_N` visuals. A landmark must define all three stages (missing stages are an error, not a silent fallback).
- Two scales:
  - World/battle scale: 1 Godot unit = 1 meter; humans about 1.8 m, including placeholders. Applies to deployment and battle scenes and to the source proportions of every character model.
  - Campaign map scale: stylized miniature. Generals and heroes are deliberately oversized relative to settlements for readability. The current prototype's proportions (recorded in the constitution) are the reference. Campaign figures are scaled-up world-scale sources, not separately proportioned models.
- Characters use a standard humanoid skeleton compatible with Godot's humanoid retargeting (SkeletonProfileHumanoid / BoneMap).
- All soldiers may share one placeholder model for now; unit cards must still visually resemble their unit.

## Units, cards and the campaign UI

- Unit types live in `data/units/*.json` (visual, outfit and weapon loadout as manifest IDs; stats only under `placeholder_stats`). Starting army compositions live in the map's `armies/` (listed in its `campaign_start.json`); during play armies are campaign state (`state.army_state`), changed only through `core/armies.gd` and `core/movement.gd`.
- Card style references live in `docs/reference/cards/` (see its README). They are reference material only: never slice them into `assets/cards/`, load them in-game, or ship them (`docs/reference/.gdignore`). Final cards use original faction heraldry (no real-world crosses, eagles or other real-world symbols), and orcs get their own crude visual language (scavenged armor, bone, fur, war paint), not human armor.
- Portraits and building-card art are auto-rendered from the visual scenes by `core/portrait_studio.gd` (SubViewport, cached by a hash of the data and every file the visual uses), so cards always match current art. Exception: a unit type may have optional hand-made card art (`"card_art"` path in its JSON, or `assets/cards/<unit_id>.png` by convention), loaded only through `UnitTypes.card_art()`; without it the card falls back to the rendered portrait. Card art is art only: the game draws faction border, strength bar, rank chevrons and unit count on top. Fit new files with `runtimeGodot.exe --headless --path . -s scripts/fit_card_art.gd`, record them in `ASSETS.md`, and never put the `docs/reference/cards/` mockups there. Building-card art stays auto-rendered.
- The campaign UI (`ui/`) reads only through `core/ui_data.gd`. Economy, events, province stats and building slots are mock values in `data/mock_ui.json` (marked `_MOCK`); real systems replace them behind UiData, not in the UI. Provinces, regions and factions are real data in the map's `provinces.json` and `factions.json`.
- Gameplay systems: `core/game_state.gd` (campaign state), `core/economy.gd` (income, upkeep, growth), `core/buildings.gd` (building chains and effects), `core/construction.gd` (build, upgrade, cancel), `core/armies.gd` (army composition, recruitment queue, disband, replenishment, new generals; placeholders in `data/recruitment.json`, names in `data/names.json`), `core/ai.gd` (campaign AI, docs/ai-design.md: every AI faction acts after the yearly processing through the player's own functions; weights in `data/ai.json`, faction traits in `data/factions.json`; soak test `scripts/ai_soak.gd`), `core/battles.gd` (war status, battles from the map, quick resolve, aftermath, sieges; sim in `core/battle_sim.gd`, deployments `core/battle_deploy.gd` (templates) and `core/deployment.gd` (player placement and orders; screen `ui/deployment_screen.gd` with the 3D tabletop `battle.tabletop` and the 2D `ui/deployment_board.gd`), battlefield `core/battlefield.gd`, report `core/battle_report.gd` (timeline, both unit tables, replay data; drawn by `ui/battle_replay.gd`); numbers in `data/battle.json`, tuned with `scripts/battle_harness.gd`), `core/movement.gd` (army movement points, terrain costs, A* paths, standing orders, garrisons; placeholders in `data/movement.json`), `core/realm.gd` (debt: desertion and disbanding, `data/economy.json` debt; loss condition: grace periods and destruction, `data/campaign_rules.json`), `core/turn_loop.gd` (End Turn sequence), `core/chronicle.gd` (Grey Scribes log). Every economy number lives in `data/economy.json` and every building number in `data/buildings.json` (placeholders); starting state in the map's `campaign_start.json`; endowments and settlement types in its `provinces.json`. Randomness only from generators seeded from the campaign seed (random per new campaign via `GameState.new_campaign()`; tests, the self-test and captures use the start file's fixed seed via `GameState.from_data()`; `--seed=N` replays a campaign). Battle seeds combine the campaign seed, year, battle counter and both sides' armies (`Battles.battle_seed`).
- Saves: `core/save_system.gd` writes `GameState.to_dict()` as JSON (schema version + `MIGRATIONS` hook; bump `SCHEMA` and add a migration whenever the state format changes) through `core/save_codec.gd` (exact int/float types and dictionary order), atomically (temp file + rename) into `user://saves`, with JPEG thumbnails encoded on a worker thread (`SaveSystem.wait_for_images()` before quitting or changing scene). Every piece of campaign state must live in `GameState` fields covered by `to_dict`/`from_dict`, never only in scene nodes. Captures and the self-test save to `user://capture_saves`.
- Implement only confirmed constitution rules; stub anything marked open and say so in code comments and the report.
- Maps live in `data/maps/<map_id>/` (`map.json` with id and version, `provinces.json`, `factions.json`, `campaign_start.json`, `armies/`, `movement.json` overlay). `core/map_registry.gd` holds the active map; every loader reads it. The test map (`testmap`, the prototype world) is the default for tests, the self-test and captures. Bump a map's `version` when its region IDs or geometry change incompatibly (saves from another map version are refused; save schema 4). Design: `docs/map-pipeline-design.md` (approved).
- Army movement reads only the baked terrain grid, never the terrain mesh: the test map's `movement_grid.json` (rebake with `runtimeGodot.exe --path . -- --bake-movement-grid` after changing its heightfield, forest, coast, roads, passes or settlements, and commit it), or a pipeline map's committed `baked/`. Movement rules live in `data/movement.json`; each map's road network and passes in its `movement.json`, and the map draws the same polylines.
- Weapon grips are generated by `scripts/fit_weapon_grips.gd`; rerun it after changing a pose or weapon instead of hand-editing `visuals/weapons/*.tscn`.

## Free and local only

- No paid tools, services, or assets. No required servers or network at runtime.
- Allowed licenses: CC0; SIL Open Font License (fonts only); CC BY, only with the required attribution recorded in `ASSETS.md`. Anything else (including "free" custom licenses such as the Quaternius Asset License) needs the user's approval first.
- Record source URL, author, and license for every third-party asset in `ASSETS.md` in the same commit that adds it.
- Ask before downloading asset packs or adding dependencies.
- Only files the game uses live in `assets/`. The rest of a downloaded pack waits in the git-ignored `asset_staging/` (with `.gdignore`, so Godot neither imports nor exports it); copy a file into `assets/` and record it in `ASSETS.md` when it is first used. CC BY assets also need the in-game credits line (`ui/main_menu.gd` `CREDITS`).

## Repository hygiene

- Never commit secrets, executables (`runtime/Godot.exe`, `*.exe`), generated caches (`.godot/`, `.local/`), captures, or work-related material.
- Commits use the repo-local identity `jwerdel` / `121633115+jwerdel@users.noreply.github.com` (GitHub noreply) for both author and committer. Confirm `git config --local user.email` is that address before the first commit of a session.
- Never put personal email addresses, real names, employer names, or other identifying information in files, commit messages, or asset metadata. Strip metadata from images before committing them.
- Small, focused commits with clear messages.
- Never add Co-Authored-By or any Claude attribution to commits.
- Commit the `.uid` files Godot generates next to scripts and shaders.

## Engine and running

- Engine is pinned to Godot 4.7.2 (standard build). `scripts/get_godot.ps1` downloads and SHA-512-verifies it into `runtime/`. Upgrading means changing the version and hash there, then updating `project.godot` and the constitution.
- Play: `Play Project Freedom.cmd` (redirects user data into `.local/`, imports on first run). The project opens on the main menu (`ui/main_menu.tscn`); `--capture`, `--self-test`, `--bake-movement-grid`, `--seed=N` and `--campaign` go straight to the campaign (`Main.tscn`), and `--menu` keeps the menu for captures (`--load-screen`, `--menu-load=<file>`). Scenes hand the campaign state over through `core/session.gd`; player settings live in `core/settings.gd` (debug keys on by default).
- After adding or renaming scripts, scenes, or assets, run a headless import so caches and `.uid` files are current:
  `runtime\Godot.exe --headless --path . --import`
- Prototype self-test and screenshot capture (quits when done, writes `captures/overview.png`):
  `runtime\Godot.exe --path . -- --capture --self-test` (add `--developed`, `--closeup`, or `--hero` for other views). Set `APPDATA`/`LOCALAPPDATA` to `.local\...` as the launcher does to keep runtime data in the project.
- When a change must not alter visuals, compare before/after captures.
- Export preset "Windows Desktop" (`export_presets.cfg`) includes `*.json` so the manifest ships, and excludes `addons/gut/*`, `tests/*` and the synthetic test maps (`data/maps/synthetic*/*`). Keep non-resource data files covered by its include filter. Export templates for 4.7.2 install with `powershell -ExecutionPolicy Bypass -File scriptsget_export_templates.ps1` (official .tpz, SHA-512 pinned, Windows templates only, into `runtimeditor_dataxport_templates`, outside git); then `runtimeGodot.exe --headless --path . --export-release "Windows Desktop" build/windows/ProjectFreedom.exe`.
- Scale benchmark (synthetic 600-region map; build it first with `-s scripts/build_map.gd -- --map=synthetic600`): debug `runtimeGodot.exe --headless --path . -s scripts/scale_test.gd -- --turns=2 --out=<file>`; release: export the "Windows Benchmark" preset (feature tag `benchmark`: the main menu hands over to `scripts/scale_bench.gd`) and run `buildenchmarkProjectFreedomBench.exe --headless -- --turns=2 --out=<file>` (release builds print no console output, so use `--out`).

## Godot windows

- Run everything headless by default: GUT tests, logic checks and AI soaks (`--headless`). The self-test's checks run inside a capture run, so batch it with the others.
- Only screenshots, GPU timing and renderer-specific tests open a real window, batched into ONE windowed batch at the end of each phase: `scripts/windowed_batch.sh "<args>" "<args>" ...`.
- Each run is 1440×900 (comparable screenshots), parked almost entirely off-screen in the bottom-right corner of the 1920×1080 screen (`--resolution 1440x900 --position 1880,1040`). It still renders the full frame.
- Godot 4.7.2 window flags (from `Godot.exe --help`): `--resolution WxH`, `--position X,Y`, `--screen N`, `-w` (windowed), `-m` (maximised), `-f` (fullscreen), `-t` (always on top). There is no minimise flag.

## Tests

- Non-trivial logic needs tests.
- Framework: GUT 9.7.1 (Godot Unit Test, MIT) in `addons/gut/`, verified on the portable Godot 4.7.2. Tests live in `tests/`, files named `test_*.gd`, extending `GutTest`.
- Run (after a headless import, so GUT's classes are registered):
  `runtime\Godot.exe --headless --path . --import`
  `runtime\Godot.exe --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
  Exit code 0 means all tests passed.
- Headless runs skip the pixel checks of portrait rendering (the dummy renderer has no pixels). Run once without `--headless` (same command) to check real portraits.
- The prototype's `--self-test` still covers the visual prototype's runtime behavior.

## Code style

- Match the surrounding code. Existing prototype GDScript uses one-space indentation and compact expressions; keep new prototype files consistent with it.
- Reference shared visual helpers through `visuals/common/proto_kit.gd`; preload scripts with `const X = preload(...)` rather than relying on `class_name` (the portable runtime may run without the editor's class cache).

## Reporting

Report results plainly: what changed, what was not done, and any risks. State test and run outcomes as observed, including failures.
