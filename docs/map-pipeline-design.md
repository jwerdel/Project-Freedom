# Map-authoring pipeline: design

**Status:** APPROVED (owner, 2026-10-02). Decisions on every open question: section 11. Numbers are proposals or placeholders unless marked as measured.
**Implements:** game-design §21 roadmap item 4 (map-authoring pipeline) and prepares item 5 (Map Stage A).
**Reads:** `constitution.md` (mechanics), `docs/game-design.md` §3, §10.9, §11.4, §12, §19, `docs/world-bible-v2.md` §1, §6–§8, §10, `docs/v1-scope.md`.

---

## 0. Summary

- **Authoring.** The world is written as a **vector sketch plus data** and generated from them; nothing is modelled by hand:
  - `sketch.svg`, editable in Inkscape: coasts, mountain ranges, rivers, region sites, borders, sea lanes, the Greywall.
  - `world.json`: names, owners, settlements, resources, culture and faith.
  - Optional low-resolution painted override layers (Krita or GIMP) where shapes alone aren't enough.

  Claude Code (CC) writes the SVG and JSON from your descriptions. You can drag points in Inkscape, edit the JSON, or paint an override, then rebuild.
- **Generation.** A headless build script turns the sources into:
  - heightfield, region map, settlements, roads, river crossings and passes;
  - the movement grid and the region, road and sea graphs;
  - resources and climate;
  - the strategic map textures.

  The same validator runs after every build and in a GUT test.
- **Runtime.** The 3D campaign map draws terrain as GPU-displaced chunks with built-in LOD. Trees, settlements and props are streamed around the camera. The camera never shows the whole world in 3D: past the farthest zoom, the strategic map takes over (already built). That is what makes TW:WH3 scale affordable.
- **Scale target.** About 320 regions and about 950 settlements for V1 Varos (minus the Ashlands). Budgets are sized for 600 regions, 1,500 settlements and 150 factions. TW:WH3's Immortal Empires has 214 provinces and about 554 settlements (regions), per the [province list](https://totalwarwarhammer.fandom.com/wiki/Immortal_Empires_province_list).
- **Migration.** The prototype map is re-authored in the new format as the **test map** (same layout, same IDs, same three placeholder factions), so tests, the self-test and captures keep a small stable world. Saves get a map ID and map version (schema 4). Saves from older map versions are **incompatible during development**.
- **Stage A.** Aldryn from just beyond the Greywall to the Red Peaks' north face:
  - all three playable starts, Caeloth, 11 major AI factions and about 28 minor ones;
  - 13 landmarks;
  - about 36 provinces, 85–95 regions and about 230 settlements.

---

## 1. Terms

| Ours | TW:WH3 | Meaning |
|---|---|---|
| **Province** | Province | A group of 1–5 regions. The constitution's "country". |
| **Region** | Region (one settlement each) | The constitution's "territory": one **major settlement** (city or fortress), its land, and its minor settlements. Region ID = major settlement ID (as today). |
| **Minor settlement** | (none) | Village (economic), castle (defensive) or town (mixed) inside a region (constitution, Economy and settlements). |
| **Sea zone** | Sea region | Water area, coastal or high seas. |
| **Stage** | – | A built part of the world (game-design §19.1). |

---

## 2. Authoring workflow

### 2.1 Options compared

| | A. Painted images | B. Pure data, procedural | C. Hybrid (recommended) |
|---|---|---|---|
| Sources | 16-bit heightmap, province colour-ID map, climate map, forest mask, painted in Krita or GIMP | One JSON description (control points, ranges, rivers, sites); noise and distance fields fill in the rest | SVG geometry (Inkscape) + JSON attributes + optional painted override layers |
| "Describe it in words, CC builds it" | Poor: CC can't paint convincingly; it would have to generate images by script, which is option B in disguise | Good: CC edits text | Good: CC edits SVG text and JSON |
| Your hand edits | Excellent for shapes and heights; tedious and error-prone for IDs (exact colours per region) | Awkward: moving a coastline means editing numbers | Drag points and lines in Inkscape, paint where needed, edit names in JSON |
| Diffs and review | Binary images, unreadable diffs | Clean diffs | Clean diffs (SVG and JSON are text); overrides are small images |
| Scales to hundreds of regions | ID colours get hard to manage | Yes | Yes (regions are generated from sites, not drawn) |
| Visual control | Highest | Lowest (noise decides) | High where it matters (coasts, ranges, borders), noise for detail |
| Risk | ID mismatches between images | Bland or unconvincing terrain | An SVG subset to parse; Inkscape conventions to follow |

**Recommendation: C, the hybrid.**

### 2.2 Sources of one map (`data/maps/<map_id>/`)

| File | Edited with | Holds |
|---|---|---|
| `map.json` | text | Map ID, version, world size, cell size, chunk size, sea level, seed for detail noise, stage list and stage boundaries |
| `sketch.svg` | Inkscape (or CC as text) | Geometry in layers (2.3) |
| `world.json` | text (CC) | Provinces, regions, settlements, factions' starts, resources, culture and faith mix, landmarks, outpost slots (section 3) |
| `factions.json`, `campaign_start.json`, `armies/*.json` | text | As today, per map |
| `overrides/*.png` (optional) | Krita or GIMP | Low-resolution painted tweaks: height offset, forest density, climate, "keep flat". 8-bit greyscale, 4–8 m per pixel |
| `baked/` | generated, never by hand | Build outputs (section 4.2) |

### 2.3 Sketch layers (SVG)

One Inkscape layer per kind of feature. Each element has an `id` the JSON refers to. World coordinates are 1 SVG unit = 1 m, with the origin at the map's north-west corner.

