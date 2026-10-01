# Visual checkpoint validation

## Executed

- Godot 4.7.2 imported the project and its texture/model assets.
- Native Vulkan / Forward+ rendering produced overview and city close-up screenshots, inspected during development.
- Automated checks cycle city and road stages, verify routes and traffic counts, verify dry city / submerged sea terrain, exercise zoom input, invoke the pause button, and select the fortress.
- Static architecture is batched by material; city and road batches remain separate so changing their stages does not leave old geometry behind.
- Six caravans follow ground-sampled road curves. Four ships follow coastal routes. These are visual traffic systems, not economy simulation.

## Observed performance

**Different machine — not this development PC.** The numbers in this paragraph were measured by the previous agent in its own environment (NVIDIA GeForce RTX 4050 Laptop GPU, driver 555.97), not on the development PC recorded in constitution.md. At 1600×1000, the developed overview and city close-up settled around 36–38 FPS in sampled runs, after initial scene construction and shader warm-up. Results are not a broad benchmark or a guarantee for other machines. Default launcher window is 1440×900.

On the development PC (Ryzen 7 5700X3D, RTX 4060 8 GB, driver 591.86), measured with `--capture` on the overview at the default 1440×900 window, reading the FPS the capture log prints at frame 180. The display runs at 60 Hz.

| RAM configuration | Runs | Frame-180 FPS | Draw calls |
|---|---|---|---|
| 16 GB, 1 stick, 2133 MT/s | 2 (before and after the manifest refactor) | 50, 51 | 690 |
| 32 GB, 2 × 16 GB dual channel, 3200 MT/s (XMP), non-optimal-slot BIOS warning accepted | 5 | 49, 51, 50, 51, 50 | 690 |

The RAM upgrade made no measurable difference. GPU utilization sampled with nvidia-smi during a run was 98–100%, so this scene is GPU-bound and memory bandwidth does not limit it. Frame-60 readings vary widely (17–49 FPS) because of shader warm-up and are not comparable. These are spot readings, not a benchmark. A 60-second run with normal settings held 50–51 FPS and 19.3–19.9 ms GPU throughout, so the frame-180 reading is representative of steady state.

## GPU profile (overview, not yet optimized)

Method: a fresh game process per configuration at the overview camera, 1440×900, vsync off. Each disables one feature right after the scene loads, settles for 10 s, then averages Godot's measured viewport GPU time over 5 s. Two rounds; the rounds agreed within 0.2 ms. Godot's per-pass visual-profiler data is not exposed to scripts, so costs are attributed by removal. Costs overlap (tree shadows are part of both "trees" and "sun shadows"), so the savings do not add up to the total.

| Configuration | GPU ms | Saved vs baseline | FPS (vsync off) |
|---|---|---|---|
| Baseline (as shipped: 4 shadow splits to 250 m, MSAA 4x, SSAO, fog) | 19.5 | — | 50 |
| Trees hidden | 2.2 | **17.3** | ~400 |
| Sun shadows off | 13.7 | **5.8** | 72 |
| MSAA off (project setting `msaa_3d=2` is 4x) | 13.9 | **5.6** | 70 |
| Tree shadow casting off only | 14.1 | 5.4 | 70 |
| SSAO off | 16.7 | 2.8 | 59 |
| Terrain hidden | 18.4 | 1.0 | 54 |
| Sea (water shader), batched buildings, fog | 19.5–19.7 | ~0 | 50 |

Top three GPU costs:

1. **Trees (~89% of the frame).** 856 fir instances of the Poly Haven fir model at about 14,300 triangles each, or 12.2 million triangles, with no LOD. They are drawn in the main pass and again in each of the four shadow cascades.
2. **Directional shadows (5.8 ms).** Almost all of it (5.4 ms) is the trees casting into four cascades out to 250 m.
3. **MSAA 4x (5.6 ms).** It multiplies the cost of the dense foliage geometry.

Water, fog, and the batched buildings are negligible. Likely fixes for later (not applied): low-poly placeholder trees or LODs/impostors, fewer shadow splits or a shorter shadow distance, and MSAA 2x or TAA/FXAA.

