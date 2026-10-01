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

Source: https://quaternius.com/packs/ultimatefantasyrts.html (full pack, free Google Drive download). License file: `License.txt`, copied from the pack; it says "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication" (its header line says "Ultimate Platformer Pack", a copy-paste slip in the pack itself; the official page for this pack also says CC0). The Goldspire pieces' red "Main" team-color material is swapped for gold at runtime by `visuals/landmarks/goldspire_rock_visual.gd`; the files themselves are unmodified. Triangle counts are as shipped, before the campaign-scale transform.

| File | Pack path | Triangles | Used as |
|---|---|---|---|
| `Resource_PineTree.gltf` | `glTF/Resource_PineTree.gltf` | 345 | Forest tree (`nature.tree`) |
| `Resource_Tree1.gltf` | `glTF/Resource_Tree1.gltf` | 552 | Forest tree (`nature.tree`) |
| `Resource_Tree2.gltf` | `glTF/Resource_Tree2.gltf` | 384 | Forest tree (`nature.tree`) |
| `Resource_Rock_1.gltf` | `glTF/Resource_Rock_1.gltf` | 632 | Coastal rock (`nature.rock`) |
| `Resource_Rock_2.gltf` | `glTF/Resource_Rock_2.gltf` | 588 | Coastal rock (`nature.rock`) |
| `Rock.gltf` | `glTF/Rock.gltf` | 162 | Coastal rock (`nature.rock`) |
| `WatchTower_SecondAge_Level1.gltf` | `glTF/WatchTower_SecondAge_Level1.gltf` | 3,564 | Goldspire Rock: gold-roofed summit and terrace towers |
| `WatchTower_SecondAge_Level2.gltf` | `glTF/WatchTower_SecondAge_Level2.gltf` | 3,216 | Goldspire Rock: crenellated summit towers (stage 2+) |
| `TowerHouse_SecondAge.gltf` | `glTF/TowerHouse_SecondAge.gltf` | 3,824 | Goldspire Rock: summit keep (stage 2+) |
| `Temple_SecondAge_Level1.gltf` | `glTF/Temple_SecondAge_Level1.gltf` | 443 | Goldspire Rock: the gold spire (stage 3) |
| `WallTowers_SecondAge.gltf` | `glTF/WallTowers_SecondAge.gltf` | 1,792 | Goldspire Rock: summit curtain wall (stage 2+) |
| `WallTowers_Door_SecondAge.gltf` | `glTF/WallTowers_Door_SecondAge.gltf` | 1,920 | Goldspire Rock: summit and land gates (stage 2+) |
| `Wall_SecondAge.gltf` | `glTF/Wall_SecondAge.gltf` | 216 | Goldspire Rock: land wall (stage 2+) |
| `Houses_SecondAge_1_Level1.gltf` | `glTF/Houses_SecondAge_1_Level1.gltf` | 2,336 | Goldspire Rock: terrace houses (stage 3) |
| `Houses_SecondAge_3_Level1.gltf` | `glTF/Houses_SecondAge_3_Level1.gltf` | 964 | Goldspire Rock: terrace and summit houses (stage 3) |
| `Storage_SecondAge_Level1.gltf` | `glTF/Storage_SecondAge_Level1.gltf` | 8,160 | Goldspire Rock: terrace halls (stage 3) |
| `Port_SecondAge_Level1.gltf` | `glTF/Port_SecondAge_Level1.gltf` | 6,672 | Goldspire Rock: harbor (stage 2) |
| `Port_SecondAge_Level2.gltf` | `glTF/Port_SecondAge_Level2.gltf` | 7,438 | Goldspire Rock: harbor (stage 3) |
| `Dock_FirstAge.gltf` | `glTF/Dock_FirstAge.gltf` | 388 | Goldspire Rock: piers (stage 2+) |
| `License.txt` | `License.txt` | — | Pack license |

### Modular Weapons Pack — `assets/quaternius/weapons/`

Source: https://quaternius.com/packs/medievalweapons.html ("Modular Weapons Pack", 24 models, CC0 on the official page, checked 2026-09-30). Downloaded as FBX only. License file: `License.txt`, copied from the download; it says "Medieval Weapons by @Quaternius" and "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication". The FBX files import with Godot 4.7.2's built-in FBX importer (ufbx); they come in about 5× real size, so each weapon's campaign scale is set in `data/units/weapons.json`. Files copied unmodified.

| File | Used by |
|---|---|
| `Spear.fbx` | Peasant Levy, Spearmen, Cavalry (as a lance) |
| `Shield_Round.fbx` | Spearmen |
| `Bow_Wooden.fbx` | Archers |
| `Sword.fbx` | Swordsmen |
| `Shield_Heater.fbx` | Swordsmen; Heavy Infantry (scaled up as a large shield) |
| `Hammer_Double.fbx` | Heavy Infantry |
| `License.txt` | Pack license |

## Kenney (CC0) — imported