| Layer | Elements | Meaning |
|---|---|---|
| `land` | closed paths | Coastlines of continents and islands |
| `lakes` | closed paths | Inland water |
| `ranges` | open paths with `data-height`, `data-width` | Mountain ridges (impassable except at passes) |
| `hills` | closed paths | Hill country |
| `forests` | closed paths with `data-density` | Forests (also drawn by the forest generator; this layer steers it) |
| `rivers` | open paths, source to mouth, with `data-width` | Rivers |
| `sites` | circles with `id` = region ID | Position of each region's major settlement |
| `minor_sites` (optional) | circles | Pinned minor settlements (the rest are placed automatically) |
| `borders` (optional) | open paths | Hard region or province borders where you want them exactly |
| `passes` | circles on a range | Passes through a range |
| `roads` (optional) | open paths | Pinned roads (the rest are generated) |
| `sea_lanes` | open paths | Shipping lanes and trade lanes at sea |
| `greywall` | one open path, with gate circles | The Greywall and its gates |
| `climate` (optional) | closed paths with `data-climate` | Climate zones overriding the latitude default |
| `stages` | closed paths, `id` = stage | Stage boundaries |

**Inkscape conventions:**
- Absolute coordinates: Preferences → Input/Output → SVG output → Path data → Absolute.
- No transforms on layers; the build script reports any it finds.
- Labels are free; IDs carry meaning.

The parser supports a deliberately small SVG subset:
- `path` with M, L, C, Q and Z commands, flattened to polylines;
- `circle`, `ellipse` and `polygon`.

Anything else is an error with the element ID.

### 2.4 The loop: describe → build → look → adjust

1. **You describe:** "a fjord north of Frosthold with two fishing villages; the Barrowlands are low moor with burial mounds".
2. **CC edits** `sketch.svg` and `world.json`, then runs the build (headless) and the validator.
3. **CC shows the result** with captures from the phase's one windowed batch: a strategic map with the affiliation and debug layers, plus a 3D view of the area.
4. **You adjust** by hand:
   - drag the coastline in Inkscape;
   - paint "more forest" in `overrides/forest.png`;
   - rename a village in `world.json`.

   Or describe the change and CC makes it.
5. **Preview while you edit.** `--map-preview=<map_id>` opens the strategic map with the debug overlay and rebuilds the affected outputs when a source file changes (watching file times). Region-level changes rebuild in seconds.

---

## 3. Data model

Field names are proposals. Every number is a placeholder that lives in data.

### 3.1 Map (`map.json`)

`id`, `version` (integer; bump when IDs or geometry change incompatibly), `size` [x, z] in m, `cell` (movement and region raster, m), `height_texel` (m), `chunk` (m), `sea_level`, `detail_seed`, `stages` [{`id`, `name`, `built`: bool}].

### 3.2 Geography (from the sketch, referenced by ID)

- **Continent:** `id`, `name`, `land` path IDs, default climate band. Aldryn, Ossara, Sothmire, plus the reserved Ashlands.
- **Sea zone:** `id`, `name`, `kind` (`coastal` or `high_seas`).
  - High seas need the right ship class (constitution, Naval; details open).
  - Generated by default from the distance to the coast plus `sea_lanes`; can be pinned with paths.