## Low-poly trees and MSAA 2x (2026-09-30)

Changes: the forest uses three Quaternius Ultimate Fantasy RTS trees (345–552 triangles each, flat colors) via the manifest ID `nature.tree`, instead of the Poly Haven fir (~14,300 triangles). Coastal rocks use three pack rocks via `nature.rock`, drawn as three multimeshes instead of 100 separate sphere meshes; placement and random draws are unchanged, so the rest of the layout is identical. `msaa_3d` changed from 2 (4x) to 1 (true 2x). Shadows are unchanged (4 splits to 250 m): with the new trees, 150 m saved only 0.08 ms, so it was not needed.

Same method and machine as the GPU profile above (RTX 4060, driver 591.86; fresh process per configuration, overview camera, 1440×900, vsync off, 10 s settle, 5 s average of Godot's measured viewport GPU time, 2 rounds). Both "before" rows were re-measured in this session on the old code.

| Configuration | GPU ms (r1 / r2) | FPS (vsync off) | Draw calls |
|---|---|---|---|
| Before, as shipped (fir, MSAA 4x) | 19.39 / 19.45 | 51 | 690 |
| Before, MSAA 2x only | 16.57 / 16.57 | 59 | 690 |
| Before, MSAA 2x + shadows to 150 m | 13.86 / 13.94 | 70–71 | 489 |
| **After, as shipped (pack trees and rocks, MSAA 2x)** | **2.13 / 2.13** | **414** | 696 |
| After + shadows to 150 m (not applied) | 2.06 / 2.05 | 427 | 493 |
| After, trees hidden | 1.99 / 1.96 | 439–445 | 669 |

With vsync on (normal play), the `--capture --self-test` overview reads 60 FPS at frame 180, the display's refresh cap. Trees now cost about 0.15 ms. Self-test and GUT tests pass.

## Farmland and Goldspire Rock (2026-09-30)

Farmland near Willowmere is now one terrain-draped patchwork (`terrain.farmland`) instead of twelve flat squares; before/after from the same camera: `captures/farmland_before.png`, `captures/farmland_after.png` (local captures, not committed).

Goldspire Rock (`goldspire_rock`, docs/world.md landmark #2) is the first landmark in the manifest's landmark slot. It stands in the sea at world (44, 36.5) on the map's coastline, about 28 × 21 m and 21 m to the summit plateau, with the summit tower at about 5 m (the top of the campaign tower range). The coastal ship loop was narrowed so ships stay west of it. Keys: **G** jumps the camera to it, **F6** cycles its stage (debug). Captures: `--capture --goldspire-stage=N` (overview) and `--capture --goldspire --goldspire-stage=N` (close), saved as `captures/overview_goldspire_stage_N.png` and `captures/goldspire_stage_N.png`.

GPU time, same method as the profiles above (RTX 4060, 1440×900, vsync off, fresh process per configuration, 10 s settle then 5 s average, 2 rounds). Goldspire starts at stage 2. "Zoomed" is the G bookmark view.

| Configuration | GPU ms (r1 / r2) | FPS (vsync off) | Draw calls |
|---|---|---|---|
| Previous checkpoint overview (no farmland or Goldspire) | 2.13 / 2.13 | 414 | 696 |
| Overview, Goldspire stage 1 | 2.17 / 2.17 | 405 | 501 |
| **Overview, as shipped (stage 2)** | **2.21 / 2.22** | **398** | 594 |
| Overview, Goldspire stage 3 | 2.30 / 2.30 | 384 | 631 |
| Zoomed on Goldspire, stage 1 | 2.01 / 2.02 | 432 | 559 |
| Zoomed on Goldspire, stage 2 | 2.06 / 2.08 | 422 | 640 |
| Zoomed on Goldspire, stage 3 | 2.18 / 2.19 | 403 | 718 |

The landmark's static pieces are batched by material inside the visual. The `--capture` runs (vsync on) all read 60 FPS at frame 180. Self-test and GUT (12 tests) pass.

Known limits: at the default overview the bottom of Goldspire's sea face sits behind the bottom bar; the summit, labels and upper cliff stay visible. The map's coast stands in for the world bible's "west coast"; there is no road to Goldspire yet.

## Unit types, campaign UI and map overlays (2026-09-30)

GUT: 30 tests pass both headless and windowed (`test_asset_manifest`, `test_goldspire_rock`, `test_unit_types`, `test_campaign_ui`, `test_world_map`): every unit type loads, builds and renders a portrait (pixel checks windowed only), the portrait cache key changes with the visual, the UI shows exactly the UiData values (fixture with distinctive numbers), End Turn advances the year and posts "Year X begins" without touching other values, and province/faction lookup and region tiling hold. `--self-test` passes and now also covers settlement selection, the army panel and End Turn.

The overview camera was reframed (target (10, 3, 21), yaw 0.08, pitch 0.85, distance 155) so Goldspire's sea face sits above the bottom panel. GPU time, same method as above (RTX 4060, 1440×900, vsync off, fresh process per configuration, 10 s settle, 5 s average, 2 rounds):

| Configuration | GPU ms (r1 / r2) | FPS (vsync off) | Draw calls |
|---|---|---|---|
| **Overview, as shipped (new framing, full UI, borders)** | **2.05 / 2.06** | 422–425 | 676 |
| Overview, UI and banners hidden | 2.03 / 2.03 | 429–431 | 478 |
| Overview, territory borders off | 2.06 / 2.06 | 422–423 | 676 |
| Previous overview framing, full UI | 2.24 / 2.24 | 394 | 754 |
| Previous overview framing, UI hidden (compare 2.21 before this work) | 2.21 / 2.21 | 399 | 556 |
| Zoomed on Goldspire (G) | 2.09 / 2.09 | 418–419 | 806 |
| Commander selected, army panel with 9 cards | 1.88 / 1.88 | 457–459 | 808 |
| Same, UI hidden | 1.84 / 1.84 | 469 | 627 |

UI cost: about 0.02–0.04 ms GPU and about 200 2D draw calls. Portraits, building thumbnails and the minimap render once (cached) and cost nothing per frame. Startup adds about 0.17 s for the territory textures and about 1 s of one-time portrait rendering (then cached on disk).

1440p: this display is 1920×1080, so a 2560×1440 window cannot be opened here. The game was rendered into an offscreen 2560×1440 viewport with the project's stretch rule (base 1600×1000, `canvas_items`, `expand`); the layout is identical to 1080p and sharper (`captures/ui_overview_1440p.png`).

## Turn loop and economy (2026-09-30)

GUT: 42 tests pass headless and windowed. `tests/test_economy.gd` covers income math against `data/economy.json` for every settlement type and level, cities out-earning fortresses and the fortress income ceiling, Goldspire out-earning a generic city of the same level (by more than 1.5× at every level), resources raising income but never changing, economic settlements growing faster than defensive ones (city/fortress, village/castle, town/castle), capacity limiting growth, income-then-expenses for every faction, a deterministic 10-turn run for a fixed seed, and the yearly chronicle. `tests/test_campaign_ui.gd` checks the UI shows real state (fixture start), the treasury breakdown, real province stats and End Turn. `--self-test` passes.

End Turn processing: 1.2–1.5 ms per turn (4 settlements, 3 factions; self-test and a 10-turn run). GPU time, same method as above: overview 2.06 / 2.06 ms, zoomed on Goldspire 2.08 / 2.09 ms, army panel 1.87–1.88 ms (one transient 2.30 ms reading in one round; two repeat rounds read 1.88 ms). Unchanged from before the economy (it runs only on End Turn).

10-turn sample run (seed 1201, placeholder numbers; treasury gold / population at the start of each year):

| Year | House Aurek | House Lannet of Silverfall | House Verrin of Highbloom |
|---|---|---|---|
| 1 | 8,450 / 19,700 | 6,000 / 12,400 | 3,000 / 2,100 |
| 2 | 8,895 / 19,838 | 6,761 / 12,575 | 3,171 / 2,118 |
| 3 | 9,340 / 19,973 | 7,522 / 12,747 | 3,342 / 2,134 |
| 4 | 9,785 / 20,105 | 8,283 / 12,918 | 3,513 / 2,151 |
| 5 | 10,230 / 20,234 | 9,044 / 13,086 | 3,684 / 2,166 |
| 6 | 10,675 / 20,360 | 9,805 / 13,252 | 3,855 / 2,181 |
| 7 | 11,120 / 20,484 | 10,566 / 13,415 | 4,026 / 2,196 |
| 8 | 11,565 / 20,604 | 11,327 / 13,576 | 4,197 / 2,209 |
| 9 | 12,010 / 20,722 | 12,088 / 13,735 | 4,368 / 2,223 |
| 10 | 12,455 / 20,836 | 12,849 / 13,891 | 4,539 / 2,236 |
| 11 | 12,900 / 20,948 | 13,610 / 14,045 | 4,710 / 2,248 |

Per-turn ledgers (year 1): Aurek income 1,791 (Goldspire 1,528, Crownwatch 263) − expenses 1,346 (army 816, buildings 530) = +445; Lannet 976 − 215 = +761; Verrin 201 − 30 = +171. Income is flat over time because nothing in the confirmed rules ties income to population, and levels do not change without construction.

## Population taxes, building effects and construction (2026-10-01)

Tests: 66/66 GUT tests pass headless and with the real renderer (portrait pixel checks included). The headless run previously hung in `test_every_unit_renders_a_portrait` (the dummy renderer never emits `frame_post_draw`); the portrait studio now skips the GPU readback when headless. Self-test passes, including a main-building upgrade at Goldspire that completes on End Turn and switches the landmark to its next stage.

GPU time, same method as above (RTX 4060, 1440×900, vsync off, 10 s settle, 5 s average, 2 rounds): overview 2.09 / 2.11 ms, army panel 1.92 / 1.87 ms, Goldspire selected with the building browser open 2.11 / 2.12 ms. Unchanged from before (economy and construction only run on End Turn or on clicks).

End Turn: 2.6–2.7 ms in the self-test; 3.26 ms average, 4.98 ms worst over the 20-turn run below (4 settlements, 3 factions, construction and placeholder AI included).

Starting incomes with population taxes (year 1; old formula in brackets): House Aurek 1,779 (1,791), of which Goldspire 1,518 (1,528) and Crownwatch 261 (263); House Lannet 879 (976); House Verrin 220 (201). Building upkeep now comes from each building level, so expenses fell (Aurek 340 vs 530 for buildings).

20-turn sample run (seed 1201, placeholder numbers; treasury gold / population / settlement levels at the start of each year). House Aurek is the player and builds nothing in this run; Lannet and Verrin are driven by the placeholder AI.

| Year | House Aurek (Crownwatch, Goldspire) | House Lannet (Greyhaven) | House Verrin (Willowmere) |
|---|---|---|---|
| 1 | 8450 / 19700 / L2, L2 | 6000 / 12400 / L2 | 3000 / 2100 / L1 |
| 2 | 9073 / 19854 / L2, L2 | 6274 / 12635 / L2 | 2600 / 2119 / L1 |
| 3 | 9701 / 20005 / L2, L2 | 6004 / 12871 / L2 | 2451 / 2175 / L2 |
| 4 | 10335 / 20152 / L2, L2 | 6760 / 13105 / L2 | 2010 / 2247 / L2 |
| 5 | 10974 / 20296 / L2, L2 | 6423 / 13339 / L2 | 2261 / 2324 / L2 |
| 6 | 11618 / 20435 / L2, L2 | 7220 / 13570 / L2 | 1731 / 2400 / L2 |
| 7 | 12267 / 20572 / L2, L2 | 4423 / 13804 / L2 | 2003 / 2495 / L2 |
| 8 | 12921 / 20704 / L2, L2 | 5331 / 14035 / L2 | 2273 / 2591 / L2 |
| 9 | 13580 / 20833 / L2, L2 | 4646 / 14406 / L3 | 2545 / 2689 / L2 |
| 10 | 14243 / 20959 / L2, L2 | 5715 / 14778 / L3 | 2820 / 2788 / L2 |
| 11 | 14911 / 21081 / L2, L2 | 4795 / 15172 / L3 | 1698 / 2887 / L2 |
| 12 | 15583 / 21200 / L2, L2 | 5876 / 15567 / L3 | 1978 / 2988 / L2 |
| 13 | 16259 / 21316 / L2, L2 | 4769 / 15967 / L3 | 1811 / 3109 / L3 |
| 14 | 16939 / 21429 / L2, L2 | 5908 / 16367 / L3 | 2176 / 3232 / L3 |
| 15 | 17624 / 21538 / L2, L2 | 4558 / 16777 / L3 | 1559 / 3358 / L3 |
| 16 | 18312 / 21644 / L2, L2 | 5861 / 17187 / L3 | 1946 / 3485 / L3 |
| 17 | 19004 / 21747 / L2, L2 | 7177 / 17611 / L3 | 2336 / 3614 / L3 |
| 18 | 19699 / 21847 / L2, L2 | 8592 / 18034 / L3 | 2755 / 3744 / L3 |
| 19 | 20399 / 21944 / L2, L2 | 10020 / 18456 / L3 | 1777 / 3875 / L3 |
| 20 | 21102 / 22039 / L2, L2 | 11461 / 18876 / L3 | 2203 / 4007 / L3 |
| 21 | 21808 / 22130 / L2, L2 | 12916 / 19294 / L3 | 2632 / 4146 / L3 |

AI construction in that run: Lannet built a mine (to level 3), upgraded its market twice, raised Greyhaven to Chartered City (level 3, year 8), then Wards and a Merchant Harbour; Verrin raised Willowmere to Market Village (year 2) and Market Town (year 12), and built Houses, Granaries/Estates and a mine. Every AI build kept the 1,500 gold reserve, and Willowmere's buildings never exceeded its settlement level.

## Coastal ports and army movement (2026-10-01)

Tests: 79/79 GUT tests pass headless and with the real renderer. Self-test passes, now including a path preview, a blocked order onto Greyhaven ("Battles not implemented yet", no points spent), a multi-turn order that continues on End Turn, cancel, and garrisoning Crownwatch (the army's state is restored before the capture).

GPU time, same method as above (RTX 4060, 1440×900, vsync off, 10 s settle, 5 s average, 2 rounds): overview 2.04 / 2.09 ms (unchanged); army selected with a 3-turn path preview, reachable area and turn markers (camera at -58,-12, 112 m) 2.21 / 2.42 ms.

CPU: End Turn 2.7 ms in the self-test; 2.94 ms average, 3.48 ms worst over 20 turns while the army marched a 6-turn order across the Greyspine Pass. A path plan takes about 1 ms (A* on the 140×102 grid); the reachable area about 13–22 ms, computed only when the army is selected or the state changes.

Movement grid: 140×102 cells of 2 m (open 5,695, forest 1,391, hills 1,299, pass 140, mountain 3,340, water 2,365, settlement 50), baked from the map by `--bake-movement-grid`. The reachable area matches the planner exactly in a 415-cell cross-check.

Screenshots (generated, in `captures/`): `move_preview.png` (3-turn path with turn markers 1-2-3, routed around foreign Willowmere), `move_reachable.png` (reachable area of the selected army; the hole is foreign Greyhaven), `move_garrison.png` (the host garrisoned in Crownwatch).

## Remaining limitations

- Artwork is a prototype and has not been approved against the desired 2016 Total War campaign-map benchmark.
- Camera, village, city, and character views are functional; there is no playable strategy campaign yet.
- Checks exercised controls programmatically. A complete manual mouse/keyboard walkthrough on the user's desktop is still needed.
- Godot reports inability to read the Windows root certificate store in this sandbox. The game makes no network requests and rendering/capture complete successfully. Launcher redirects runtime data into the project-local .local folder to avoid external filesystem writes.
- Initial startup constructs geometry and may briefly pause. Development changes are not saved between sessions.

Screenshots in captures are generated by the running game, not concept art.