Author: Kenney (https://www.kenney.nl). License: CC0 1.0 Universal; credit is appreciated but not required. Files copied unmodified; the white Fantasy UI Borders are tinted in code.

### Fantasy UI Borders — `assets/kenney/fantasy-ui-borders/`

Source: https://kenney.nl/assets/fantasy-ui-borders (version 1.0). `License.txt` copied from the download states CC0.

| File | Pack path | Used as |
|---|---|---|
| `panel-border-010.png` | `PNG/Default/Border/panel-border-010.png` | Main panel frame (9-slice, gold tint) |
| `panel-border-001.png` | `PNG/Default/Border/panel-border-001.png` | Card and button frame (9-slice) |
| `panel-border-015.png` | `PNG/Default/Border/panel-border-015.png` | Thin frame for slots and small widgets (9-slice) |
| `divider-fade-000.png` | `PNG/Default/Divider Fade/divider-fade-000.png` | Section divider |
| `License.txt` | `License.txt` | Pack license |

### UI Pack: RPG Expansion — `assets/kenney/rpg-expansion/`

Source: https://kenney.nl/assets/ui-pack-rpg-expansion . `License.txt` is the download's `license.txt`, which states CC0.

| File (same name in the pack's `PNG/`) | Used as |
|---|---|
| `buttonRound_brown.png`, `buttonRound_beige.png` | Round menu and minimap buttons |
| `buttonLong_brown.png`, `buttonLong_brown_pressed.png`, `buttonLong_beige.png` | Tabs and text buttons (normal, pressed, selected) |
| `panel_beige.png` | Parchment tooltips |
| `panelInset_brown.png` | Building slot background |
| `barBack_horizontal{Left,Mid,Right}.png` | Public order bar track |
| `barGreen_horizontal{Left,Mid,Right}.png`, `barRed_horizontal{Left,Mid,Right}.png` | Public order bar fill (positive / negative) |
| `iconCross_grey.png` | Locked building slot |
| `License.txt` | Pack license |

## Fonts (SIL Open Font License 1.1) — `assets/fonts/`

Downloaded 2026-09-30 from the Google Fonts repository (https://github.com/google/fonts). Each font's OFL text is kept next to it.

| File | Font | Source | Copyright | SHA-256 |
|---|---|---|---|---|
| `Cinzel-Variable.ttf` | Cinzel (variable weight), headers | `ofl/cinzel/Cinzel[wght].ttf`; project https://github.com/NDISCOVER/Cinzel | 2020 The Cinzel Project Authors | `f4d83d34d1f6c741193e4acf4b3dff9531e5a67b6aa65228d00a7db72a4e0f34` |
| `AlegreyaSans-Regular.ttf`, `AlegreyaSans-Bold.ttf` | Alegreya Sans, body text | `ofl/alegreyasans/`; project https://github.com/huertatipografica/Alegreya-Sans | 2013 The Alegreya Sans Project Authors | `8fab6341…ea10` (Regular), `a3055a18…fb8e` (Bold) |
| `Cinzel-OFL.txt`, `AlegreyaSans-OFL.txt` | License texts | `OFL.txt` in each font folder | — | — |

## Reviewed and rejected

| Pack | Reason | Decision |
|---|---|---|
| Bestiary – Dungeon Monsters Kit (Quaternius, free Standard tier: Imp, Puglin) | Quaternius Asset License v1.0 (https://quaternius.com/license.html), not CC0: free commercial use but no redistribution of the assets themselves. Textured, sculpted PBR style that does not match the flat-color low-poly map. | Rejected by the user, 2026-09-30. Not imported. |

## Approved placeholder packs (license confirmed)

Approved by the user on 2026-09-30. CC0 was confirmed on each official page that day (the "License CC0" label in the pack's sidebar links to https://creativecommons.org/publicdomain/zero/1.0/). Import only the files we use, into `assets/quaternius/<pack>/`, with that pack's `License.txt`. When files are imported, list them in the imported section above. Do not swap the remaining planned uses into the prototype until that is approved.

The downloaded copies were checked on 2026-09-30: each pack's own license file says CC0 1.0 Universal (`License.txt` in Ultimate Fantasy RTS, Animals and Universal Animation Library; `License_Standard.txt` in Universal Base Characters and Modular Character Outfits – Fantasy). The Pirate Kit download has no license file; its license source is the official page https://quaternius.com/packs/piratekit.html , which states "CC0" (linking to https://creativecommons.org/publicdomain/zero/1.0/) and "free to use in personal and commercial projects" (checked 2026-09-30).

| Pack | Official page | Download | Planned use |
|---|---|---|---|
| Ultimate Fantasy RTS | https://quaternius.com/packs/ultimatefantasyrts.html | Google Drive, full pack free | Trees, rocks and the Goldspire Rock pieces: imported (above). Not yet imported: FirstAge town center, houses, watchtower, walls, farm, windmill, port and dock at levels 1–3 for the generic settlements |
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

## System fonts

The legacy prototype labels still use installed Windows system fonts (Georgia, Segoe UI) through Godot's SystemFont. These are not redistributed.
