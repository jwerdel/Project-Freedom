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

Goldspire Rock (`goldspire_rock`, docs/archive/world-v1.md landmark #2) is the first landmark in the manifest's landmark slot. It stands in the sea at world (44, 36.5) on the map's coastline, about 28 × 21 m and 21 m to the summit plateau, with the summit tower at about 5 m (the top of the campaign tower range). The coastal ship loop was narrowed so ships stay west of it. Keys: **G** jumps the camera to it, **F6** cycles its stage (debug). Captures: `--capture --goldspire-stage=N` (overview) and `--capture --goldspire --goldspire-stage=N` (close), saved as `captures/overview_goldspire_stage_N.png` and `captures/goldspire_stage_N.png`.

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

## Recruitment, new armies and rival armies (2026-10-01)

Tests: 94/94 GUT tests pass headless and with the real renderer. Self-test passes, now also opening the recruitment panel at Crownwatch, queueing a levy (gold and men taken) and cancelling it (both refunded).

GPU time, same method as above (RTX 4060, 1440×900, vsync off, 10 s settle, 5 s average, 2 rounds): overview with all three armies visible 2.05 / 2.06 ms (unchanged; two more commander figures).

End Turn: 2.5 ms in the self-test; 2.38 ms average, 3.22 ms worst over the 20-turn run below (3 armies, AI construction and recruitment, replenishment).

20-turn sample run (seed 1201, placeholder numbers; treasury gold / population / armies / units at the start of each year; units exclude generals). House Aurek is the player and gives no orders; Lannet and Verrin are driven by the placeholder AI, which recruited peasant levies (the only unit their settlements unlock) into their capital garrisons: Lannet up to its 6-unit target by year 4, Verrin to 4 by year 4 and a 5th in year 17, held back by its net-income guard. Aurek's host replenishes at a gold cost while it stands in Lannet's land.

| Year | House Aurek | House Lannet | House Verrin |
|---|---|---|---|
| 1 | 8450 / 19700 / 1 / 8 | 6000 / 12400 / 1 / 4 | 3000 / 2100 / 1 / 2 |
| 2 | 9064 / 19854 / 1 / 8 | 5694 / 12475 / 1 / 4 | 2188 / 1959 / 1 / 2 |
| 3 | 9704 / 20005 / 1 / 8 | 4840 / 12552 / 1 / 5 | 1623 / 1856 / 1 / 3 |
| 4 | 10362 / 20152 / 1 / 8 | 5222 / 12789 / 1 / 6 | 1676 / 1924 / 1 / 4 |
| 5 | 11043 / 20296 / 1 / 8 | 4474 / 13025 / 1 / 6 | 1685 / 1993 / 1 / 4 |
| 6 | 11738 / 20435 / 1 / 8 | 4861 / 13260 / 1 / 6 | 1695 / 2064 / 1 / 4 |
| 7 | 12438 / 20572 / 1 / 8 | 1654 / 13497 / 1 / 6 | 1707 / 2135 / 1 / 4 |
| 8 | 13158 / 20704 / 1 / 8 | 2151 / 13731 / 1 / 6 | 1721 / 2206 / 1 / 4 |
| 9 | 13883 / 20833 / 1 / 8 | 2655 / 14100 / 1 / 6 | 1737 / 2279 / 1 / 4 |
| 10 | 14636 / 20959 / 1 / 8 | 1713 / 14471 / 1 / 6 | 1755 / 2351 / 1 / 4 |
| 11 | 15394 / 21081 / 1 / 8 | 2382 / 14844 / 1 / 6 | 1775 / 2424 / 1 / 4 |
| 12 | 16156 / 21200 / 1 / 8 | 3062 / 15238 / 1 / 6 | 1797 / 2497 / 1 / 4 |
| 13 | 16922 / 21316 / 1 / 8 | 1743 / 15633 / 1 / 6 | 1821 / 2571 / 1 / 4 |
| 14 | 17692 / 21429 / 1 / 8 | 2436 / 16030 / 1 / 6 | 1847 / 2644 / 1 / 4 |
| 15 | 18467 / 21538 / 1 / 8 | 3140 / 16431 / 1 / 6 | 1875 / 2717 / 1 / 4 |
| 16 | 19245 / 21644 / 1 / 8 | 1690 / 16832 / 1 / 6 | 1905 / 2790 / 1 / 4 |
| 17 | 20027 / 21747 / 1 / 8 | 2452 / 17233 / 1 / 6 | 1937 / 2862 / 1 / 4 |
| 18 | 20812 / 21847 / 1 / 8 | 3226 / 17643 / 1 / 6 | 1721 / 2774 / 1 / 4 |
| 19 | 21602 / 21944 / 1 / 8 | 1655 / 18052 / 1 / 6 | 1752 / 2846 / 1 / 5 |
| 20 | 22395 / 22039 / 1 / 8 | 2597 / 18459 / 1 / 6 | 1749 / 2918 / 1 / 5 |
| 21 | 23191 / 22130 / 1 / 8 | 3552 / 18880 / 1 / 6 | 1748 / 2989 / 1 / 5 |

Screenshots (generated, in `captures/`): `recruit_panel.png` (recruitment at Goldspire, locked units with their building), `recruit_queue.png` (two queued recruits on the army panel), `rival_army.png` (the Highbloom Levy garrisoned in Willowmere, green banner).

## Battle simulation and Monte Carlo harness (2026-10-01)

`scripts/battle_harness.gd` (headless), 500 seeded battles per case, 5 lanes, debug editor build. Targets and tuned numbers: docs/battle-design.md sections 12 and 15. The GUT subset (`tests/test_battle_sim.gd`) runs the same seeds and reproduces this table.

| # | Case | Target | Actual |
|---|---|---|---|
| 1 | mirror | 45-55% | 52.4% |
| 2 | good vs bad | 75-92% | 77.2% |
| 3 | spears hold | 80-95% | 92.6% |
| 4 | cavalry charges | 85-97% | 95.4% |
| 5 | target has no reserve | 70-90% | 84.6% |
| 5 | target keeps a cavalry reserve | 40-60% | 58.0% |
| 5 | target screens both outer lanes (reference for the flank gap) | (reference) | 70.4% |
| 6 | holding the pass | 50-95% | 93.8% |
| 6 | same armies in the open | <= 15% | 10.2% |
| 7 | heavy infantry / levies kills per volley | <= 0.50 | 0.29 (4.40 vs 15.39) |
| 8 | fresh walls | 75-92% | 78.4% |
| 8 | after 4 siege turns | <= 60% | 15.8% |
| 9 | rank 5 vs 1 | 55-65% | 59.6% |
| 10 | 70/85/100/115/130% men | rising | 1% 10% 46% 84% 98% |
| 11 | same seed, same result and report | identical | identical |
| 12 | ms per battle (10 v 10 units, debug build) | < 10.0 ms | 3.07 ms |
| 13 | 3 lanes: scenarios 2-6 meet targets (informational) | (info) | some miss |
| 13 | 5 lanes: scenarios 2-6 meet targets | all pass | all pass |
| 13 | flank gap (unscreened - screened) | 5 lanes > 3 lanes | 14% vs -13% |

Speed: 3.07 ms per 10-v-10 battle in the debug editor build (target under 10 ms; re-measure against under 2 ms once a release build exists).

## Battles in the campaign (2026-10-01)

Tests: 129/129 GUT tests pass headless and with the real renderer (including `tests/test_battles.gd`: war declaration, garrisons, reinforcements, walls, casualties, experience, movement cost, destroyed units and armies, capture, retreat, generals and captains, sieges and surrender, withdrawal, report summary, determinism). Self-test passes; ordering onto an enemy settlement opens the war confirmation.

GPU time, same method as above (RTX 4060, 1440×900, vsync off, 10 s settle, 5 s average, 2 rounds): overview 2.06 / 2.07 ms; pre-battle panel open over Greyhaven 2.26 / 2.27 ms.

CPU: one quick-resolved battle (Aurek host against Greyhaven's garrison and the Silverfall Guard behind walls) 4.7-5.5 ms including the aftermath; opening the pre-battle panel 160-180 ms (50 seeded runs for the balance-of-power bar; cache it per panel or cut to 25 runs if it ever feels slow). End Turn 2.8 ms in the self-test.

Screenshots (generated, in `captures/`): `battle_prebattle.png` (siege assault on Greyhaven: both armies, garrison, walls, balance of power 12%), `battle_report.png` (victory at Willowmere: headline, why you won, key numbers, units), `battle_captured.png` (Willowmere under House Aurek, territory recolored, the host garrisoned).

## Deployment screen (2026-10-01)

Deploy on the pre-battle panel opens a full-screen deployment view. The tabletop (`battle.tabletop`) is built from the sampled battlefield: terrain tiles, trees on forest cells, walls and towers for sieges. Both sides stand in their slots with the existing unit figures: idle sway, and a fluttering banner on the general. Layout is 5 lanes × front/back + reserve + general's row per side.

- Placement: click a card or a placed unit, then a slot; or drag a card onto the board. Lane capacity and pass limits are checked with messages ("The pass holds only 1 unit per line", "Left front line is full (2 units in forest)", impassable lanes).
- Orders: Hold, Aggressive, Flank left/right, Protect (then click the unit to shield) and Reserve. Each order shows as a letter on the card and on the board. Protect and Flank draw arrows in both views.
- Templates and info: template buttons quick-fill the layout. Enemy units in forest, reserve or a fogged back line show as unknown. Lane terrain and weather are listed.
- Balance of power: recomputed on "Update odds" or 1 s after the last change. It runs the same 50 seeded runs as the pre-battle panel, about 170 ms; this screen's run was not timed separately.
- Buttons: 3D/2D toggle, Reset (the faction's default), Back to campaign (back to the pre-battle panel, nothing spent), Fight (the same flow as Quick Resolve, with the player's deployment).

While the screen is open the map's 3D is switched off, since the opaque screen covers it.

Tests: 134/134 GUT tests pass headless. The self-test passes and now opens the screen, applies a template, gives Reserve and Flank orders, toggles to 2D, updates the odds and goes Back with no movement spent.

GPU time, same method as above (RTX 4060, 1440×900, vsync off, 10 s settle, 5 s average, 2 rounds; root viewport plus the tabletop SubViewport):

| View | GPU ms |
|---|---|
| Deployment, 3D tabletop | 1.01 / 1.07 |
| Deployment, 2D board | 0.26 / 0.26 |

Screenshots (generated, in `captures/`):
- `deploy_3d.png`: siege assault on Greyhaven, faction default layout.
- `deploy_orders.png`: heavy infantry protecting archers, cavalry flanking right, with arrows.
- `deploy_2d.png`: the same orders on the 2D board.

## Full battle report and replay (2026-10-01)

The report window (the same window for Fight and Quick Resolve) shows:
- the headline
- "why you won/lost" and the key numbers
- a top-down 2D replay of unit blocks per tick: your side at the bottom, block height by men left, routed units faded, destroyed ones crossed out, walls and gates drawn for sieges
- a scrubber with play/pause, and timeline events as markers on it (green helped you, red helped them); clicking a marker jumps to it
- unit tables for both sides
- the full timeline, collapsed by default. Each event is a plain sentence, for example "The enemy Peasant Levy (left) charges your Swordsmen (left)." Clicking one jumps the replay to its tick and highlights the units involved.

The simulation now records the deployment as replay frame 0 (frames are ticks + 1) and returns a roster that maps replay columns to units.

One fix: a deployment now keeps its template's unit order, which is also the simulation's order. Before, the player's units went back to roster order, so an unchanged template could fight slightly differently from the default.

Tests: 141/141 GUT tests pass headless. The new `tests/test_deployment.gd` covers:
- impassable lanes, pass limits and lane capacity per terrain, with refused moves leaving the unit unchanged
- every template legal on four terrains, both roles and three army sizes
- orders and the general's lane saved into the battle setup, with the enemy keeping its default
- a deployment matching a template gives the same result as that template: the faction default through Quick Resolve, and all five templates at the simulation
- replay frames match the simulation: starting and final men, and destroyed and routed states at their event ticks
- the report carries the timeline, roster, enemy table and walls
- Quick Resolve gets the full report

The seed tests from Phase A (`tests/test_seeds.gd`) cover different seeds per new campaign, exact reproduction, and two battles in one year differing.

The self-test passes. It now also opens the full report from a pure simulation of the deployment, checks the frame count and the collapsed timeline, and clicks an event to check the jump and highlight. The overview capture is unchanged.

GPU time, same method as above (RTX 4060, 1440×900, vsync off, 10 s settle, 5 s average, 2 rounds):

| View | GPU ms |
|---|---|
| Deployment, 3D tabletop | 1.01 / 1.07 |
| Deployment, 2D board | 0.26 / 0.26 |
| Report window over the map (after a battle at Greyhaven) | 1.99 / 1.99 |

Screenshots (generated, in `captures/`):
- `deploy_3d.png`
- `deploy_orders.png` (Protect and Flank arrows)
- `deploy_2d.png`
- `battle_report_replay.png` (Greyhaven siege, replay at tick 6 of 9 with the event's unit highlighted)

## Save/load, main menu and pause menu (2026-10-01)

**Saves** (`core/save_system.gd`) are one JSON file per save under `user://saves`, with a schema version and a migration hook. The full campaign state is `GameState.to_dict()`: settlements, buildings and construction, armies and their orders and queues, wars, treasuries, year and turn, chronicle, last ledgers, campaign seed and battle counter. There is no separate RNG state, because every random draw is seeded from the campaign seed, year and battle counter.

`core/save_codec.gd` keeps the state exact:
- int and float stay distinct (Godot's JSON parser returns every number as a float)
- dictionary order is kept
- floats are bit-exact. Godot's JSON parser is not correctly rounded, so a float that would not read back exactly is stored as its 64-bit pattern.

Writes go to a temp file that is renamed over the old one. Incompatible, damaged or foreign files fail with a message and never produce a partial state.

**Autosave and quicksave:** autosave runs at the start of End Turn into three rotating slots. Quicksave and quickload are Ctrl+S and Ctrl+L. Each save stores a JPEG thumbnail of the map (320×200, about 20 KB, drawn without the interface) plus faction, year and real date. The thumbnail is encoded on a worker thread, and the newest view also becomes the main menu backdrop.

**Menus:**
- Main menu on launch: Continue, New Campaign (as House Aurek; faction choice comes with the V1 map), Load, Settings, Quit.
- Pause menu: Esc with no panel open; Esc still closes panels first. It has Resume, Save (named), Load, Settings, Exit to main menu and Quit. Exiting or quitting with unsaved progress asks first, with Save and continue, Continue without saving, or Cancel.
- Load screen: thumbnail, name, faction, year and date; delete asks for confirmation; damaged files list as damaged.
- Settings (placeholder): resolution, fullscreen, UI scale, and debug keys (on by default). The debug keys F5–F7, L and Space are listed in the README.

Tests: 152/152 GUT tests pass headless. The new `tests/test_saves.gd` has 11 tests:
- codec types, order and bit-exact floats
- a full round trip gives the identical state hash
- 10 turns played straight vs. 5 turns, save, load, 5 more: identical state and identical battle results. The script includes construction, recruitment, two battles, a multi-turn march, and a siege active at the save point.
- construction, recruitment queues, multi-turn orders and an active siege survive a save and keep running identically for 3 more turns
- autosave rotation
- newer, older, damaged and foreign files fail with messages
- the migration hook
- an interrupted save leaves the old file byte-identical and loadable
- save names, listing and delete
- the load screen's delete confirmation and Load button

Self-test passes, now including: autosave on End Turn, a save/load round trip, the Esc order, and pause-menu save and the unsaved-progress warning. The full menu → load → campaign path was run as a capture (`--menu --menu-load=…`): year 4, treasury, events and the Goldspire stage were all restored.

Timings (RTX 4060, real renderer, campaign at year 13 after 12 End Turns; 5 runs each, 2 rounds):

| Measure | Result |
|---|---|
| Save (JSON written, thumbnail queued) | 7.3–9.3 ms |
| Thumbnail grab (one extra frame without the interface) | 13–14 ms |
| Background JPEG encoding | about 16 ms, off the main thread |
| End Turn including autosave and thumbnail | 40–50 ms (End Turn alone 2–5 ms) |
| Load from file (parse, decode, rebuild state) | 0.9–6.4 ms |
| Load into a playable campaign (menu → map scene rebuilt from the save) | 2.69–2.70 s, almost all of it building the 3D map scene |

File sizes:

| Save | Size |
|---|---|
| Year-1 start | 3.9 KB |
| After a battle | 7.5 KB |
| Year 13 | 13.6 KB |
| Thumbnail | about 20 KB |
| Menu backdrop | 960×600 JPEG |

Screenshots (generated, in `captures/`):
- `main_menu.png`
- `load_screen.png` (three saves with thumbnails)
- `pause_menu.png`
- `loaded_goldspire.png` (a save loaded through the menu)

## Campaign AI (2026-10-01)

Design: `docs/ai-design.md`. Code: `core/ai.gd`. Weights: `data/ai.json`. Faction traits: `data/factions.json`, from docs/archive/world-v1.md:
- Aurek: income-focused, cruel when crossed
- Verrin: generous, income-focused, levy-heavy
- Lannet: none listed

End Turn runs the yearly processing, then the AI phase, where every AI faction acts with full movement through the player's own functions. AI attacks on the player wait in `state.pending_battles`, and the pre-battle panel opens with the player defending (no Close). The camera follows AI armies that move near the player's lands; Space or Esc skips, and Settings has a "Follow AI armies" switch. Wars, battles and captures between AI factions appear in Event Messages ("Wars and Battles") and the chronicle. Besieged settlements show a "BESIEGED n/m" tag on the map. The camera is saved with each save (save schema 2, with a migration from schema 1).

**Main data values (placeholders):**

| Area | Values |
|---|---|
| Reach | 55 m (one turn of 60 points); threat radius 70 m; strategic range 160 m |
| Odds screen | ratio ≥ 2.2 counts as sure, ≤ 0.45 as hopeless; between, 5 fast simulations, at most 1 per faction per turn, else a logistic curve (k = 3) |
| Attack | win chance ≥ 0.65; assault walls only at ≥ 0.8, else besiege when the no-walls ratio ≥ 0.9; march on targets at force ratio ≥ 1.2 |
| Defence | threatened at threat > 0.8 × defence; help only if it reaches 0.75 of the threat; flee when facing more than 1.6 × own power; withdraw from field battles below 0.25 |
| War | chance 0.12 × aggression × weakness; at most 2 wars at once; field force counted at 0.8 |
| Economy | reserve 1,200 gold × personality; net income never below 50 after new upkeep; 1 build per turn; separate weights for safe and threatened settlements |
| Recruitment | composition spear 0.3, infantry 0.25, missile 0.25, cavalry 0.1, levy 0.1 (Verrin levy-heavy); 10 units per army, up to the cap when treasury > 3 × reserve; 2 recruits per army per turn; emergency floor 0.25 × reserve with no army or under 6 units |
| Personality | expansionist aggression × 2.5; cruel × 1.5; treacherous × 1.3 and opportunist; income-focused × 0.8, reserve × 1.6; generous and kind × 0.3; passive × 0.15 |

**Fixes found along the way:**
- The player's Besiege did not march to the settlement first, so the siege lifted at the next End Turn. Besiege now moves along the approach, as Quick Resolve does.
- The chronicle's yearly ledger kept listing eliminated factions, even naming one "the fullest treasury". Factions gone from the map are now skipped.
- GUT exits 0 when a test file fails to parse; it silently skipped `test_recruitment.gd` once. Test runs now check the log for parse errors.
- `Movement.plan` re-marked every foreign army's cells on the A* grid for each path, costing O(armies) per plan. The blocked cells now stay applied until armies move or owners change: plans are 3–8× faster, with identical paths.

**Tests:** 162/162 GUT tests pass (13 new in `tests/test_ai.gd`, 2 new in `tests/test_saves.gd`). `tests/test_ai.gd` covers:
- exact gold accounting over 25 all-AI turns
- no debt from spending, the army and unit caps, movement within allowance, and no recruiting or building into negative income
- captain-led armies stay put
- defending a threatened settlement
- refusing bad odds (it falls back instead)
- besieging walls it cannot storm and assaulting when it can
- attacks on a human player waiting for the player, the panel as defender, and pending attacks surviving a save or being dropped when stale
- a hopeless AI army withdrawing when the player attacks
- recruiting a unit mix
- personality: over 6 seeded 25-turn campaigns, expansionist factions started 4 wars and passive or kind factions started 0
- determinism

The placeholder AI stubs and their 5 tests were removed. The self-test passes.

**Soak test** (`scripts/ai_soak.gd`): 50 turns, all factions AI, 8 seeds, world.md traits. The first seed was run twice and gave identical results.

| Seed | Wars | Battles | Sieges | Captures | Withdrawals | Eliminated | Final settlements (Aurek / Lannet / Verrin) | Final treasury (Aurek / Lannet / Verrin) |
|---|---|---|---|---|---|---|---|---|
| 11 | 2 | 2 | 2 | 3 | 2 | Lannet, Verrin | 4 / 0 / 0 | 5,643 / −1,036 / 3,156 |
| 22 | 2 | 3 | 2 | 3 | 0 | Lannet, Verrin | 4 / 0 / 0 | 8,633 / 2,799 / 3,446 |
| 33 | 2 | 4 | 4 | 7 | 0 | Verrin | 2 / 2 / 0 | 5,707 / 684 / 3,077 |
| 44 | 2 | 3 | 1 | 2 | 0 | Verrin | 2 / 2 / 0 | 2,651 / 2,055 / 3,489 |
| 55 | 1 | 1 | 0 | 1 | 0 | Verrin | 3 / 1 / 0 | 2,309 / 4,590 / 3,116 |
| 66 | 2 | 3 | 1 | 3 | 0 | Verrin | 1 / 3 / 0 | 746 / 2,835 / 3,446 |
| 77 | 2 | 2 | 1 | 2 | 0 | Verrin | 2 / 2 / 0 | 2,046 / 2,696 / 3,319 |
| 88 | 2 | 2 | 2 | 3 | 1 | Lannet, Verrin | 4 / 0 / 0 | 6,898 / −6,024 / 3,237 |

Armies at the end, Aurek / Lannet:

| Seed | Aurek | Lannet |
|---|---|---|
| 11 | 2 armies, 20 units | 1 army, 10 units |
| 22 | 2, 37 | 0, 0 |
| 33 | 2, 26 | 2, 0 |
| 44 | 1, 8 | 2, 26 |
| 55 | 2, 20 | 1, 19 |
| 66 | 1, 1 | 2, 24 |
| 77 | 2, 13 | 2, 26 |
| 88 | 2, 36 | 1, 4 |

No crashes. No stuck armies. Seed 44 reports Verrin idle for 10 turns before it fell.

An expansionist variant (all three factions expansionist) produced 1–3 wars per seed and eliminations of both other houses in 2 of 8 seeds. It is calmer than the default, because three factions building big armies deter each other (AI time per turn: average 6.5 ms, 95th percentile 15 ms).

**AI time per turn** (debug build, all factions, this map):

| Statistic | ms |
|---|---|
| Average | 7.6 |
| Median | 4.6 |
| 95th percentile | 31 |
| Max | 66 |

- The 66 ms maximum is the first turn of a session, a one-time A* grid build.
- War turns run 30–55 ms: one 5-run odds simulation, a battle, aftermath and retreat plans.
- Quiet turns run 2–7 ms.

So the 50 ms target is met except on the first turn and some battle turns.

**Scaling** (synthetic: K armies per settlement, everyone at war, median of 3 runs):

| Armies | AI phase |
|---|---|
| 9 | 14 ms |
| 17 | 19 ms |
| 30 | 38 ms |
| 59 | 67 ms |

Before the snapshot and A* changes the same runs took 21 / 39 / 98 / 294 ms. Cost is now about linear in armies.

V1 estimate (about 30 settlements, about 15 factions, 45–60 armies): about 60–90 ms for the assessment and movement part. On top of that come up to 15 odds simulations (about 15 ms each) and the battles fought that turn, so a busy war turn could reach about 150–300 ms in the debug build. Before V1, I'd recommend:
- a per-phase rather than per-faction odds budget
- a faster fast-mode simulation or a learned odds table
- spreading factions over frames

**What the AI does poorly:**
- Every seed opens the same way. House Verrin (weakest economy) falls between years 5 and 13; the seed only changes rolls, so variety is low. After that, wars stall unless one side clearly outgrows the other.
- With the world.md traits nobody is expansionist on this map, so AI-started wars are rare.
- Armies coordinate only through the reinforcement radius and gathering; the first army to arrive may besiege alone.
- Target choice weighs only weakness, not value (rich or strategic settlements).
- Reach is straight-line, so a target behind a mountain can look reachable while its approach is multi-turn (the attack is then skipped).
- Besieged AI defenders never sally, and relief comes only from armies already within reach.
- A faction whose income collapses can end with empty armies (Lannet in seed 33). A faction with no settlements left keeps its army and runs into debt (Lannet in seeds 11 and 88).
- Odds beyond one simulation per faction-turn come from a curve, which is coarse near even odds.

**Design gaps hit:**
- No peace exists, so wars never end and accumulate until diplomacy.
- No relationship web, alliances or treaties: the betrayal rules are moot, and "wariness" is AI-internal only.
- What a negative treasury does is open, so the AI only avoids it.
- Disbanding a whole army or its general is open, so empty armies and homeless armies linger.
- The maximum number of armies (placeholder 3) and one army per settlement for raising limit rich factions.
- AI factions have no fog of war, but neither does the player.
- Sack, raze and expel stay open, so captures occupy only.

**Screenshots** (generated, in `captures/`):

| File | Shows |
|---|---|
| `ai_siege.png` | House Lannet besieging Crownwatch; the banner reads "BESIEGED 0/3" |
| `ai_attacks_player.png` | "House Lannet of Silverfall attacks! Battle in the field": the pre-battle panel with the player defending (Deploy, Quick resolve, Withdraw; no Close) |
| `chronicle_ai_wars.png` | The Grey Scribes recording Lannet's war on Verrin, the Field of Willowmere and its capture |
| `ai_follow.png` | The camera following "The Silverfall Guard marches" during End Turn |

## Debt and the loss condition (2026-10-01)

Rules confirmed in constitution.md, implemented in `core/realm.gd`.

**Debt:**
- A faction may go below 0 gold down to `data/economy.json` debt.limit (placeholder −4,000).
- In debt, construction, recruitment and new armies are refused, with an "In debt" reason.
- Each End Turn in debt, every unit loses 6% of its men (placeholder; at least 1 man, never below 1).
- Below the limit, the units with the highest upkeep disband until income covers upkeep. Disbanding cannot raise the treasury, so the faction climbs back out through income.
- Buying can never create debt: every purchase still needs the gold.
- UI: the treasury turns red with an "IN DEBT" tag, and its tooltip explains the purchase ban, desertion and the limit.

**Loss condition:**
- Losing the last settlement starts a grace period of `data/campaign_rules.json` loss.grace_turns (placeholder 5).
- Retaking a settlement ends it ("Endures"). Otherwise, at 0 the faction is destroyed and its armies disband (men return to the region they stand in).
- A faction with no army left when it loses its last settlement is destroyed at once.
- UI: the grace countdown shows as a red "LANDLESS · n turns" tag in the player's resource bar, as "LANDLESS · n" over the faction's armies on the map, and as chronicle and Event Messages entries every turn for the player. Start, survival and destruction are recorded for every faction.
- The player's destruction opens the defeat screen (Load a save, or Main menu).
- Grace periods and destroyed factions are saved (save schema 3, with a 2 → 3 migration).

**AI:**
- It avoids debt: it disbands as before, and the purchase ban applies to it.
- A landless AI declares war on the owner of its best reachable settlement without a roll, attacks at 1.5× boldness, targets only settlements, and besieges only if the siege would end inside its grace.

**Tests:** 173/173 GUT tests pass, including 11 new in `tests/test_realm.gd`:
- the purchase ban in debt
- desertion amounts and the one-man floor
- highest-upkeep disbanding below the limit until income covers upkeep
- debt recorded in the turn and the chronicle
- the grace countdown and destruction
- survival by retaking
- immediate destruction with no army
- player game over and grace surviving a save
- the 2 → 3 migration
- a landless AI declaring war and going for a settlement
- an AI in debt not building or recruiting

The self-test passes.

**Soak test** (8 seeds × 50 turns, all AI, same seeds as Phase D, deterministic). Wars, battles, sieges and captures are unchanged in every seed. Differences:

| Seed | Before (Phase D) | Now |
|---|---|---|
| 11 | Lannet landless with a 10-unit army, treasury −1,036 at the end | Landless, deserted 173 men, destroyed after its grace (lowest treasury −1,036) |
| 22 | Lannet landless | Destroyed at once (no army left) |
| 33 | Lannet with 2 empty armies | Lost its last settlement, retook one in time and survived |
| 88 | Lannet landless at −6,024 | Deserted 195 men, destroyed; its lowest treasury was −1,074 instead of −6,024 |

House Verrin is destroyed in every seed, usually at once because its army fell with Willowmere. No faction went below the debt limit. AI time is unchanged: average 7.7 ms, median 4.6 ms, 95th percentile 30 ms, max 71 ms (the first turn of a session and battle turns).

**Screenshots** (generated, in `captures/`):

| File | Shows |
|---|---|
| `debt_warning.png` | Treasury −2,600 in red with the IN DEBT tag and its tooltip |
| `landless_grace.png` | The player landless: "LANDLESS · 5 turns" in the bar and over the army |
| `game_over.png` | The defeat screen |

## TW:WH3 parity pass (2026-10-02)

Spec and checklist: `docs/tw-ui-parity.md`, researched with sources and confidence levels. Section 12 gives each item's status: matched, by design, not yet possible, or open.

**Recruitment bug from playtest.** Two causes:
1. The old rule required the army inside or within 12 m of an own settlement. The host starts in open country in Greyhaven's region, which belongs to House Lannet, so Recruit was disabled; the reason only showed on hover.
2. Queued recruits were appended after the general and all units in a fixed-width scrolling row, so they were clipped or off-screen until they joined at End Turn.

Fixed:
- Province-wide recruitment (constitution).
- A TW-style recruitment drawer.
- Queued units shown at once as greyed cards with their turns left; clicking one cancels it.
- Cards narrow so 20 always fit.
- An inline reason when recruiting is impossible.

**Parity changes:**
- **Movement:**
  - Hold right-click to preview the move, release to give it; left click or Esc cancels.
  - No numbers anywhere on the map or path.
  - Gold range boundary.
  - The movement bar shows what a previewed move would spend.
- **Camera:**
  - Q/E rotate, middle-drag orbits, and the tilt follows the zoom.
  - Selection never moves the camera.
  - `,` / `.` cycling pans at the current zoom.
- **End Turn:** warnings (low funds, construction available, army can still move) with jump, cycle and skip; Enter, Shift+Enter and H.
- **Hotkeys:** Home, End, Backspace, Ctrl+P, 3, 4, and hold Space for banners.
- **Other:** an AI-turn skip bar, and rich tooltips (bold title, pinned beside the element).

**Tests:** 181/181 GUT tests pass headless, including 8 new in `tests/test_parity.gd`:
- the drawer queues greyed cards that cancel on click with a full refund
- the "own territory" reason
- recruiting anywhere in a province from its buildings
- a full 20-card army fits
- paths and blocked markers carry no numbers
- the attack preview
- warnings follow state and settings
- on the real map scene:
  - selection does not move the camera
  - cycling keeps the zoom
  - a held right click previews and its release orders; Esc cancels the hold and keeps the selection
  - End Turn jumps to a warning first; Shift+Enter ends the turn

The self-test passes and now covers the same camera, preview, input and warning behaviour.

**Found by the new tests:**
- The card-scale formula shrank the gaps as well as the cards (a full army was 29 px too wide).
- The overlay's `clear()` left nodes counted until the end of the frame.

**Screenshots** (generated, in `captures/`):

| File | Shows |
|---|---|
| `path_preview.png` | A held preview: green this turn, then yellow, no numbers; the gold range boundary; a red (multi-turn) spend on the movement bar; "Cannot recruit: Must be in your own territory" |
| `recruit_drawer.png` | The drawer in Goldspire, with two queued units as greyed "1 turn" cards |
| `end_turn_warnings.png` | "Construction available (1 of 2) · Crownwatch" with `<` `>` and Skip above End Turn |

**Not done:**
- Sticky tooltips.
- An attack cursor, double-click and edge scroll (TW:WH3 behaviour unverified).
- The WH3 End Turn button cluster and top-right dropdowns (the constitution's layout; owner decision).
- Global recruitment and capacity (open rules).
- A strategic map.
- With the drawer open, the taller army panel covers the bottom of Event Messages.

## TW:WH3 campaign layout, AI turn speed and the strategic map (2026-10-02)

Research and decisions: `docs/tw-ui-parity.md` section 13 (L1–L12, with sources and confidence). Checklist: section 12, updated.

**Part 1:** skill-point notifications, early lords, threats and demands, and foreign cults recorded as confirmed (constitution, game design).

**Part 2, layout:**
- **Top bar.**
  - Left: Menu, Advisor, Help, Unit browser, Camera settings.
  - Centre: treasury with breakdown tooltip, income, population, two greyed faction-resource slots, faction effects.
  - Right: tactical map, Events, Lords and heroes, Provinces, Missions, Known factions, Faction summary.
  - Lords, Provinces and Known factions are drop-downs built from campaign data; clicking a lord or province selects it and pans there.
  - Faction summary: Summary and Records (the chronicle); Statistics is greyed.
- **Round End Turn menu** at the bottom right:
  - End Turn in the centre, the hourglass turn counter below it, the notification gear beside it.
  - Objectives, Diplomacy, Technology and a culture slot, greyed.
  - The warning with `<` `>` and Skip sits above.
- **Bottom panel in three parts:**
  - Province: stats; settlement tabs with Buildings or Garrison; resources, climate (terrain shares) and effects.
  - Army: lord card, greyed equipment, traits and stances, and movement; recruit buttons above the cards, then the drawer and the cards; upkeep, men, replenishment and a greyed stance.
- **Drawer fix:** the panel ends left of the event feed and the round menu, and the feed ends above the menu, so the drawer no longer covers Event Messages (a test checks the geometry).
- **Event pop-ups:** war declared on you, a settlement lost, landless, destroyed. They are found by comparing the state before and after End Turn.

**Part 3, speeds:**
- The AI turn bar has Pause, 1x / 2x / 4x and Skip; the speed is saved in Settings.
- Following AI movements is Off / Only near my territory / All, default Off. It replaces the old on/off setting; old settings files fall back to Off.
- Your armies' animation speed is 1x / 2x, set in the camera settings, in Settings, or with R.

**Part 4, strategic map:**
- Tab, or zooming out past the farthest zoom, fades (0.35 s) to a flat parchment map with territory colours, borders, settlement seals with level pips and names, and army shields.
- Clicking a place or scrolling in returns there.
- Layers: Affiliation, Diplomatic status, Public order, Development, Climate and terrain. Attitude, Faith and Culture are greyed.
- Scaling:
  - The terrain is baked once from the movement grid.
  - Colours, icons and screen polygons are cached and rebuilt only when the state, the layer or the size changes. A refresh takes about 0.2 ms here; a test keeps it under 8 ms.
  - 3D rendering is switched off while the map stands open.

**Key conflicts resolved:**

| Key | Before | Now |
|---|---|---|
| Tab | Hide interface | Strategic map (TW) |
| K | – | Hide interface (TW); Alt+K adds letterbox bars |
| R | – | Your armies' speed 1x / 2x (TW: character move speed) |
| 1 / 2 / 5 | – | Building slots / garrison / heroes (coming later) |
| Ctrl+T | – | Settlement labels |
| Space | Hold for banners | Also skips during the AI turn (as before) |
| F, G | Follow army, Goldspire bookmark | Unchanged (ours; no TW key) |

**Tests:**
- 208/208 GUT tests pass headless, and again in the windowed batch (real portrait pixels).
- New files:
  - `tests/test_layout.gd` (11 tests): top-bar order and greyed buttons, lists from data, camera settings, summary and records, round menu, three-part panels, drawer geometry, pop-ups.
  - `tests/test_settings.gd` (8 tests): persistence, defaults, invalid values, follow modes, speed multipliers, the AI bar, camera settings, the Settings panel.
  - `tests/test_strategic_map.gd` (8 tests): layers, colours from state, refresh on change, screen mapping and caching, fade, click and scroll-in, refresh cost, and on the real map scene Tab, zoom-out, choose a place, K, Alt+K, Esc, Ctrl+T, 1, 2 and R.
- The self-test passes, headless and in the windowed batch.

**Screenshots** (one windowed batch, 1440×900, parked off-screen; in `captures/`):

| File | Shows |
|---|---|
| `province_selected.png` | Goldspire: three-part province panel, round menu, End Turn warning, top bar |
| `army_selected.png` | The Host of Goldspire: lord column, cards with recruit and disband above, army info |
| `round_menu.png` | The round End Turn menu with the warning (cropped from `army_selected.png`) |
| `strategic_affiliation.png` | Strategic map, Affiliation layer, with legend and layer bar |
| `strategic_development.png` | Strategic map, Development layer |

The screenshots were taken before three small follow-ups, which have not been re-captured:
- resource names in the province's right column were cut to four letters ("Ston", "Mine"); they now show in full in two columns;
- the layer bar overlapped the minimap's left edge by a few pixels; it is now narrower;
- the map terrain was drawn with nearest filtering; it is now linear.

**Not done or unverified:**
- TW positions on the round menu.
- The bottom panel's right column (ours).
- Which events TW pops up.
- The strategic map's visual style.
- Alt+K on WH3's campaign map.
- R's exact WH3 behaviour.
- Per-faction-group camera settings.
- The Treasury panel.
- Statistics.
- Heroes.
- The strategic map has no zoom of its own. At the big map's size it may need one, or region labels.
- Small text (12–13 px) loses some word spacing in the current font (existing issue, visible in the lord column).

## Map pipeline: data model and scale test (2026-10-02) — STOPPED on missed budgets

**Built** (design `docs/map-pipeline-design.md`, approved):
- **P1:** maps live in `data/maps/<id>/`, the prototype is the test map, and every loader reads the active map (`core/map_registry.gd`). Lookups are O(1): a province dictionary, plus a baked region raster for pipeline maps. Save schema 4 records the map ID and version and refuses saves from another map version.
- **Synthetic generator** (`map/synthetic.gd`): the full V1 world size (4,096 × 2,560 m, 2 m cells) with 600 regions, 225 provinces, 150 factions, 500 armies and 1,171 roads. It writes the same formats a real map uses: zstd gameplay bakes and a local render cache (`map/map_bake.gd`).
- **Tools:** `scripts/build_map.gd` builds a map; `scripts/scale_test.gd` is the CPU half of the scale test.
- **Build time:** the 600-region world builds in 3.8 s headless.

**CPU results** (synthetic600, mid-game worst case: every region owned, 500 armies; headless; debug editor build; Ryzen 7 5700X3D):

| Measurement | Result | Budget | |
|---|---|---|---|
| Load (world, grid, start state) | 0.92 s | ≤ 10 s | met |
| Memory after load / after 3 turns | 29 MB / 226 MB | ≤ 2.5 GB | met |
| `region_at` | 0.0014 ms | ≤ 0.01 ms | met |
| Save size / load | 1.1 MB / 0.47 s | ≤ 5 MB / ≤ 3 s | met |
| Save time | 213–221 ms | ≤ 100 ms | **missed** |
| First path plan (builds the A* grid) | 11.4–12.4 s | none set | a one-time hitch per session |
| Path plan, 60 m | 127–137 ms median | ≤ 5 ms | **missed** |
| End Turn, all 150 factions AI | turn 1: 28.8 s (includes the A* build); turns 2–3: 14.1 s and 17.1 s | ≤ 4 s (release) | **missed** |

**Where End Turn goes** (one AI phase, profiled):
- **Building the A* grid: 12.7 s.** A GDScript loop over 2.6 million cells.
- **Army orders: 25.5 s.** 569 path plans cost 21.2 s, but the A* search inside them is only 0.53 s. The rest is rebuilding army and settlement blocking for every plan: a key string from 500 armies and 600 settlements, then about 27,000 cells re-marked.
- **War decisions: 3.2 s** (odds simulations).
- **Assess, books, build and recruit: about 1.7 s.**
- **Economy, growth, armies and sieges together: about 0.16 s.**

**Not measured** (the run stopped first): the GPU half (frame time, draw calls, VRAM, strategic map). It needs the chunked-terrain runtime (P3).

**Not built:** the SVG and JSON authoring parser, the validator and debug overlay, the runtime map scene (P3), and the test map rebuilt through the pipeline (P5).

## Scale fixes and final CPU budgets (2026-10-04)

Option 3 (owner): fix first, then set final budgets from measured numbers. Measured on synthetic600 (mid-game worst case: every region owned, 150 factions, 500 armies), headless, Ryzen 7 5700X3D. Release numbers come from the "Windows Benchmark" export (official 4.7.2 templates, SHA-512 verified, `scripts/get_export_templates.ps1`).

**The five planned fixes:**
1. **Enemy blocking:** cached as an incremental index, per faction. Cell counts for every area and per faction; only armies that moved and settlements that changed hands are recomputed; synced once per frame per faction. Switching factions touches only their own cells.
2. **Pathfinding grid:** built in bulk from row runs baked at map build time, one native fill per run.
3. **Hierarchical pathing (HPA\*):**
   - stored least-cost paths between every pair of border crossings of a region (6,791 on synthetic600, 8 s at build);
   - region parts (ridge-separated areas), so start and goal legs stay short;
   - a connected-components raster for an instant "no route".
4. **AI:**
   - a per-turn odds budget (`data/ai.json` odds.turn_budget 24, rotating eligibility when factions outnumber it);
   - End Turn spread over frames (yearly steps, each faction's seven AI steps, and army orders one army at a time), with identical results to the one-frame version (tested) and a "The world takes its turn n / N" line.
5. **Saves:**
   - the main thread copies the state; encoding and the atomic write run on a worker thread;
   - every reader waits for pending writes;
   - a small `.meta` sidecar replaces parsing whole saves for slot lists and the save counter.

Also: spatial buckets for AI target scans and settlement lookups, and inlined path costing.

**Synthetic map change:** the generator now cuts passes through its ridges, following the design rule "ranges impassable except at passes". The earlier ridges formed closed mazes no authored map will have. Path numbers on the old maze-like map (debug, after fixes 1–2): 95th percentile 64–164 ms.

**Results:**

| Measurement | Before (debug) | After, debug | After, release | Final budget (release) | |
|---|---|---|---|---|---|
| End Turn, all AI, one frame | 14.1–28.8 s | 4.6–5.0 s | 3.1–3.6 s | — | |
| End Turn as the game runs it (spread over frames) | — | 4.4 s, 265 frames | 3.0 s, 190 frames | ≤ 10 s, UI responsive | met |
| Longest stretch without a frame during End Turn | whole turn | 75 ms | 58 ms | UI responsive | met (one ~58 ms stall per turn; ordinary frames do ≤ 12 ms of turn work) |
| Path plan, 95th percentile (60 / 150 / 400 / 1,000 m) | 127–137 ms median | 2.8 / 4.1 / 3.3 / 3.5 ms | 2.0 / 3.1 / 2.9 / 3.4 ms | ≤ 5 ms | met |
| Path plan, median | — | 1.2–1.9 ms | 1.0–1.7 ms | | |
| Path plan, worst of 100 | — | 18 / 63 / 4 / 4 ms | 20 / 54 / 4 / 4 ms | | over 5 ms for a few short moves across a ridge |
| First plan of a session (builds the grid) | 11.4–12.4 s | 166 ms | 152 ms | | |
| Save, main thread | 213–221 ms | 10.8 ms | 9.8 ms | ≤ 100 ms | met (background write 133 ms) |
| Load save | 467 ms | 120–230 ms | 155 ms | ≤ 3 s | met |
| Campaign load (gameplay data) | 0.92 s | 0.27 s | 0.11 s | ≤ 10 s | met |
| Memory after 3 turns | 226 MB | 266 MB | not measured (the counter is debug-only) | ≤ 2.5 GB | met |


## Lords, living settlements and changing land (2026-10-04) — STOPPED on GPU budgets

**Lords (Part 2):**
- Figures are drawn 2x on the campaign map (`data/campaign_view.json`), never below 56 px on screen.
- Every army has a floating faction banner that is clickable, shrinks a little far out and fades very close.
- Click targets scale with the figure.
- Before/after captures from the same cameras: `captures/lord_city_compare.png`, `lord_overview_compare.png`, `lord_goldspire_compare.png`.

**Living settlements and changing land (Part 3):**
- **Decisions:** confirmed in game-design §12.13 and the constitution; implementation in design Addendum A.
- **Built:**
  - culture biome profiles (`data/cultures.json`);
  - procedural sprawl (`map/sprawl.gd`, `data/settlement_sprawl.json`) with countryside features per building chain, drawn as MultiMeshes of low-poly kit pieces (`visuals/kits/`, manifest `kit.*`: Quaternius RTS models plus Kenney CC0 castle and town pieces);
  - land conversion with the climate yield factor (`core/land.gd`, an End Turn stage, save schema 5);
  - the pipeline 3D runtime: chunked GPU-displaced terrain with four LODs, a culture and conversion terrain shader, sea, streamed trees and settlements (`map/map_view.gd`, `map/map_scene.tscn`);
  - the strategic map's Culture layer.
- **Region sizing (Addendum A.5):** the synthetic world grew to 5,632 × 3,584 m (regions about 120 m apart).

**CPU on the larger world** (release build): see the table below. The hierarchy now serves any move between region parts, and loads with the grid.

**GPU** (RTX 4060, 1440×900; synthetic600; "worst" = every settlement a level-3 city or fortress with farms, mines, port, market, temple, barracks and walls, and mixed conversion states, over the densest area):

| View | GPU ms | Draw calls | Primitives | VRAM | |
|---|---|---|---|---|---|
| Farthest 3D zoom (210 m), worst | 5.35 | **2,071** | 1.46 M | 245 MB | draw calls over the 1,500 budget |
| Middle zoom (120 m), worst | 5.75 | **2,245** | 1.57 M | 245 MB | over |
| Close (60 m), worst | 5.87 | **1,910** | 1.38 M | 245 MB | over |
| Normal campaign view (150 m) | 7.48 | 1,314 | 1.05 M | 243 MB | met |
| Strategic map, Culture layer (3D off, as in the game) | **5.79** | 5,803 (2D) | 0.22 M | 209 MB | over the 3 ms budget |
| Strategic map, Affiliation layer (3D off) | **5.85** | 5,876 (2D) | 0.22 M | 206 MB | over |

GPU time is within the 8 ms 3D budget everywhere. VRAM is far below 2 GB.

**Budgets blown:**
- **3D draw calls in the worst case** (about 93 sprawling cities built near the camera, 28,000 kit pieces): the cities draw one MultiMesh per kit mesh, and each is drawn again in the four shadow cascades.
- **The strategic map:** it still draws one polygon, border and label per region on the CPU (fine at 4 regions). The design (§6.4) already planned an ID-texture shader for V1 Varos.

Stopped before Part 4, as instructed. Nothing was cut.

**Visual state (honest):**
- The sprawl, industry and conversion work and read clearly bigger than Lothern.
- Still a first pass:
  - the terrain is pale and washed out;
  - fields and road strips are flat quads that do not follow slopes;
  - Kenney's wall piece reads as a chunky block at this scale;
  - strategic-map labels pile up at 600 regions.
- Screenshots: `captures/city_small_large.png`, `farm_vs_mine.png`, `convert_grid.png` (0 / 3 / 6 / 9 turns, Greek to orc), `lothern_vs_level3.png`, `gpu_close_worst.png`, `synthetic_view.png`, `strategic_culture.png`, `strategic_affiliation.png`.

**Also found and fixed:**
- Headless imports had silently imported nothing since 2026-10-01. Godot tried to import `art_source/general_aurek/general_aurek.blend` through Blender and stalled. Fixed with `filesystem/import/blender/enabled=false` in project.godot; `art_source/` is untouched.

**CPU on the larger world** (release build, after the pathfinding fix):

| Measurement | Result | Budget | |
|---|---|---|---|
| Path plan 95th percentile, 60 / 150 / 400 / 1,000 m | 1.7 / 3.1 / 2.9 / 4.2 ms | ≤ 5 ms | met |
| Path plan, worst of 100 | 48 / 99 / 7 / 8 ms | | a few short moves across a ridge |
| Grid and hierarchy build, once per session | 245 ms | | |
| End Turn as the game runs it | 2.9 s over 180 frames | ≤ 10 s | met |
| Longest stall during End Turn | **192 ms** (one faction's step) | UI responsive | **regressed** from 58 ms on the smaller world. Debug comparison: 107 ms with the hierarchy for every cross-part move, 94 ms with the old 100 m threshold, so the cause is the larger world's AI steps, not the threshold |
| Save, main thread | 12 ms | ≤ 100 ms | met |

## Remaining limitations

- Artwork is a prototype and has not been approved against the desired 2016 Total War campaign-map benchmark.
- Camera, village, city, and character views are functional; there is no playable strategy campaign yet.
- Checks exercised controls programmatically. A complete manual mouse/keyboard walkthrough on the user's desktop is still needed.
- Godot reports inability to read the Windows root certificate store in this sandbox. The game makes no network requests and rendering/capture complete successfully. Launcher redirects runtime data into the project-local .local folder to avoid external filesystem writes.
- Initial startup constructs geometry and may briefly pause. Development changes are not saved between sessions.

Screenshots in captures are generated by the running game, not concept art.

## Budget fixes (2026-10-04)

The three budgets that failed in the previous run, fixed without cutting content.

**1. City draw calls** (RTX 4060, 1440×900, synthetic600; the same worst-case views as before):
- **Approach:** each kit piece is baked once into a single mesh with one surface per look (`map/kit_cache.gd` `baked()`).
  - The model's parts and material colours are combined, with the colours in linear vertex colours.
  - Distance LODs are regenerated with `ImporterMesh.generate_lods`.
  - A city draws one MultiMesh per piece instead of one per model part with a surface per material.
  - Fields, roads and small props cast no shadow (`data/settlement_sprawl.json` `no_shadow`).
- **Measured** (`--instanced` draws the old way, for comparison):

| View | Draw calls before → after | GPU ms before → after | Primitives before → after | VRAM |
|---|---|---|---|---|
| Farthest zoom (210 m), worst | 2,071 → **867** | 5.77 → 6.29 | 1.46 M → 4.74 M | 245 → 248 MB |
| Middle zoom (120 m), worst | 2,245 → **889** | 5.35 → 5.58 | 1.57 M → 5.35 M | 245 → 248 MB |
| Close (60 m), worst | 1,910 → **669** | 5.79 → 5.95 | 1.38 M → 4.42 M | 245 → 248 MB |
| Normal campaign view (150 m) | 1,314 → 514 | 7.48 → 5.61 | 1.05 M → 1.82 M | 245 MB |

- **Draw calls:** all under 1,500.
- **GPU:** within the 8 ms budget.
- **Primitives:** higher, because the regenerated LODs are less aggressive than the importer's. This is within the GPU budget and goes away with the low-poly culture kits.
- **Screenshots:** `captures/p1_{far,mid,close}_{before,after}.png` are identical except the small props' shadows.
- **First attempt, rejected:** merging each whole city into a few meshes cut draw calls to about 350, but it loses the per-distance LODs. That gave 18–22 M primitives and 2.7 GB VRAM.

**2. Strategic map:**
- **Approach:** the map is now one shader pass (`ui/strategic_map.gdshader`).
  - It reads a region-ID texture (the baked raster, or the test map's polygons scanned into one) and a palette of fills and owner colours. Borders are drawn in the shader.
  - Icons are drawn as five MultiMeshes.
  - Names are placed greedily by importance (level, yours, then name) and are never allowed to overlap a name or seal. A smaller map on screen shows fewer.
- **Results:**
  - Draw calls: 5,800 → 58–130.
  - Render CPU: 3.2 → 0.1 ms.
  - GPU: 5.8 ms → **0.21 ms** for the whole frame, measured with the GPU loaded.
- **About the measurement:** a lone light 2D frame lets the GPU clock down, so single runs read anywhere from 1.6 to 6.5 ms. An empty frame measures 0.02 ms. Stacking 21 and 41 copies of the territory pass (`--strategic-stress=N`) gives 0.13–0.23 ms per pass under load.
- **Zoom:** the strategic map has no zoom of its own. As in TW:WH3, scrolling in returns to the 3D map. "Thinning by zoom" therefore means thinning by on-screen scale.

**3. End Turn stall** (release build, synthetic600):

| Measurement | Before | After |
|---|---|---|
| Longest stall during End Turn | 192 ms | **26.7–31 ms** |
| End Turn as the game runs it | 2.9 s | 2.7–2.8 s |
| End Turn in one go (turn 1 / 2) | 3.0 / 2.8 s | 3.2–3.4 / 2.7–3.0 s (budget 4 s) |
| Path plan p95, 1,000 m | 4.2 ms | 4.0–4.5 ms (one of ten runs 5.3 ms) |
| Save, main thread | 12 ms | 11–12 ms |

- **Causes, profiled:**
  - a failed direct search exploring the whole map (187 ms);
  - catching up the blocking index after the yearly moves inside some army's turn (60 ms);
  - after those, the scribes' yearly entries (one pass over all settlements per faction, about 50 ms).
- **Fixes:**
  - The AI's direct searches run on a window around start and goal (`Movement.ai_cap`, `_window_path`, with blocking areas bucketed by position). The player's moves keep the full search.
  - The blocking index syncs once at the AI phase start.
  - The chronicle groups settlements by faction in one pass.
  - The slicer now names the longest chunk (`end_turn_sliced_longest_chunk_at`).
- **Tests:** sliced and one-go End Turns still give identical results.

## Terrain overhaul (2026-10-04), synthetic600

**What changed** (owner brief: TW:WH3 campaign terrain, `docs/reference/tw/terrain_*.png`, not committed):
- **Relief** (`map/synthetic.gd` `_relief`, on the 8 m land grid):
  - broad massifs from a ridged fractal with domain warp inside a low-frequency massif mask;
  - foothills rolling into the plains, and pass valleys where a gap noise ridges;
  - a thermal-erosion pass (wider bases, scree at the feet);
  - rivers from a priority-flood drainage network with meander noise, traced as chains, rounded and drawn with widths by drainage area. They are carved into valleys and stored in the render cache (`rivers.bin`). Rivers are **visual only** for now: crossing rules are open.
  - Peaks reach about 110 m. Map versions bumped to 2.
- **Texturing** (`map/terrain_view.gdshader`, per-culture `ground` palettes in `data/cultures.json`, targets `docs/reference/biomes/`):
  - grass and dry patches, rock by slope and on the massifs, scree, snow above each culture's snow line, sand on beaches, dirt on passes and roads, water in rivers;
  - canopy carpets on forest cells with crown relief;
  - per-pixel normals and two-scale cavity shading, strata on rock;
  - organically frayed culture borders.
  - **Found and fixed:** the palette texture had been read as linear while holding sRGB colours. That is why the terrain looked pale and washed out before.
- **Forests:** Quaternius Stylized Nature trees per culture (weighted models, density, tint, scale), within 320 m of the camera. They are thinner but larger, over the shader's canopy.
- **Roads and fields:** draped over the terrain as one mesh per city. Fields turn along the contour with furrows; roads run along their direction (they were drawn crosswise).
- **Atmosphere:** depth haze, aerial perspective and a mild colour grade (`data/campaign_view.json` `atmosphere`).

**GPU** (RTX 4060, 1440×900). The new geography packs more cities near the densest point (137 cities, 42,600 pieces in the worst case vs 93 and 28,000 before), so the worst case is heavier than in the previous table.

| View | GPU ms | Draw calls | Primitives | VRAM |
|---|---|---|---|---|
| Close (60 m), worst | 5.63 | 1,110 | 1.31 M | 294 MB |
| Middle (120 m), worst | 5.56 | 1,196 | 1.50 M | 294 MB |
| Farthest (210 m), worst | 5.39 | 1,168 | 1.40 M | 294 MB |
| Normal campaign view (150 m) | 5.95 | 872 | 1.20 M | 279 MB |
| Massif close-up | 6.61 | 139 | 0.44 M | 268 MB |
| TW comparison angle | 4.70 | 92 | 0.45 M | 268 MB |

**Budget fixes made on the way:**
- The first pass measured 16–30 ms. A `--hide=trees,cities,terrain,shadows` attribution showed trees cost 9 of 12 ms. Fixes:
  - fewer, larger trees;
  - LOD bias on city and tree MultiMeshes (Godot picks a MultiMesh's LOD from its nearest point);
  - city detail ranges (small props to 260 m, houses to 480 m);
  - two shadow cascades instead of four;
  - a light farmstead piece (the RTS farm had 10,000 triangles and no LOD).

**Screenshots** (`captures/`):
- `p2_compare_close.png`, `p2_compare_mid.png`, `p2_compare_far.png`: before | after from the same camera arguments. The map was regenerated, so the dense focus point moved.
- `p2_tw_side_by_side.png`: TW terrain_1 | ours.
- `p2_normal.png`, `p2_massif.png`.

**Still not TW quality:**
- Cities are concentric rings (next part).
- Distant forests are flat canopy texture.
- Rock lacks TW's sculpted detail.
- The sky is a flat procedural sky.

## Settlement variety and culture kits (2026-10-04)

**Culture kits:**
- Every culture has its own procedural building kit, built from simple shapes (`visuals/kits/cultures/culture_kit.gd`, `kit_shapes.gd`).
- Pieces: houses ×3, tall house, hut, wall, tower, gatehouse, keep, temple, a bridge, and one signature building per specialization path (military, farming, mining, lumber, market).
- Each piece is 20–620 triangles. They load through the asset manifest's new `procedural` section (`kit.<culture>.<piece>`).
- Targets: `docs/reference/biomes/` and `specializations/` (palette and style only).

**Layouts** (`map/sprawl.gd` rewritten): every culture lays out its own way, using the terrain (high ground, slopes, shores, rivers, forests, mountains):

| Culture | Layout |
|---|---|
| Roman | Grid and forum, square walls |
| Lizardmen | Plaza with pyramids and causeways |
| Desert | Blocks along the river, a processional avenue to the pyramid |
| Greek | Terraces stepping down the contours toward the sea |
| Medieval | Crooked lanes from the gates to a square below the castle |
| Ratmen | Leaning stacks with walkways over ruins |
| Dwarves | A hold at the mountain's foot, halls stepping up, a fortified front |
| Orcs | A palisaded stronghold and sprawling camps |
| Elves | Spires and bridges |
| Dark elves | Towers on the rocks and shore |
| Beastmen | Herdstone and groves |

- Walls follow the built outline and stop at cliffs and shores.
- Interiors are filled; suburbs spill along the roads.
- Towns show their specialization path. A mining town on flat land opens a pit; lumber towns keep their forests.
- Rivers count as water for layouts.

**Goldspire Rock rebuilt** to the owner's brief:
- a golden spire with the castle carved into it: colonnaded halls and gold-roofed towers on the ledges, glowing mines, and a colossus in the face;
- the white Greek city with red roofs at its foot, a theatre, and walls to the sea;
- the harbour with a breakwater and lighthouses.

**GPU** (worst case: every settlement a level-3 city with every chain, mixed conversion):

| View | GPU ms | Draw calls | Primitives | VRAM |
|---|---|---|---|---|
| Close (60 m) | 5.55 | 330 | 0.77 M | 359 MB |
| Middle (120 m) | 5.32 | 641 | 1.59 M | 359 MB |
| Farthest (210 m) | 5.20 | 607 | 1.47 M | 359 MB |
| Normal view (150 m) | 5.32 | 401 | 1.18 M | 333 MB |

- **Draw calls:** the first run of the culture kits measured 1,702. Separate meshes per culture piece, doubled in mixed and converting regions, put it over the budget. The low-poly kit pieces now merge into one mesh per look per settlement; imported props stay instanced with their LODs.

**Screenshots** (`captures/`):
- `p3_variety_grid.png`: 12 settlements of mixed cultures, types, paths and terrain;
- `p3_lineup_grid.png`: one level-3 city per culture;
- `p3_goldspire_1.png`, `p3_goldspire_3.png`.

**Tests:**
- every culture builds its own pieces in its own layout;
- walls are not a ring, and the inside is built up;
- the Roman square wall;
- mining pit, docks, farming and lumber.
- Self-test passes.

**Still rough:**
- On flat ground the Greek terraces still form a rounded blob (a hill gives them their shape).
- Small towns read sparse at the showcase distance.
- The kits are first-pass shapes. The colossus and breakwater are blocky.

## Map pipeline: authoring, validator, debug overlay, test map (2026-10-04)

**Built** (design `docs/map-pipeline-design.md` §2–5):
- **Sketch parser** (`map/sketch.gd`): the SVG subset (layers; path M/L/H/V/C/Q/Z absolute and relative, circle, ellipse, polygon; data attributes). Transforms and anything else are errors naming the element.
- **Pipeline build** (`map/pipeline.gd`, via `scripts/build_map.gd`):
  - land, lakes, hills, forests, ranges, passes, rivers, sites, pinned roads and pinned region outlines, from `sketch.svg` + `world.json`;
  - outputs the same committed bakes and render cache as the synthetic maps;
  - deterministic (tested).
- **Validator** (`map/validator.gd`, `scripts/validate_map.gd`, run by the build):
  - Checks:
    - ids and references;
    - every land cell in a region;
    - regions in one piece;
    - provinces contiguous;
    - major types;
    - landmarks with three stages;
    - settlement spacing;
    - settlements on water or mountains;
    - majors reachable by land or port;
    - faction start regions and seats;
    - culture, faith and race shares;
    - province budgets;
    - committed bakes matching their sources.
  - **Skipped** until their systems exist: sea graph and port anchors, Greywall continuity, start positions against the world bible, minor factions, names by culture.
- **Debug overlay** on the strategic map (F9 with debug keys; `--debug-layer=`): region IDs, movement classes, validator problems as red markers (hover for the message).
- **The test map rebuilt through the pipeline** (`data/maps/testmap_pipeline/`):
  - The sources were converted once from the legacy map: same region IDs and pinned borders, settlements, factions, armies, the Greyspine range and pass, the coast, Goldspire.
  - New: a river (Silverrun) and two forests.
  - It builds in 0.35 s.
  - `--demo` shows the specialization looks (Willowmere farming, Crownwatch military), industry (Greyhaven port and market, Goldspire mine and port), Willowmere mid-conversion (Roman to Greek), and Goldspire's landmark with sprawl.
  - The legacy `testmap` stays the default for tests, the self-test and `Main.tscn` until the campaign scene runs on pipeline maps.

**Validator results:**

| Map | Errors | Warnings | Notes |
|---|---|---|---|
| testmap_pipeline | 0 | 0 | |
| testmap (legacy) | 0 | 0 | |
| synthetic600 | 4 | 114 | 241 land cells outside every region (islands without a site); provinces p059, p159 and p175 split across impassable ridges; 114 factions start with more than 2 regions |
| synthetic_tiny | 14 | 5 | majors closer than 30 m (the tiny map is dense on purpose) |

The synthetic maps are performance fixtures, so their findings are recorded, not fixed.

**Captures** (`captures/`): `p5_testmap_overview.png`, `p5_testmap_goldspire.png`, `p5_testmap_willowmere.png`, `p5_testmap_crownwatch.png`, `p5_debug_regions.png`, `p5_debug_movement.png`, `p5_debug_problems_synthetic600.png`.

## Fixes carried from the last report (2026-10-05)

**Stance-only battles** (`docs/war-and-realm.md` §1):
- **Pre-battle panel:** shows both forces, terrain and weather, the balance-of-power bar, the stance choice (Aggressive / Balanced / Defensive), Fight, Withdraw (defender) and Besiege (settlements).
- **Deployment screen and 2D replay:** removed from the UI (code dormant).
- **Battle report:** keeps the "why you won or lost" summary and both casualty tables.
- **Sim:** a stance scales the losses each side deals and takes, and how hard it pursues. Defensive takes less again behind walls or on hills. The AI picks its stance from the odds; the player starts Balanced; choosing a stance recomputes the balance of power. Numbers are in `data/battle.json` `stances`.
- **Multi-army battles:** each side's main armies fight with the garrison, and nearby armies of both sides join as reserve blocks.
- **Tests:** Aggressive costs both sides more; Defensive costs less and holds walls better; AI stance rule; the player's stance reaches the sim.

**Strategic map legend:** lists only the factions you have met (yours, at war with you, or within 220 m of your settlements and armies; a placeholder until contact and envoys exist), with a count of the factions not met. The title collapses it.

**Greek cities always terraced:** the acropolis core stands on stepped stone terraces (plinths, 2–10 m) even on flat ground, stepping down a terrace per band; on a hill the contours add to it.

**Small towns:**
- **Footprints:** larger and denser in the data. Small Roman towns use fewer streets.
- **People:** specks of townsfolk on streets, squares and the roads out.
- **Smoke:** a few chimneys smoke (particles drawn within 320 m).
- **Houses** (flat ground, levels 1/2/3):

| Settlement | Before | After |
|---|---|---|
| Medieval town | 29/39/63 | 51/66/105 |
| Roman village | 5/13/24 | 11/23/40 |

**TW terrain gaps:**
- canopy depth: distant forests rise into a lumpy canopy beyond the 3D trees;
- sculpted rock: a screen-space bump from two-scale rock noise;
- a real sky shader: gradient, sun glow, drifting clouds;
- haze retuned.

**GPU** (synthetic600, worst case):

| View | GPU ms | Draw calls |
|---|---|---|
| Close | 4.64 | 340 |
| Middle | 5.38 | 709 |
| Farthest | 5.34 | 675 |
| Normal view | 5.30 | 458 |

All within budget.

## Playtest fixes (2026-10-05, Part 3)

Research and decisions: docs/tw-ui-parity.md §10 and §15.

**Lord model:** the rigged Blender general (`art_source/general_aurek`) imports cleanly: a 6,580-vertex body skinned to a 22-bone humanoid rig (Godot humanoid bone names), separate mace and shield, `faction_primary`/`faction_secondary` materials. Exported to `assets/models/general_aurek.glb`; same campaign size as the old procedural figure; faction colours on cape, tabard and shield; no walk animation yet.

**Lords & Heroes window:** opened from the magnifying glass under the lord portrait, the Lords list, and the unspent-points warning. Details (stats, traits, army), Skills (Command / Logistics / Conquest rows, one point per level, auto-allocate; placeholder: no effects), Equipment (greyed slots). Skills are saved with the general.

**Diplomacy:** full screen from the round menu or by double-clicking a foreign army or settlement. Your faction, known factions with Quick Deal, the selected faction mirrored. Declaring war works (with a confirmation); attitude, reliability and deal chances are placeholders; treaties greyed.

**Turn transitions:** an "Ending turn" banner while the year closes, the AI turn bar naming the moving faction, and "Your turn / Year X" when control returns.

**End Turn warnings:** settlement upgrade, idle construction, lords with movement, unspent skill points, armies that can recruit, low funds; each skippable, each item jumps to its subject (the skill-points warning opens the skill tree).

**Upgrade icons:** a green arrow on upgradeable building cards, a green hammer on the settlement banner.

**Attack flow:** right-clicking an enemy not at war asks for war first; then the lord marches over the turns needed, and the pre-battle panel opens on arrival. Checked by tests/test_attack_flow.gd and a capture series: war window, march, arrival in year 2.

**Strategic map:** painted from map data, in the look of `docs/reference/world/varos_map.jpg`:
- relief shading, snowy peaks, rivers;
- an inked coast with ripple contours, a teal sea, paper grain;
- watercolour territory with smooth owner borders (region polygons rasterised at 8×, cached);
- mountain, hill and tree glyphs;
- province names zoomed out, settlement names zoomed in;
- the wheel zooms up to 3×.

**Tests:** 295 GUT tests pass headless; the self-test passes (now also opens the character window and the diplomacy screen).

## World enlarged 2.5x (2026-10-06) — STOPPED on two budgets

Design: map-pipeline-design Addendum B.
- **Varos:** 14,080 × 11,520 m, cell 4 m (3,520 × 2,880 cells). It builds headless in 61 s with 0 validator errors, footprints included.
- **The test map:** 700 m (version 2) with its sites moved apart. 297 GUT tests pass; the self-test passes.
- **Bench armies:** the enlarged Varos has no armies until Stage A content. The benchmark raises one 8-unit army per faction at its seat (42 armies).

**CPU budgets** (`scripts/scale_test.gd -- --map=varos --turns=2`):

| Budget | Debug | Release | Target | |
|---|---|---|---|---|
| Load (world, grid, state) | 45 ms | 36 ms | ≤ 10 s | met |
| RAM after End Turns | 796 MB (static) | – | ≤ 2.5 GB | met |
| `region_at` | 1.4 µs | – | ≤ 10 µs | met |
| Path preview p95, 60 / 150 / 400 m | 0.3 / 0.5 / 2.6 ms | 0.3 / 0.5 / 2.6 ms | ≤ 5 ms | met |
| **Path preview p95, 1,000 m** | **8.6 ms** | **8.5 ms** (median 1.9, max 13) | ≤ 5 ms | **missed** |
| End Turn, 42 AI factions | 165 ms | 93 ms | ≤ 4 s | met |
| End Turn, longest slice | 13.9 ms | 12.5 ms | no frame over 50 ms | met |
| Save / load | 14 / 10 ms, 102 KB | – | ≤ 3 s, ≤ 5 MB | met |
| Map build (authoring, headless) | 61 s | – | ≤ 2 min | met |
| **First-run render cache build** | **42.6 s** | not measured | ≤ 30 s | **missed in debug** |

- **Path p95:** the time is spent in the hierarchy's route legs; the native A* dominates, so the release build is no faster. Synthetic600 measured 4.2 ms on its 2 m cells.
- **Render cache:** load once built is 96 ms.

**GPU** (`map/map_scene.tscn -- --map=varos --focus=dense`, 1440×900, RTX 4060):

| View | GPU ms | Draw calls | VRAM |
|---|---|---|---|
| Farthest zoom (210 m) | 4.80 | 24 | 338 MB |
| Middle (120 m) | 4.82 | 19 | 338 MB |
| Close (60 m) | 6.21 | 12 | 338 MB |
| Normal view (150 m) | 5.14 | 21 | 338 MB |
| Strategic map, painted (3D off) | **1.82** | 59 (2D) | 443 MB |
| Strategic map, 21 stacked passes | 9.74 → 0.40 ms per pass | | |

All GPU rows are within budget (≤ 8 ms 3D, ≤ 3 ms strategic, ≤ 1,500 draw calls, ≤ 2 GB VRAM). This includes the painted strategic-map shader, which Part 3 of the last block did not measure. The draw calls are low because the outline has no content yet (7 settlements built near the camera, few trees); Stage A content will raise them.

**Follow-up (owner's decisions, 2026-10-06):**
- **Path preview (B + C):**
  - The hierarchy's legs (start to the first crossing, last crossing to the goal) now search a small local window (8 cells of margin) instead of the 10M-cell grid; they fall back to the whole grid only when a leg detours outside it.
  - The preview re-plans only when the cursor enters another grid cell. A long move first draws its coarse route (crossings joined by straight lines); the full path replaces it on the next frame.
  - Release build, 1 km: full plan p95 **4.45 ms** (debug 4.65–4.95 over four runs); the first preview frame p95 **0.23 ms**. **Met.**
- **First-run render cache:**
  - Release build: **36.7 s**, over 30 s and under 60 s, so option B. On the first start with a map version, the campaign shows "Preparing the world map". The cache is built on a worker thread with its steps and elapsed time, then the campaign loads.
  - Measuring it found a real bug: Varos's `sketch.svg` was imported as a texture (a 14,080 px raster) and was missing from exported builds, so the shipped game could not have built the cache. It is now kept as a plain file (as on the test map).

## Visual fixes from the playtest (2026-10-06, Part 2)

- **Goldspire Rock rebuilt** (`visuals/landmarks/goldspire_rock_visual.gd`) as a sheer golden sea cliff, not a cone:
  - the sea face drops near-vertically, the land side slopes;
  - deep buttresses and ravines, strata, a scree foot and a craggy skyline.
  - Carved into the face: six tiers of colonnaded halls with balconies, a grand carved gateway, stairways up the cliff, towers emerging from the stone, glowing mines, and a giant statue in a niche.
  - Above and below: gold-roofed spires and a ring of halls on the summit; the Greek city, theatre, harbour and lighthouses below.
  - Landmarks now turn to face the nearest water (`map/map_view.gd`); before, Goldspire only faced the sea on the test map.
- **Walls:**
  - Curtain walls are 5.2 m tall and 1.9 m thick, with a battered base, a string course and merlons. Every wall piece reaches 2 m below its foot, so it follows slopes.
  - Towers are 9–10 m (round with machicolations and cones for the north; square for the south).
  - Gatehouses have twin towers, an arched passage and crenellations.
  - The palisade cultures get earth banks and fighting steps.
- **Buildings:**
  - **Medieval:** stone ground floors and jettied half-timbered upper floors, steep slate roofs and chimneys.
  - **Roman:** hipped terracotta roofs with eaves, window rows, and insulae with shop arches.
  - **Greek:** whitewashed walls, blue doors and shutters, parapet roofs or low red tiles, roof rooms.
  - **Desert:** parapets, domes and deep windows.
  - **Dwarf, dark elf, ratmen, orc, elf and lizardmen houses:** doors and lit windows.
  - **Greek terraces:** limestone retaining walls instead of white blocks.
- **Starting generals:** skill points are pre-allocated, so the warning is gone from turn 1.
- **Strategic-map shader:** 1.82 ms on Varos (World enlarged, above).
- **Image-to-3D later (TRELLIS):** an exact `visuals` entry in `data/asset_manifest.json` now overrides a procedural builder. A generated model wrapped in its own visual scene replaces any kit piece (`kit.<culture>.<piece>`) or landmark stage through the manifest alone (`tests/test_asset_manifest.gd`).
- **GPU, worst case** (synthetic600, every settlement level 3 with every industry):
  - 5.25–6.09 ms GPU, 280–630 draw calls, 590 MB VRAM: within budget.
  - Triangles: 4.0–4.3 M, a little over the 4 M guideline but below the 4.74 M measured before this change.
- **Tests:** 300 GUT tests pass; the self-test passes.

## Stage A content (2026-10-06, Part 3) — stopped for the owner's playtest

**Map:**
- Varos at 14,080 × 11,520 m; Stage A's 73 regions in 36 provinces.
- Rivers are barriers, crossed only at bridges (where a planned road crosses) and fords.
- `scripts/plan_roads.gd` routes 123 roads on the built grid (A* around mountains and sea, few river crossings), with 30 bridge crossings and 16 fords. The 8 unrouted links are to islands.
- The Greywall is drawn as a wall (24 m, battlemented, towers every 160 m, open at Wardens' Gate).
- Builds in about 63 s with 0 validator errors.

**Factions (42):**
- culture, faith (Throne Church, the Radiant Seven with city patrons, the race faiths);
- tendencies mapped to the AI's personalities;
- original crests (field, division, charge; no real-world symbols);
- the lore friendships and rivalries of v1-content §3.2, mutual.
- The Throne Church is `untouchable`: the AI never targets or declares war on Caeloth (constitution).

**Start:**
- one army per faction at its seat (placeholder rosters; the shared human units stand in for dwarves, orcs, dark elves and ratmen);
- populations and buildings by type and level;
- starting generals' skills pre-allocated.
- Economy: the playable houses start in surplus (Varn +211, Varrenus +39, the Aurekids +211 a turn). Four AI factions start in small deficits (−24 to −164 a turn, their treasuries last 36+ turns): placeholder balance.

**Landmarks:** all 13 Stage A landmarks have their own three growth stages: Caeloth, Crownhaven, Frosthold, Wardens' Gate, Skyreach, Harrow Crossing, Highbloom, Oldstone Citadel, Tempest Keep, the Skulkmire, Emberdeep, Brinecrag, and Goldspire. `tests/test_landmarks.gd` checks them.
- The reference image `docs/reference/landmarks/brinecrag.jpg` shows a dwarf hold. It was used for Emberdeep, which had none; Brinecrag follows the world bible's text.
- There is no Emberdeep image of its own.

**Biomes and specializations:** every Stage A culture already has its biome (`data/cultures.json`: ground, forests, tints) and kit with specialization buildings. Unchanged in this block.

**Screens:**
- the faction selection (three houses with crests, founder, tradition, culture, start, and the start on the parchment map);
- the illustrated intro (three panels per house, placeholder art slots);
- the court introduction (a placeholder until the character system).
- New Campaign plays on Varos; tests, the self-test and captures stay on the test map.

**AI soak** (`scripts/ai_soak.gd -- 50 11,22,33,44 --map=varos`, all 42 factions AI-run, 50 turns, debug build):
- stable: no script errors, deterministic, no desertion, no stuck armies;
- 3–4 wars, 1–3 battles, 1–2 sieges and 2–3 captures per seed;
- End Turn 145–154 ms on average, worst 584 ms.
- **The world is quiet:** about 17 of 42 factions take no action for 10 turns or more. A tuning question for the playtest.

**Tests:** 306 GUT tests pass; the self-test passes.
