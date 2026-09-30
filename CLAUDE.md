# Project Freedom — rules for every session

Godot 4.7.2 fantasy strategy game. Personal project; free and local only.

## Project location (check first, every session)

- The canonical project path is `C:\Users\Owner\dev\project-freedom`. It does not live on the OneDrive Desktop.
- At the start of every session, confirm the working directory is this repo root: `CLAUDE.md` is present and `git remote get-url origin` is `https://github.com/jwerdel/Project-Freedom.git`. If not, stop and tell the user before doing anything else.
- Never create or keep project files inside OneDrive.

## Source of truth

- `constitution.md` is the design source of truth. Read it before design or gameplay work.
- Never implement a mechanic the constitution lists as open, unresolved, or undecided without the user's approval. Ask instead.
- Keep confirmed decisions separate from open questions when editing the constitution.

## Art / data separation (critical)

- Gameplay values (size, footprint, speed, stats, costs) live in data files (Godot Resources or JSON under `data/`). Never derive them from meshes, bounding boxes, or visual scenes.
- Every visual is its own scene under `visuals/` (e.g. `visuals/units/spearman.tscn`), plugged into a generic gameplay scene. Swapping art = swapping the visual scene only; no gameplay code changes.
- One asset manifest, `data/asset_manifest.json`, maps unit / building / road IDs to visual scene paths. Load visuals only through `core/asset_manifest.gd` (`AssetManifest.instantiate(id)`), never by hard-coded scene path in gameplay code.
- Two scales:
  - World/battle scale: 1 Godot unit = 1 meter; humans about 1.8 m, including placeholders. Applies to deployment and battle scenes and to the source proportions of every character model.
  - Campaign map scale: stylized miniature. Generals and heroes are deliberately oversized relative to settlements for readability. The current prototype's proportions (recorded in the constitution) are the reference. Campaign figures are scaled-up world-scale sources, not separately proportioned models.
- Characters use a standard humanoid skeleton compatible with Godot's humanoid retargeting (SkeletonProfileHumanoid / BoneMap).
- All soldiers may share one placeholder model for now; unit cards must still visually resemble their unit.

## Unit cards (planned, not built yet)

Portraits are auto-rendered from the unit's visual scene (SubViewport render, cached), so cards always match current art. Do not hand-paint or separately maintain portrait images.

## Free and local only

- No paid tools, services, or assets. No required servers or network at runtime.
- Only CC0 or clearly free-for-commercial-use assets. Record source URL, author, and license for every third-party asset in `ASSETS.md` in the same commit that adds it.
- Ask before downloading asset packs or adding dependencies.

## Repository hygiene

- Never commit secrets, executables (`runtime/Godot.exe`, `*.exe`), generated caches (`.godot/`, `.local/`), captures, or work-related material.
- Commits use the repo-local personal identity; confirm it before the first commit of a session if it looks unset.
- Small, focused commits with clear messages.
- Commit the `.uid` files Godot generates next to scripts and shaders.

## Engine and running

- Engine is pinned to Godot 4.7.2 (standard build). `scripts/get_godot.ps1` downloads and SHA-512-verifies it into `runtime/`. Upgrading means changing the version and hash there, then updating `project.godot` and the constitution.
- Play: `Play Project Freedom.cmd` (redirects user data into `.local/`, imports on first run).
- After adding or renaming scripts, scenes, or assets, run a headless import so caches and `.uid` files are current:
  `runtime\Godot.exe --headless --path . --import`
- Prototype self-test and screenshot capture (quits when done, writes `captures/overview.png`):
  `runtime\Godot.exe --path . -- --capture --self-test` (add `--developed`, `--closeup`, or `--hero` for other views). Set `APPDATA`/`LOCALAPPDATA` to `.local\...` as the launcher does to keep runtime data in the project.
- When a change must not alter visuals, compare before/after captures.

## Tests

- Non-trivial logic needs tests.
- Framework: GUT (Godot Unit Test, MIT, pure GDScript, runs from the command line with the portable engine). Not installed yet; it will live in `addons/gut/` with tests in `tests/` (files named `test_*.gd`).
- Run (once installed):
  `runtime\Godot.exe --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Until GUT is added, the prototype's `--self-test` covers the existing visual prototype.

## Code style

- Match the surrounding code. Existing prototype GDScript uses one-space indentation and compact expressions; keep new prototype files consistent with it.
- Reference shared visual helpers through `visuals/common/proto_kit.gd`; preload scripts with `const X = preload(...)` rather than relying on `class_name` (the portable runtime may run without the editor's class cache).

## Reporting

Report results plainly: what changed, what was not done, and any risks. State test and run outcomes as observed, including failures.
