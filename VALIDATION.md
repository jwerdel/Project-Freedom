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

## Remaining limitations

- Artwork is a prototype and has not been approved against the desired 2016 Total War campaign-map benchmark.
- Camera, village, city, and character views are functional; there is no playable strategy campaign yet.
- Checks exercised controls programmatically. A complete manual mouse/keyboard walkthrough on the user's desktop is still needed.
- Godot reports inability to read the Windows root certificate store in this sandbox. The game makes no network requests and rendering/capture complete successfully. Launcher redirects runtime data into the project-local .local folder to avoid external filesystem writes.
- Initial startup constructs geometry and may briefly pause. Development changes are not saved between sessions.

Screenshots in captures are generated by the running game, not concept art.