- **Range:** ridge height and width.
- **Pass:** `id`, the range it crosses, width, and an outpost slot of kind `pass` (game-design §12.5).
- **River:** width; crossings are generated where roads cross, and can be pinned as `ford` or `bridge`.
- **Road:** generated between settlements (4.1 step 7) or pinned. Each segment has a level (the existing road stages).
- **Sea lane:** port anchor to port anchor (or to the map or stage edge). Used for naval movement hints and trade-route drawing.
- **Greywall:**
  - one polyline across the north;
  - gates with IDs (the Wardens' Gate landmark is one);
  - segments with IDs every N metres, so "neglected, it falls" (game-design §12.9) can later track strength per segment.

  The wall is impassable except at gates.

### 3.3 Provinces and regions (`world.json`)

```json
{"provinces": [{"id": "frosthold_vale", "name": "Frosthold Vale", "regions": ["frosthold", "hearthwick"], "capital": "frosthold"}],
 "regions": {
  "frosthold": {
   "name": "Frosthold", "province": "frosthold_vale", "owner": "house_varn",
   "major": {"type": "city", "level": 2, "port": false, "landmark": "frosthold"},
   "minor": [{"id": "frosthold_mill", "name": "Millwick", "type": "village", "level": 1}],
   "minor_auto": 2,
   "resources": {"auto": true, "minerals": 1},
   "climate": "auto",
   "culture": {"medieval": 0.9, "roman": 0.1},
   "faith": {"throne_church": 0.85, "radiant_seven": 0.15},
   "race": {"human": 1.0},
   "outposts": "auto"
  }}}
```

| Field | Rule |
|---|---|
| `major.type` | `city` or `fortress` only (constitution: one major city or fortress per territory). The prototype's village and town majors (Willowmere) are kept only on the test map. |
| `major.landmark` | Optional landmark ID. Loads `landmarks.<id>` stages 1–3 from the asset manifest (CLAUDE.md, Landmarks). Footprint, flattening and terrain stamp come from `data/landmarks.json`, never from the mesh. |
| `minor` | Pinned minor settlements; `minor_auto` asks the generator for N more (4.1 step 6). Types: village, castle, town. **Their gameplay is open** (question Q4). |
| `resources` | `auto` derives endowments 0–5 from terrain: farmland and rivers → food; forest → wood; hills → stone; mountains → minerals. Explicit values override (Goldspire Rock's minerals stay exceptional). |
| `climate` | `auto` = latitude band + continent + climate zones + override paint. Values: `frozen`, `cold`, `temperate`, `warm`, `arid`, `jungle`, `swamp`, `mountain`, `grassland`. Race suitability (game-design §10.9) is a separate data table built with that mechanic. |
| `culture`, `faith`, `race` | Starting mix (game-design §11.4); shares sum to 1. Defaults come from the owner's culture; `culture_zones` in the JSON give area defaults (for example "Middle Marches: medieval 0.5, roman 0.3, greek 0.2"). |
| `owner` | Faction ID, or `""` for unsettled land (wilderness regions without a major, like today's Greyspine). |
| `outposts` | `auto`: pass slots from passes, resource slots at resource hot spots, watchtower slots on coasts and borders. Can be listed explicitly. |

### 3.4 Factions (per map `factions.json`, extended)

Fields:
- as today: name, colours, emblem, traits;
- `culture`, `race`, `faith`, `tier` (`playable`, `major`, `minor`, `holy` for Caeloth), `capital`;
- `untouchable` (Caeloth, game-design §9.2);
- `liberator_target` (game-design §3.3), `start_armies`.

Start regions come from region `owner`.

### 3.5 Landmarks (`data/landmarks.json`, new)

`id` → footprint radius (m), flatten radius, terrain stamp (one of a small library: sea cliff, peak, marsh moats, mountain face, sea stacks, river fork), port side.

The **Black Ark** is a moving landmark: it needs the army-like entity from the map-mechanics block, so it comes later (Q9).

---

## 4. Generation

### 4.1 Build steps (headless `scripts/build_map.gd --map=<id>`)

Deterministic: the same sources always give the same outputs.
- Randomness comes only from `detail_seed`, never from the campaign seed, so every campaign plays on the same world.
- Iteration order is sorted by ID.

1. **Parse and check the sources.**
   - SVG subset, JSON schemas.
   - Every SVG `id` referenced and every reference resolved.
2. **Rasterise the land.**
   - Land, lakes and sea mask at `cell` resolution.
   - Signed distance to the coast (for beaches, cliffs and coastal sea zones).
3. **Heightfield** at `height_texel` resolution:
   - base: gentle noise by continent;
   - hills: noise inside hill areas;
   - ranges: ridged noise along range polylines, by `data-height` and `data-width`;
   - passes: a saddle lowered to passable slope;
   - rivers: valleys carved so that each river's bed only descends from source to mouth;
   - settlements: plateaus flattened under sites and landmark footprints, plus landmark terrain stamps;
   - overrides: height-offset paint added last.

   Built with Godot's native `FastNoiseLite.get_image()` and `Image` operations, not per-pixel GDScript loops.
4. **Regions.**
   - A cost-weighted flood fill from the region sites over land.
   - Ranges, rivers and pinned `borders` raise the cost, so borders follow ridges and rivers the way TW borders do.
   - Output: a **region-ID raster** (16-bit) and simplified region polygons (for drawing and the existing `WorldMap.regions()` API).
   - Provinces are the union of their regions.
5. **Classification.** Each cell becomes `open`, `forest`, `hills`, `mountain`, `pass`, `water`, `settlement` or `wall`, using the thresholds in `data/movement.json` (as today's bake does). Forest comes from the forest generator: climate × slope × the `forests` layer × override paint.
6. **Minor settlements.** Auto-placement fills `minor_auto`:
   - candidates are flat, dry cells near a road, river or coast, at a minimum spacing from other settlements;
   - type follows the terrain: villages on farmland, castles at passes and borders, towns at road junctions;
   - names come from the world bible §10 conventions, from a per-culture syllable table in data.
7. **Roads.**
   - A* on a road-cost grid (slope, rivers, forest), from every minor settlement to its region's major, between majors in each province, and between neighbouring provinces' capitals.
   - Pinned roads are kept; overlapping paths are merged into a graph.
   - River crossings are created where roads cross rivers (bridges or fords).
8. **Graphs.**
   - Region adjacency, with crossing points (land, pass, ford, bridge, gate).
   - Sea zones and port anchors: each coastal major gets the nearest deep-water cell as its anchor.
   - The road graph.
   - Trade lanes: land lanes follow the road graph; sea lanes follow `sea_lanes` and the sea-zone graph.
9. **Derived data:**
   - resources (`auto`);
   - climate per region;
   - outpost slots;
   - culture, faith and race defaults;
   - the start-position check (5.1).
10. **Strategic map textures:**
    - parchment and terrain colour textures;
    - the region-ID texture;
    - a border mask;
    - label anchors per province and region.
11. **Validate** (section 5) and write `baked/` plus a build report (counts, timings, warnings).

### 4.2 Outputs: committed vs cached

| Output | Size, V1 Varos estimate | Where |
|---|---|---|
| Movement grid (one byte per cell, PNG) | 2048 × 1280 at 2 m: about 0.5–1 MB | **Committed** (gameplay; replaces today's `data/movement_grid.json` text format for new maps) |
| Region-ID raster (16-bit PNG) | about 0.3 MB (large flat areas compress well) | **Committed** (gameplay: O(1) `region_at`) |
| Region polygons, adjacency, road graph, sea graph, trade lanes, minor settlements, derived resources, climate and outpost slots (JSON) | 1–3 MB | **Committed** |
| Heightfield (16-bit), splat and biome maps, scatter points, strategic map textures | 10–30 MB | **Local cache** (`user://map_cache/<map_id>/<source hash>/`), rebuilt on first run or after a source change, like the portrait studio cache |

Gameplay outputs are committed so that tests, saves and the AI never depend on a build at startup. A GUT test checks that the committed outputs match the sources' hash, so a stale bake fails loudly.

This replaces the CLAUDE.md rule "rebake with `--bake-movement-grid` and commit" with "run `build_map`, commit `baked/`". CLAUDE.md is updated on implementation.

### 4.3 Runtime: building the 3D map

- **Terrain:**
  - Chunks of 256 m.
  - Every chunk uses one of a few shared flat grid meshes (2, 4, 8 and 16 m vertex spacing) displaced in the vertex shader from the heightfield texture.
  - LOD uses Godot's built-in visibility ranges per chunk (HLOD), with no per-chunk mesh building.
  - Chunk bounds come from per-chunk min and max heights computed at build time.
  - Normals come from the heightfield in the shader.
  - Splat colours come from the biome map. Territory tint and shroud are shader inputs (both exist today in simpler form).
- **Water:** one sea plane (as today) plus river ribbon meshes along river polylines and lake surfaces.
- **Scatter (trees, rocks):**
  - Per-chunk `MultiMeshInstance3D`, one per mesh type, built on a worker thread when a chunk enters the camera's range and freed when it leaves (LRU).
  - Distant forests are read from the terrain tint (as TW does), not drawn as trees.
- **Settlements:**
  - Instantiated through `AssetManifest.instantiate_settlement(id, stage)` for majors with landmarks, and generic `settlement.<type>.stage_N` otherwise; the same goes for minors.
  - Only within a radius of the camera (about 700 m); pooled.
  - The banners (settlement pins) follow the same set.
- **Roads, the Greywall, sea lanes:**
  - Road ribbons per chunk.
  - Greywall segments built from manifest kit pieces (`greywall.segment`, `greywall.tower`; the gate is the Wardens' Gate landmark).
  - Sea and trade lanes drawn only when shown (trade routes, game-design §12.7).
- **Picking and heights on the CPU:** the heightfield image stays in RAM for `height_at` (picking, army figure heights), sampled bilinearly. It is no longer a noise function in `main.gd`.

---

## 5. Validation tooling

### 5.1 Automatic checks (`scripts/validate_map.gd`, also run by the build and by a GUT test per committed map)

Errors fail the build; warnings are listed in the report.

| Check | Level |
|---|---|
| IDs unique; every reference resolves (SVG ↔ JSON ↔ factions ↔ manifest) | Error |
| Every land cell belongs to exactly one region; every region is one connected area | Error |
| Every province's regions are contiguous (by land, or by sea for island provinces flagged `island`) | Error |
| Every settled region has exactly one major settlement of type city or fortress | Error |
| No settlement on water, on a slope over the limit, or within the minimum spacing of another | Error |
| Every major can reach every other major by land, or by sea through a port (excluding regions sealed off on purpose, such as across the high seas before naval research) | Error |
| Ports lie on a coast and their anchor connects to the sea graph | Error |
| Every pass connects the two sides of its range; the range is otherwise impassable along its length | Error |
| Rivers descend from source to mouth and end in the sea, a lake or another river | Error |
| Every road connects; every settlement has a road to its region's major | Warning |
| The Greywall is continuous across the stage; it can be crossed only at gates | Error |
| Factions: each faction in the stage has 1–2 start regions (game-design §3.2) and its capital among them | Error |
| Start positions match the world bible: House Varn at Frosthold; House Varrenus at an estate-city next to Crownhaven; the Aurekids at Goldspire Rock; each Liberator's Call target next to its faction (§7.1) | Error |
| Every major faction has at least two minor factions within two regions (game-design §3.2) | Warning |
| Every landmark used has all three stages in the manifest | Error |
| Caeloth is flagged untouchable | Error |
| Names unique within the map; names follow §10 conventions (suffix check by culture) | Warning |
| Culture, faith and race shares sum to 1 | Error |
| Budgets: settlements per chunk, regions per province (1–5), province count per faction | Warning |
| Committed `baked/` matches the sources' hash | Error |

### 5.2 Debug overlay (in game, debug keys on)

A key toggles each layer on both the 3D map and the strategic map:
- region IDs (colour plus ID labels);
- province borders;
- movement classes;
- passes and crossings;
- the road graph (nodes and edges);
- sea zones, sea lanes and port anchors;
- outpost slots;
- minor settlement candidates;
- chunk bounds and the current LOD per chunk;
- validator problems as red markers, with the message in the tooltip;
- a perf HUD (FPS, GPU ms, draw calls, visible chunks, scatter instances, settlements instantiated).

---

## 6. Scale and performance

### 6.1 Size and density

| | Prototype (today) | Stage A | V1 Varos | Design ceiling |
|---|---|---|---|---|
| World | 280 × 280 m | the Stage A part of Varos | 4,096 × 2,560 m (Ashlands reserved, not built) | same |
| Regions | 4 (+1 unsettled) | 85–95 | about 320 | 600 |
| Settlements (major + minor) | 4 | about 230 | about 950 | 1,500 |
| Factions at start | 3 | about 40 | about 120 | 150 |
| Armies at start / mid-game | 3 / 3–6 | about 55 / about 120 | about 180 / about 350 | 500 |

- **Region spacing:** about 90 m in rich lowlands, 140–180 m in the North, desert and grassland. Today's settlements are 50–80 m apart; regions grow so their minor settlements fit.
- **Figure scale:** the campaign figure scale (commander about 4.4 m) is unchanged.
- **Heightfield:** a 2 m texel (2,048 × 1,280 for V1 Varos).
- **Movement grid:** the 2 m cell (as today).
- **Chunks:** 256 m (16 × 10 chunks).

### 6.2 Budgets on the development PC (Ryzen 7 5700X3D, RTX 4060 8 GB)

Measured today (VALIDATION.md):
- overview at about 2.1 ms GPU and 690 draw calls;
- End Turn 2–5 ms on the prototype;
- AI phase about 1.1 ms per army (debug build, linear in armies);
- path plan about 1 ms on the 140 × 102 grid.

| Budget | Target | How |
|---|---|---|
| Frame rate, campaign 3D | 60 FPS at 1440×900 and 1920×1080 (vsync) | below |
| GPU time, densest area at the farthest 3D zoom | ≤ 8 ms (headroom for the later art pass) | chunk culling, HLOD, scatter only near the camera, shadows limited to about 150 m |
| GPU time, strategic map | ≤ 3 ms | one shader over the baked textures (6.4) |
| Draw calls (3D, including shadows) | ≤ 1,500 at the farthest zoom | MultiMesh per chunk and mesh type; settlements pooled within about 700 m |
| Triangles in view | ≤ 4 million | low-poly placeholders (trees 345–552 triangles); tree impostors beyond about 150 m if needed |
| Tree instances in view | ≤ 15,000 | per-chunk scatter with visibility ranges |
| VRAM | ≤ 2 GB (placeholder art) | heightfield 5 MB (R16), splat and biome maps about 40 MB, shared meshes |
| RAM | ≤ 2.5 GB | streaming scatter and settlements; the campaign state is small |
| New campaign load | ≤ 10 s warm, ≤ 30 s on first run (render cache build) | committed gameplay bakes; render cache built once |
| Save load | ≤ 3 s; save file ≤ 5 MB | as today (JSON, codec), bigger state |
| End Turn, AI phase (release build) | Stage A ≤ 1.5 s, V1 Varos ≤ 4 s; **no frame over 50 ms** during it | time-sliced: factions processed across frames behind the AI turn bar |
| Path preview (held right click) | ≤ 5 ms per update | hierarchical paths (6.3) |
| `region_at` | ≤ 0.01 ms | region-ID raster lookup (today: a loop over polygons) |
| Map build (authoring) | Stage A ≤ 30 s, V1 Varos ≤ 2 min, headless | native Image and noise operations |

A **scale-proof block** comes before any Stage A content (section 8). It runs on a **synthetic map** generated by the same pipeline: 600 regions, 150 factions, 500 armies. It measures every row of this table, so problems show up before content depends on them.

### 6.3 CPU scaling: what changes

- **Pathfinding.** A* over 2.6 million cells per army is too slow.
  - Long paths run A* on the region adjacency graph (about 320–600 nodes) through its crossing points.
  - Cell-level A* then runs only inside the corridor of regions on that route, and only as far as the turns being shown or walked.
  - Results are cached per turn (the AI's snapshot already does this).
- **Lookups.** `region_at` and `province_of` become O(1): raster lookup and a dictionary built at load. Province statistics are cached per turn.
- **AI.**
  - Rules stay identical for every faction (fairness).
  - Factions far from the player and from any war replan their strategic goals every few turns instead of every turn. Their moves still follow the same rules.
  - Odds simulations get a per-turn budget across all factions (recommended in VALIDATION.md, Campaign AI).
  - Factions are processed across frames, never in one frame.
- **Spatial queries.** "Armies near X" moves from a scan over all armies to a grid bucket (spatial hash) updated on moves.

### 6.4 How the camera, shroud and strategic map scale

- **Camera.**
  - The 3D camera keeps today's zoom range (10–210 m), so the 3D view always covers only a few chunks.
  - Zooming out past the farthest zoom opens the strategic map (built); the world-size cost lands there, not in 3D.
  - Camera bounds come from `map.json` and the built stages.
- **Shroud** (game-design §12.6, darkened, no fog):
  - A per-player vision texture (8 m per texel: 512 × 320 for V1 Varos, R8).
  - Updated when vision changes, from armies, settlements, outposts, allies and embassies.
  - Sampled by the terrain, scatter and strategic map shaders.
  - The AI's knowledge rules are a mechanics question for the map-mechanics block; until then the AI keeps its current knowledge.
- **Strategic map.** Today it draws one polygon per region on the CPU (fine for Stage A). For V1 Varos it switches to a shader:
  - the region-ID texture plus a palette texture with one texel per region, so a layer change rewrites a few hundred texels;
  - borders from the ID texture's edges;
  - its own pan and zoom;
  - label LOD: provinces far out, regions closer in, settlements closest;
  - settlement and army icons culled to the view.
- **Minimap.** Today it renders the 3D world. It switches to the strategic map's baked textures, because rendering 10 km² of 3D for a small map isn't affordable.

---

## 7. Migration

1. **Map folders and loader.**
   - Map data moves under `data/maps/<map_id>/`.
   - `WorldMap`, `Movement` and the start loader read the **active map** (`GameState` gets a `map_id`).
   - Default maps:
     - **Tests, the self-test and captures:** the test map, through `GameState.from_data()`.
     - **New Campaign:** Varos once Stage A exists; until then the test map.
2. **The prototype becomes the test map** (`data/maps/testmap/`).
   - It is re-authored in the new format with the same layout: the same region IDs and polygons (pinned as borders), settlement positions, the Greyspine range with its pass, the coast and the Goldspire landmark.
   - It keeps House Aurek, House Lannet and House Verrin and its four settlements, so it stays a small, fast, stable world for tests.
   - Generated terrain differs slightly from today's hand-tuned noise. Captures, the movement grid and a few coordinate-based tests (paths, preview points) are re-baselined **once**, in the migration commit, with before/after captures.
   - There is then one terrain path, and `main.gd`'s hand-written `height_at` noise retires.
3. **`main.gd` becomes map-agnostic.**
   - Prototype specifics move into the test map's data or are gated to it: `CITY_ID`, `GOLDSPIRE_ID`, hand-placed settlement anchors, traffic routes, the F5–F7 debug upgrades and the G bookmark.
   - Traffic becomes sea lanes and roads.
   - The visual showcase (city stages, road stages, Goldspire stages) stays on the test map.
4. **Saves.**
   - Schema 4 adds `map_id` and `map_version`; the 3 → 4 migration sets `testmap`, version 1.
   - Loading a save whose map version differs from the installed map is refused with a clear message: "This save was made with an older version of the map Varos."
   - **Saves are incompatible across map versions during development.** After V1's content freeze, map changes must keep IDs and ship migrations.
5. **Tests.**
   - Existing tests keep the test map.
   - New tests:
     - the pipeline on a tiny map (`data/maps/pipeline_test/`, about 12 regions with a river, a range, a pass, an island and a lake);
     - the validator (one broken copy per check);
     - determinism (two builds give identical outputs);
     - the committed-bake hash check;
     - the scale-proof budgets (headless parts).
6. **The three placeholder factions** never appear on Varos. The world bible (§11) already maps them:
   - House Aurek becomes the Aurekids of Goldspire (playable);
   - House Verrin of Highbloom and House Lannet become Roman or Greek AI or minor factions (Q7).

---

## 8. Stage A proposal

### 8.1 Boundaries

Proposed world frame (the world-outline block fixes it for good). x runs east, z runs south, in metres.

```
x→ 0         300        600        900        1200       1500 | 1800 Narrow Sea | Ossara 1800–3200 | Ashlands 3200–4096 (reserved)
z 0    FROSTWASTE: Ghurmak, Frostmaw Clans, Redhand, Ironjaw Horde ................ Stage B
  250  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ Stage A northern edge ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
       orc fringe: Snowtusk, Grimhollow
  330  ═════════════ THE GREYWALL ═══ Wardens' Gate (x ≈ 650) ═══════════════
       THE NORTH: Frosthold (≈ 600, 520), Dunmoor, Barrowlands, Rowen     THE VALE: Skyreach (≈ 1150, 650)
  800  WESTERN   GREEK COAST          MIDDLE MARCHES and CAELOTH (≈ 760, 960)
       ISLES     Goldspire Rock       Harrow Crossing, Stillwater           STORMLANDS: Tempest Keep (≈ 1380, 1120)
       Brinecrag (≈ 220, 1060)
  1200 (x ≈ 60)  Theros, Kyme         THE REACH: Highbloom (≈ 520, 1260)    CROWNLANDS: Crownhaven (≈ 820, 1300)
                                      Oldstone Citadel                      SKULKMIRE (≈ 1320, 1420)
  1550 ─ ─ ─ ─ ─ RED PEAKS north face: Emberdeep (≈ 800, 1520), Stonefast ─ ─ Stage A southern edge
       RED PEAKS south: Sunforge, Karvak, Deepdelve ....................... Stage B
  1900 SAHREN DESERT: Qaseth, Mer-Khet ......................................... Stage B
  2200+ high seas → SOTHMIRE (z 2200–2560, x 400–1700) ......................... Stage D
```

**Stage A** is Aldryn between z ≈ 250 and z ≈ 1,550, coast to coast, including the Western Isles nearest the Greek coast: about 1.5 × 1.3 km, roughly 1.2 km² of land.

Outside a built stage, the world is shown as dark unexplored edge, impassable; sea lanes end at the edge (Q10). Later stages add regions without moving Stage A's, so Stage A content and IDs stay stable.

### 8.2 Provinces, regions and owners

These are proposals.
- Names in *italics* are new placeholders following world bible §10; every other name is from the world bible.
- Each region's major settlement is a city (C) or fortress (F); ★ marks a landmark.
- Minor settlements (villages, castles, towns), about 1–3 per region, are mostly generated.

| Area | Province | Regions (major) and owner |
|---|---|---|
| **Orc fringe** | *Snowtusk Fells* | *Snowtusk Camp* (F) Snowtusk tribe; *Rimefang* (F) Snowtusk tribe |
| | *Grimhollow Barrens* | Grimhollow (F) Grimhollow tribe; *Skullcairn* (F) Grimhollow tribe |
| **The Greywall** | *The Wall* | ★ Wardens' Gate (F) and *Rimeguard* (F), both the Wardens of the Greywall; *Ashen Tower*, an abandoned wall tower in an unsettled region (the Wall is undermanned) |
| **The North** (Medieval) | *Frosthold Vale* | ★ Frosthold (C) **House Varn**; *Hearthwick* (C) **House Varn** |
| | *Dunmoor* | *Dunmoor Keep* (F) House Dunmoor (Liberator's Call target); *Mirewick* (C) House Dunmoor |
| | *The Barrowlands* | *Kellsford* (C) House Kells; *Barrowmere* (F) the Barrow-lords; *Coldbarrow* (C) House Kells |
| | *Rowen Moors* | *Rowenhold* (F) House Rowen; *Greymere* (C) House Rowen |
| | *Blackpine* | *Blackpine Hold* (F), *Elkford* (C): generated northern house |
| | *The Long Lakes* | *Lakewick* (C), *Osricmere* (C): generated northern house |
| **The Vale** (Medieval) | *Skyreach* | ★ Skyreach (F) House Aldane; *Highford* (C) House Aldane |
| | *The Lower Vale* | *Brightmere* (C), *Stonewick* (C): generated Vale house |
| **Middle Marches** (mixed) | *Caeloth* | ★ Caeloth (C) the Throne Church (untouchable); *Pilgrim's Ford* (C) the Throne Church |
| | *Harrow* | ★ Harrow Crossing (F) House Tollan; *Harrowfield* (C) House Tollan |
| | *Stillwater* | *Stillwater* (C) House Merrow; *Merrowmere* (C) House Merrow |
| | *Brackenmoor* | *Bracke Hall* (F) House Bracke; *Fennick* (C) House Bracke |
| | *Ashford* | *Ashford* (C) House Ashford; *Ashwick* (C) House Ashford |
| | *The Riverforks* | *Forkwatch* (F), *Twinford* (C): generated Marches house |
| **Greek coast** | *Goldspire* | ★ Goldspire Rock (C) **the Aurekids**; *Silverfall* (C) the city of Silverfall (Liberator's Call target) |
| | *Theros* | *Theros* (C) the free city of Theros; *Kallipolis* (C) Theros |
| | *Kyme* | *Kyme* (C) the Philandrid tyranny; *Lykon* (C) *the Lykourgids of Lykon* (Kyme's rivals) |
| | *Elaia* | *Elaia* (C), *Myrtos* (C): generated Greek league |
| | *Delos Minor* (island) | *Delos Minor* (C) the island colony of Delos Minor |
| **Western Isles** (dark elves) | *Brinecrag* | ★ Brinecrag (F) the Reavers of Brinecrag; *Mor-Skerry* (C) the Reavers |
| | *The Grey Stacks* | *Drakhaven* (F) independent reaver captain; *Vael-Shoal* (F) independent reaver captain |
| **The Reach** (Roman) | *Highbloom* | ★ Highbloom (C) House Verrin (Q7); *Orchardium* (C) House Verrin |
| | *Oldstone* | ★ Oldstone Citadel (C) and *Port Dallow* (C), both Port Dallow (Q7) |
| | *Fossa* | *Fossum* (C) House Fossa; *Vinaria* (C) House Fossa |
| **Crownlands** (Roman) | *The Seven Hills* | ★ Crownhaven (C) House Corvinus (Q7); *Varrenum* (C) **House Varrenus** |
| | *Tullia* | *Tullanum* (C) the Tullan estates (Liberator's Call target); *Aquilia* (C) the Tullan estates |
| | *Corvinia* | *Corvinium* (C) House Corvinus; *Sabellum* (C) generated Roman family |
| | *Aemeria* | *Aemerium* (C) House Aemerius; *Lucentia* (C) House Aemerius |
| | *The Via Septem* | *Septimium* (C), *Castra Nova* (F): generated Roman family |
| **Stormlands** (Roman) | *Tempest Coast* | ★ Tempest Keep (F) House Durran; *Stormhaven* (C) House Durran |
| | *The Rainwood* | ★ The Skulkmire (F) the Skulkmire Brood; *Rainwick* (C) generated Stormlands house |
| **Red Peaks north face** (dwarves) | *Emberdeep* | ★ Emberdeep (F) Hold Emberdeep; *Karak Durn* (F) Hold Emberdeep |
| | *Stonefast* | *Stonefast* (F) the Stonefast outpost; *Redgate Pass* (F) the Stonefast outpost |

That is 36 provinces and 73 regions (one unsettled). The world-outline block adds 12–22 more where the geography leaves gaps (wilderness regions, extra coastal and northern regions), for **85–95 regions**. With about 1.5 generated minor settlements per region, that's **about 230 settlements**.

### 8.3 Factions present

- **Playable (3):** House Varn, House Varrenus, the Aurekids.
- **Major AI (11):**
  - House Aldane of Skyreach;
  - the Wardens of the Greywall;
  - House Corvinus, House Aemerius, House Durran of Tempest Keep;
  - the free city of Theros, the Philandrid tyranny of Kyme;
  - Caeloth (the Throne Church, untouchable);
  - Hold Emberdeep;
  - the Reavers of Brinecrag;
  - the Skulkmire Brood.
- **Minor (about 28):**
  - **from the world bible:** Dunmoor, Kells, Rowen, the Barrow-lords; Tollan, Merrow, Bracke, Ashford; the Tullan estates, Port Dallow, Fossa; Silverfall, Delos Minor; Stonefast; Snowtusk, Grimhollow; two independent reaver captains;
  - **proposed:** House Verrin of Highbloom (§11); the Lykourgids of Lykon;
  - **generated:** about eight (two northern, Vale, Marches, Greek league, two Roman families, Stormlands).

That is **about 42 factions**. Every faction starts with one or two regions (game-design §3.2).

**Not in Stage A:**
- the Ironjaw Horde, Frostmaw Clans and Redhand Warband, with Ghurmak (Q8);
- Sunforge, Karvak and Deepdelve;
- Qaseth and Mer-Khet;
- the Black Ark (Q9);
- all of Ossara and Sothmire.

**Non-human races need placeholder rosters** for their AI armies (Q13).

### 8.4 Landmarks in Stage A (13)

Caeloth, Crownhaven, Goldspire Rock (exists), Frosthold, the Greywall and Wardens' Gate, Skyreach, Harrow Crossing, Highbloom, Oldstone Citadel, Tempest Keep, the Skulkmire, Emberdeep, Brinecrag.

Twelve are new. Each needs placeholder stage 1–3 scenes and a `data/landmarks.json` entry with its terrain stamp:
- Caeloth: marsh moats at a river fork;
- Skyreach: a peak;
- Emberdeep: a mountain face;
- Brinecrag: sea stacks;
- Tempest Keep: a storm cliff.

---

## 9. Content pipeline for later stages

### 9.1 Who does what

| Work | CC | Owner |
|---|---|---|
| World outline (coasts, ranges, rivers, culture areas) from the world bible | Drafts it | Approves it from strategic-map captures, drags shapes in Inkscape if wanted |
| Region sites, provinces, region and settlement names (§10 conventions) | Generates and lists | Renames anything; settles lore gaps (owners, capitals the bible leaves open) |
| Minor settlements, roads, resources, climate, culture and faith mix, outpost slots | Generated | Spot checks; overrides where it matters |
| Generated minor factions (names, houses, traits) | Generates within the bible's rules | Approves the list |
| Landmark placeholder scenes (3 stages each) | Builds low-poly placeholders | Approves silhouettes; the final art pass comes later |
| Validation, budgets, soak tests | Runs every build | Reads the report |
| Playtest feel (distances, chokepoints, start balance) | Captures and soak statistics | Plays, gives notes |

### 9.2 Blocks, roughly

Each block ends with a commit, push and report; design-heavy ones stop for approval.

| Block | Content | Blocks |
|---|---|---|
| P1 | Data model, map folders, active-map loader, region-ID raster, O(1) lookups, save schema 4 | 1 |
| P2 | Build script: SVG and JSON parsing, land, heightfield, regions, rivers, passes, roads, classification, graphs, derived data; validator; `pipeline_test` map | 2 |
| P3 | Runtime map scene: chunked GPU terrain, streaming scatter and settlements via the manifest and landmark slots, roads, rivers and Greywall rendering, strategic map and minimap from bakes, shroud texture input, debug overlay, `--map-preview` | 2 |
| P4 | Scale proof on a synthetic 600-region map: perf harness for every budget; hierarchical paths, AI time slicing, odds budget | 1–2 |
| P5 | Test map re-authored, `main.gd` made map-agnostic, tests and captures re-baselined | 1 |
| A1 | Varos world outline (all continents, coarse); **stop for approval** | 1 |
| A2–A3 | Stage A detail: regions, factions, starts, armies, placeholder rosters, validation clean, AI soak | 2 |
| A4–A6 | Twelve landmark placeholders (about four per block; can interleave with other work) | 3 |
| B | Rest of Aldryn: Frostwaste with Ghurmak, Red Peaks south, Sahren, the Black Ark (once moving landmarks exist); about 70 regions, 6 landmarks | 3–4 |
| C | Ossara: Elven Coast, Horned Sea; about 110 regions, 3 landmarks | 3–4 |
| D | Sothmire: Gnawing Coast, Jungle Heart, high-seas lanes; about 40 regions, 2 landmarks | 2 |

The pipeline is 7–8 blocks before content and Stage A is 6. Each later stage is 2–4 blocks plus your review.

---

## 10. Free tools

| Tool | License | Use | Shipped? |
|---|---|---|---|
| Godot 4.7.2 (pinned) | MIT | Build script, validator, preview, the game | Yes (as today) |
| Inkscape | GPL-2.0-or-later | Optional: editing `sketch.svg` | No (authoring only) |
| Krita or GIMP | GPL-3.0 | Optional: painting override layers | No (authoring only) |

No new runtime dependency, no paid tool, no network. Terrain3D (MIT, a GDExtension terrain addon) was considered; see Q2.

---

## 11. Decisions (owner, 2026-10-02)

Every question raised in this design, with the decision. Q4, Q6, Q7, Q8 and Q9 were decided explicitly; the rest adopt the recommendation.

| # | Question | Decision |
|---|---|---|
| Q1 | Authoring format | **Hybrid:** SVG geometry (Inkscape-editable) + JSON attributes + optional painted overrides (section 2) |
| Q2 | Terrain technology | **Our own GPU-displaced chunk grid**, no Terrain3D dependency; revisit only if the scale proof misses its GPU budget |
| Q3 | World size and density | **Varos 4,096 × 2,560 m**; region spacing about 90 m in lowlands, 140–180 m in sparse lands; about 320 regions in V1; budgets for 600 |
| Q4 | Gameplay of minor settlements | **Approved as recommended:** they belong to their region's owner, fall with its major settlement (no separate sieges), and give a small bonus by type (village: food and population; castle: defence and garrison; town: income) |
| Q5 | Major settlement types | **City or fortress only** on Varos; the test map keeps its village and town majors |
| Q6 | Rivers | **Approved: crossable only at fords and bridges.** TW:WH3 parity on this is **unverified**; research it during the pipeline work and record it in docs/tw-ui-parity.md |
| Q7 | Owners the world bible leaves open | **Approved:** Crownhaven = House Corvinus; Highbloom = House Verrin (Roman minor); Oldstone Citadel = Port Dallow; Silverfall's tyrants = the Lannetids |
| Q8 | Orcs in Stage A | **Approved:** only minor orc tribes (Snowtusk, Grimhollow) beyond the Wall; the Ironjaw Horde and Ghurmak come in Stage B (Ghurmak's holder: the Ironjaw Horde) |
| Q9 | The Black Ark | **Approved: Stage B**, once the moving-landmark entity exists |
| Q10 | Land outside a built stage | Dark "unexplored" edge, impassable; sea lanes stop at the edge; blank parchment on the strategic map |
| Q11 | Saves across map versions | Incompatible during development (clear refusal message); after the V1 content freeze, keep IDs and ship migrations |
| Q12 | Committed vs cached outputs | Commit gameplay bakes (movement, region raster, graphs, derived data); cache render bakes locally by the sources' hash |
| Q13 | Rosters for non-human AI factions in Stage A | Placeholder rosters as data (existing unit stats re-tagged per race, racial names, shared placeholder model) until each race's roster block |
| Q14 | AI cost at scale | Same rules for all; distant peaceful factions replan strategic goals every few turns; a per-turn odds budget; factions processed across frames |
| Q15 | Stage A boundaries and list | As in section 8; the world-outline block (A1) refines the exact lines for approval |
| Q16 | The Wardens of the Greywall's AI | An independent major faction in Stage A; Greywall duties come with the Greywall mechanics |
| Q17 | Unsettled wilderness regions | Allowed (mountain and forest regions without a major, for passes and outposts); every region with a major settlement has an owner at start |
