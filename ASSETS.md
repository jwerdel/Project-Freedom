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
| `fir_optimized.glb`, `fir_optimized_fir_sapling_*.jpg` | https://polyhaven.com/a/fir_sapling | CC0. Simplified for real-time use with glTF Transform / meshoptimizer; textures are also embedded in the .glb. |

## Original to this project

Architecture, ships, wagons, the commander, the terrain heightfield, layout, UI, and shaders were built procedurally for this prototype (`main.gd`, `visuals/`, `*.gdshader`). No Total War, Warhammer, Lord of the Rings, or Game of Thrones assets are included. Greyhaven, Crownwatch, Willowmere, and the Greywater March are working names, not final worldbuilding.

## Development tools (committed)

| Path | Tool | Source | License |
|---|---|---|---|
| `addons/gut/` | GUT 9.7.1 (Godot Unit Test) | https://github.com/bitwes/Gut/releases/tag/v9.7.1 (source zip SHA-256 `14969AA46ADC84AA08CDD21B9F6D1A64ADDD92AE60B36F02D0521ED305AA4086`); only `addons/gut/` copied, unmodified | MIT, copyright Tom "Butch" Wesley; see `addons/gut/LICENSE.md` |

## Engine (not committed)

Godot 4.7.2 standard Windows build, MIT license: https://github.com/godotengine/godot/releases/tag/4.7.2-stable . Downloaded by `scripts/get_godot.ps1` into `runtime/` together with `GODOT-LICENSE.txt` and `GODOT-COPYRIGHT.txt`. More information: https://godotengine.org/license/ .

## Fonts

Uses installed Windows system fonts (Georgia, Segoe UI) through Godot's SystemFont. No font files are redistributed.
