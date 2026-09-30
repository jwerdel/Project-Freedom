# Third-party assets and licenses

Every third-party asset in this repository must be listed here with its source and license, in the same commit that adds it. Only CC0 or clearly free-for-commercial-use assets are allowed.

## Poly Haven (CC0)

License: CC0 1.0, https://polyhaven.com/license . Artist credits are on each asset page. Textures are used at 1K resolution.

| File(s) in `assets/` | Source | License |
|---|---|---|
| `aerial_grass_rock_Diffuse.jpg`, `aerial_grass_rock_nor_gl.jpg` | https://polyhaven.com/a/aerial_grass_rock | CC0 |
| `rocky_terrain_Diffuse.jpg`, `rocky_terrain_nor_gl.jpg` | https://polyhaven.com/a/rocky_terrain | CC0 |
| `medieval_blocks_03_Diffuse.jpg`, `medieval_blocks_03_nor_gl.jpg` | https://polyhaven.com/a/medieval_blocks_03 | CC0 |
| `weathered_brown_planks_Diffuse.jpg`, `weathered_brown_planks_nor_gl.jpg` | https://polyhaven.com/a/weathered_brown_planks | CC0 |
| `coast_sand_01_Diffuse.jpg`, `coast_sand_01_nor_gl.jpg` | https://polyhaven.com/a/coast_sand_01 | CC0 |
| `roof_slates_02_Diffuse.jpg`, `roof_slates_02_nor_gl.jpg` | https://polyhaven.com/a/roof_slates_02 | CC0 |
| `plastered_stone_wall_Diffuse.jpg`, `plastered_stone_wall_nor_gl.jpg` | https://polyhaven.com/a/plastered_stone_wall | CC0 |
| `fir_optimized.glb`, `fir_optimized_fir_sapling_*.jpg` | https://polyhaven.com/a/fir_sapling | CC0. Simplified for real-time use with glTF Transform / meshoptimizer; textures are also embedded in the .glb. **Kept in the repo but unused since 2026-09-30**: replaced in the forest by the Quaternius low-poly trees (about 14,300 triangles per fir made trees ~89% of GPU time). `visuals/nature/fir.tscn` still wraps it but is not in the manifest; to bring it back, point `nature.tree` at that scene. |

## Original to this project

Architecture, ships, wagons, the commander, the terrain heightfield, layout, UI, and shaders were built procedurally for this prototype (`main.gd`, `visuals/`, `*.gdshader`). No Total War, Warhammer, Lord of the Rings, or Game of Thrones assets are included. Greyhaven, Crownwatch, Willowmere, and the Greywater March are working names, not final worldbuilding.

## Quaternius (CC0) — imported

Author: Quaternius (https://quaternius.com). License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/ . Files are copied unmodified from the downloaded pack's `glTF/` folder (self-contained `.gltf`, buffers embedded, flat material colors, no textures).

### Ultimate Fantasy RTS — `assets/quaternius/ultimate-fantasy-rts/`

Source: https://quaternius.com/packs/ultimatefantasyrts.html (full pack, free Google Drive download). License file: `License.txt`, copied from the pack; it says "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication" (its header line says "Ultimate Platformer Pack", a copy-paste slip in the pack itself; the official page for this pack also says CC0).

| File | Pack path | Triangles | Used as |
|---|---|---|---|
| `Resource_PineTree.gltf` | `glTF/Resource_PineTree.gltf` | 345 | Forest tree (`nature.tree`) |
| `Resource_Tree1.gltf` | `glTF/Resource_Tree1.gltf` | 552 | Forest tree (`nature.tree`) |
| `Resource_Tree2.gltf` | `glTF/Resource_Tree2.gltf` | 384 | Forest tree (`nature.tree`) |
| `Resource_Rock_1.gltf` | `glTF/Resource_Rock_1.gltf` | 632 | Coastal rock (`nature.rock`) |
| `Resource_Rock_2.gltf` | `glTF/Resource_Rock_2.gltf` | 588 | Coastal rock (`nature.rock`) |
| `Rock.gltf` | `glTF/Rock.gltf` | 162 | Coastal rock (`nature.rock`) |
| `License.txt` | `License.txt` | — | Pack license |

## Approved placeholder packs (license confirmed)

Approved by the user on 2026-09-30. CC0 was confirmed on each official page that day (the "License CC0" label in the pack's sidebar links to https://creativecommons.org/publicdomain/zero/1.0/). Import only the files we use, into `assets/quaternius/<pack>/`, with that pack's `License.txt`. When files are imported, list them in the imported section above. Do not swap the remaining planned uses into the prototype until that is approved.

The downloaded copies were checked on 2026-09-30: each pack's own license file says CC0 1.0 Universal (`License.txt` in Ultimate Fantasy RTS, Animals and Universal Animation Library; `License_Standard.txt` in Universal Base Characters and Modular Character Outfits – Fantasy). The Pirate Kit download has no license file; its license source is the official page https://quaternius.com/packs/piratekit.html , which states "CC0" (linking to https://creativecommons.org/publicdomain/zero/1.0/) and "free to use in personal and commercial projects" (checked 2026-09-30).

| Pack | Official page | Download | Planned use |
|---|---|---|---|
| Ultimate Fantasy RTS | https://quaternius.com/packs/ultimatefantasyrts.html | Google Drive, full pack free | Trees and rocks: imported (above). Not yet imported: FirstAge town center, houses, watchtower, walls, farm, windmill, port and dock at levels 1–3 |
| Pirate Kit | https://quaternius.com/packs/piratekit.html | Google Drive, full pack free | `Ship_Small` and `Ship_Large` only |
| Universal Base Characters | https://quaternius.com/packs/universalbasecharacters.html | itch.io, free Standard tier (2 base models, 5 hairstyles) | Shared soldier and commander body (humanoid rig) |
| Modular Character Outfits – Fantasy | https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | itch.io, free Standard tier (Ranger and Peasant outfits) | Placeholder soldier and commander outfits |
| Universal Animation Library | https://quaternius.com/packs/universalanimationlibrary.html | itch.io, free Standard tier (45 animations) | Idle, walk and run for placeholder units |
| Ultimate Animated Animal Pack | https://quaternius.com/packs/ultimateanimatedanimals.html | Google Drive, full pack free | `Horse` only |

## Development tools (committed)

| Path | Tool | Source | License |
|---|---|---|---|
| `addons/gut/` | GUT 9.7.1 (Godot Unit Test) | https://github.com/bitwes/Gut/releases/tag/v9.7.1 (source zip SHA-256 `14969AA46ADC84AA08CDD21B9F6D1A64ADDD92AE60B36F02D0521ED305AA4086`); only `addons/gut/` copied, unmodified | MIT, copyright Tom "Butch" Wesley; see `addons/gut/LICENSE.md` |

## Engine (not committed)

Godot 4.7.2 standard Windows build, MIT license: https://github.com/godotengine/godot/releases/tag/4.7.2-stable . Downloaded by `scripts/get_godot.ps1` into `runtime/` together with `GODOT-LICENSE.txt` and `GODOT-COPYRIGHT.txt`. More information: https://godotengine.org/license/ .

## Fonts

Uses installed Windows system fonts (Georgia, Segoe UI) through Godot's SystemFont. No font files are redistributed.
