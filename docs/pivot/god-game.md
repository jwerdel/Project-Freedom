# Project Freedom: God Game Pivot

**Status:** Exploration (branch `god-pivot`, 2026-10-10). Nothing here is approved for the main game. The constitution still governs the strategy game on `main`.
**Markers:** **Decided** = owner decision for the pivot. **Open** = needs the owner's call. **Recommendation** = a proposal, not a decision.
**Companions:** `constitution.md`, `docs/game-design.md`, `docs/war-and-realm.md`, `docs/world-bible-v2.md`, `docs/v1-scope.md`.

---

## 1. Vision

The player is an all-powerful being. He walks, runs and flies. He can level a city with one punch (One Punch Man scale). He is **Edric Varn, the Winter Shield**, founder of House Varn of Frosthold (`docs/world-bible-v2.md`).

The arc:

1. Protect a village.
2. Rule it.
3. Grow it into a city.
4. Grow the city into an empire.

There is no skill-based combat. Nothing in the world can beat the god in a fight. Power is overwhelming; the challenge is what kind of ruler you are. Do people love you, fear you, or flee from you? Do you build, or do you break?

### 1.1 The four reference games

| Game | What we take |
|---|---|
| **Where Winds Meet** | Traversal and a vast, open world. Movement as a pleasure in itself. |
| **Manor Lords** | City building with living villagers: roads, plots, families, seasons. |
| **Mount & Blade II: Bannerlord** | The campaign map, clans, fiefs, founding a kingdom. |
| **Total War: Warhammer III** | The campaign UI and the strategy layer. Already built. |

### 1.2 Rule for all later work **(Decided)**

- Copy known mechanics from these four games freely and closely.
- Do not invent our own version when a known game already solved it.
- When unsure, do it the way those games do. Research first.
- This widens the old "TW:WH3 UI parity" rule in `CLAUDE.md`: the other three games are now references too. TW:WH3 still governs the campaign UI (panels, cards, tooltips, End Turn, notifications, diplomacy, strategic map).

---

## 2. The core loop

The god moves between three views without loading screens:

| View | What the player does |
|---|---|
| **On foot / in flight** | Walks the village, flies over the land, deals with threats in person. |
| **Settlement (build mode)** | Lays roads and plots, places buildings, assigns families (Manor Lords). |
| **Empire** | Rises high enough that the land becomes the campaign map: realm, armies, diplomacy, End Turn (TW:WH3 / Bannerlord). |

The loop: **walk, fly and rise to the empire view; build and grow settlements; protect them; rule.**

### 2.1 One loop, concretely

1. Edric stands in Hearthwick in late summer. Villagers carry wood along the road he drew last week. Approval is 68%: one family is homeless.
2. He opens build mode, draws three burgage plots off the main road and sets the new well as the High-priority project. Unassigned families start building.
3. A notification on the End Turn button: orc raiders are burning a hamlet in the next valley.
4. He leaps, chains a Threefold Skywalk into a dash, glides over the ridge and lands on the raiders. The fight is not in doubt. The question is how carefully he lands: a Meteor Flight slam ends the raid and also flattens two farmsteads.
5. He rises until Frosthold Vale becomes the campaign map. The empire view shows the cost: the hamlet lost people, its taxes drop, and his standing moved toward Feared.
6. In the empire view he sends a vassal army to the Greywall, accepts a marriage offer, queues a granary in a town he has not visited in years, and ends the turn.
7. He dives back down to Hearthwick for the autumn harvest.

---

## 3. Simulation level of detail

Only the settlement near the player has individual villagers. Every other settlement runs on the existing numeric economy. The existing strategy systems become the far-away half of the game.

### 3.1 Two modes per settlement

| Mode | When | Simulation |
|---|---|---|
| **Living** | The god is inside or near the settlement. | Individual villagers, families, carried goods, plots, workplaces. |
| **Numeric** | Everywhere else. | Population, growth, income, stockpiles and buildings as numbers: `core/economy.gd`, `core/resources.gd`, `core/buildings.gd`, `core/construction.gd`, `core/seasons.gd`, `core/markets.gd`. |

### 3.2 Handoff: arriving (numbers to villagers)

- Read the settlement from `GameState`: population, buildings and slots, stockpiles, approval inputs.
- Spawn families to match population (a fixed number of people per family).
- Place buildings from the settlement's building list onto plots and roads. Layout follows the culture's `layout` in `data/cultures.json` and `map/sprawl.gd`, as today.
- Fill storehouses and granaries from the stockpiles in `GameState.stock`.
- Assign families to workplaces by the same priorities the numeric economy uses, so production matches the numbers on the first day.

### 3.3 Handoff: leaving (villagers to numbers)

- Count living people back into population.
- Write goods in storehouses back into stockpiles.
- Write finished buildings and plots back as buildings and slots. Unfinished projects become entries in `constructions` with their progress.
- Write approval back as the settlement's order and reputation inputs.
- Persistent details the numbers cannot hold (plot shapes, road lines, named villagers the player met) are stored in a per-settlement layout record in `GameState`, so the village looks the same next time.

### 3.4 What stays authoritative

- **`GameState` is always the truth.** The living village is a view and an editor of it, the same way the campaign UI is.
- Every change the player makes while the village is living is written to `GameState` as it happens or at handoff. Nothing lives only in scene nodes (save rule in `CLAUDE.md`).
- Saves work in both modes. A save made in a living village writes the numbers plus the layout record.

---

## 4. Why the empire still matters

The god cannot beat anyone in a fight, so the empire has to matter for other reasons.

- **One body, one place.** The world is huge. The god is in one place at a time.
- **Many threats at once.** Raids, rebellions, famines and wars happen across the realm in the same season. Vassals (`core/vassals.gd`), armies (`core/armies.gd`, `core/hosts.gd`) and governors handle what the god cannot reach.
- **Destruction has a price.** A punch that levels a building kills people, cuts taxes and moves the god's standing away from Loved. `core/reputation.gd` already tracks Loved / Feared / Neutral, and "Feared but weak" is already a bad state. For the god, the equivalent is a realm that fears him but does not work: people flee, vassals scheme, banners do not come.
- **The Loved path is harder.** Protecting without breaking means landing carefully, arriving in time and building well. That is the skill the game asks for.
- **Rivals and Ages are too big for one body.** Rival powers spread over many regions. The Ages (`docs/war-and-realm.md` §8) bring invasions and coalitions across whole frontiers. The god can win any battle he attends; he cannot attend them all.

---

## 5. Borrowed-mechanics reference

Copy these closely in later slices. Research the exact behavior in the source game before building.

### 5.1 Where Winds Meet

- **Context movement skills** (sprint, wall-running, climbing trigger from holding run or jump, or from touching terrain). How we use it: the god's default traversal; no extra buttons for climbing or wall runs.
- **Threefold Skywalk** (up to three jumps in the air) followed by a **Skywalk Dash**. How we use it: the early way to cross rooftops, gaps and valleys before full flight.
- **Wallstride.** How we use it: running up and along walls, towers and cliffs.
- **Fan Glider.** How we use it: long glides after a jump; the god's cloak or a winter wind in place of a fan.
- **Full flight unlocked by exploration progress.** How we use it: flight opens after discovering enough of the world, so the early game is on foot and the world feels big.
- **Dive-and-slam (Meteor Flight).** How we use it: the god's main attack from the air; huge, fast and destructive around the landing point.
- **Suspicion bar in towns** (NPCs fill a bar above their heads at reckless movement: crashing into people, disrupting their paths). How we use it: mapped to **settlement approval**; reckless movement through a living village lowers approval and, at scale, Loved reputation.

### 5.2 Manor Lords

- **Free roads that guide workers and deliveries.** How we use it: the player draws roads at no cost; villagers and carts follow them.
- **Burgage plots along roads, in irregular shapes, with backyard extensions** (garden, coop, workshop). How we use it: the main housing tool in living villages.
- **Three plot tiers with needs** (a well on a road connection, ale, clothing). How we use it: plots upgrade as needs are met; tiers feed the numeric settlement level.
- **Families move in only with a free plot and approval** (above about 75% fast, 50-75% slow; homelessness carries a lasting penalty). How we use it: growth in living villages; the same thresholds drive numeric growth far away.
- **Families assigned to workplaces by clicking the building.** How we use it: the workplace panel in build mode.
- **Unassigned families build, with one High-priority project at a time.** How we use it: construction labor in living villages; maps onto `core/construction.gd` progress.
- **A Development point per settlement level.** How we use it: settlement perks; can share data with the building chains in `data/buildings.json`.
- **Storehouse and granary.** How we use it: physical stockpiles in living villages; numeric stockpiles in `GameState.stock` elsewhere.
- **Fuel and food stockpiles for winter.** How we use it: winter needs; ties into `core/seasons.gd` winters.
- **Seasons** (spring planting, summer drought, autumn harvest, winter fuel and herbs). How we use it: the yearly rhythm of a living village, driven by the existing season data (`data/seasons.json`).
- **Regional Wealth separate from the lord's Treasury.** How we use it: each settlement keeps its own wealth; the god's treasury is the faction gold in `core/economy.gd`.
- **Trading posts.** How we use it: the living-village front end of `core/markets.gd`.
- **Influence to claim new regions.** How we use it: a peaceful way to expand, alongside conquest and fealty.

### 5.3 Bannerlord

- **A campaign map where you travel between settlements and enter them as scenes.** How we use it: the god travels the Varos map and drops into a settlement, which becomes living.
- **A clan that grows** (tiers, members, parties). How we use it: House Varn and its court (`core/court.gd`), with clan tier as a progression measure.
- **Fiefs: village, castle, town.** How we use it: settlement types in `provinces.json` mapped to these three; each grows differently.
- **Founding a kingdom.** How we use it: the step from ruling a town to ruling a realm; unlocks titles (`core/titles.gd`) and vassals.
- **Vassals.** How we use it: the existing fealty system in `core/vassals.gd`; vassals hold fiefs and raise armies.
- **Economy and diplomacy layers.** How we use it: already built in `core/economy.gd` and `core/diplomacy.gd`; keep them, present them the Bannerlord way where the god walks.

### 5.4 Total War: Warhammer III

- **Campaign UI.** How we use it: keep `ui/campaign_ui.gd` and the rest of `ui/` for the empire view.
- **End Turn button and notifications.** How we use it: the threat feed that tells the god where to go (`UiData.WARNINGS`).
- **Diplomacy.** How we use it: keep `ui/diplomacy_screen.gd` as is.
- **Strategic map.** How we use it: keep `ui/strategic_map.gd` as the highest zoom level of the rise.

---

## 6. Slice plan

Each slice answers one question. If the answer is no, stop and rethink before the next slice.

### Slice 1: Look test (built on `god-pivot`, see section 10)

- **Goal:** see whether the god, the village and the land look and feel right at character scale.
- **Built:** a separate "God Test" scene (main menu, `god/god_test.tscn`). Frosthold and about 1.2 km of countryside each way at character scale, from the culture kits and the landmark at 2x (section 8), on terrain taken from Varos. Edric at 2.7 m with Where Winds Meet traversal (walk, run, sprint, Threefold Skywalk and dash, wall-run, glide, flight, superhero landing). The rise from his shoulder to the campaign map and the strategic map in one motion, and the dive back (Meteor Flight) onto a ground slam. One-punch destruction (light and charged punches, the slam) on pre-fractured kit pieces with Jolt debris. 96 villagers on routines with a suspicion bar and a town approval number. A rendering and material pass, performance measurements and a scripted video.
- **Not built:** build mode, economy, saves, stamina or power limits, other settlements at character scale, links back into campaign state.
- **Question:** can this look and feel great in Godot with our assets?

### Slice 2: One living village with build mode

- **Goal:** one village that lives and that the player can build.
- **Built:** villagers and families, free roads, burgage plots, workplaces, storehouse and granary, one High-priority project, approval with the suspicion bar, seasons from existing data. Destruction with a cost in people and approval.
- **Not built:** other settlements, the campaign map, armies, the numeric handoff (the village is standalone).
- **Question:** is building and protecting one village fun when the player is all-powerful?

### Slice 3: Village to city

- **Goal:** the village grows into a town and then a city.
- **Built:** plot tiers and needs, Development points per level, more building types, the walls and landmark stages (`AssetManifest.instantiate_settlement`), threats that grow with the city.
- **Not built:** travel to other settlements, the empire layer.
- **Question:** does growth hold interest for hours, and does the city still read well at character scale?

### Slice 4: Connect to the world

- **Goal:** fly between settlements on Varos and switch settlements between living and numeric.
- **Built:** the rise from character scale to the campaign map as one motion, flight across the land, the handoff in section 3, numeric simulation for every settlement the god is not in, time passing while the god acts.
- **Not built:** vassals, diplomacy and armies in the god view (they keep running as they do now).
- **Question:** does the world feel vast and alive, and does the handoff hold up (no visible jumps in numbers)? Answers the real-time question in section 7.2.

### Slice 5: The empire layer

- **Goal:** the existing strategy systems run the far-away half of the game.
- **Built:** the empire view from the current campaign UI, vassals, governors, armies, diplomacy, threats in many places, Ages, reputation reacting to the god's deeds.
- **Not built:** new strategy systems beyond what the borrowed games already have.
- **Question:** does the empire matter when the god can win any fight in person?

---

## 7. What carries over

| System | File(s) | Status | Notes |
|---|---|---|---|
| Campaign state and saves | `core/game_state.gd`, `core/save_system.gd`, `core/save_codec.gd` | Carries over, adapts | Stays authoritative. Adds the god's position and state, per-settlement layout records and living-village data. Schema bump with a migration. |
| Economy, resources, buildings, construction | `core/economy.gd`, `core/resources.gd`, `core/buildings.gd`, `core/construction.gd`, `data/economy.json`, `data/buildings.json`, `data/resources.json` | Carries over as-is (numeric mode) | The far-away simulation. Living villages must produce matching numbers. Plots, tiers and roads are new. |
| Armies and movement | `core/armies.gd`, `core/movement.gd`, `core/path_hierarchy.gd`, `data/movement.json` | Carries over, adapts | Armies still march on the campaign map. The god does not use army movement. |
| Battles | `core/battles.gd`, `core/battle_sim.gd`, `core/battle_report.gd`, deployment files | Carries over; open question | Battles were "complete for V1". Simulated battles still resolve fights the god is not at. Whether and how the god joins a battle is open. |
| Campaign AI | `core/ai.gd`, `core/ai_realm.gd`, `data/ai.json` | Carries over, adapts | Rivals and vassals keep playing. The AI must learn that the god's presence changes a region's danger. |
| Court, reputation, diplomacy, vassals, hosts, titles | `core/court.gd`, `core/reputation.gd`, `core/diplomacy.gd`, `core/vassals.gd`, `core/hosts.gd`, `core/titles.gd`, `core/realm_standing.gd` | Carries over, adapts | The heart of "what kind of ruler you are". Reputation gains inputs from the god's deeds (destruction, rescues, reckless movement). Edric's immortality fits the level-20 rule. |
| Seasons, markets, supply | `core/seasons.gd`, `core/markets.gd`, `core/supply.gd` | Carries over as-is | Seasons drive the living village's year too. Markets become trading posts in living villages. |
| Map pipeline and Varos | `map/pipeline.gd`, `map/sketch.gd`, `map/validator.gd`, `data/maps/varos/` | Carries over, adapts | Varos stays the world. Character-scale terrain around the god is new and must line up with it (section 8). World scale for travel is open. |
| Culture kits and landmarks | `visuals/kits/cultures/culture_kit.gd`, `visuals/landmarks/`, `map/sprawl.gd`, `data/cultures.json` | Carries over, adapts | Built at campaign kit scale; the god test builds them at 2x. Interiors and walkable streets are new. |
| Campaign camera and strategic map | `core/camera_rig.gd`, `map/map_view.gd`, `ui/strategic_map.gd`, `ui/minimap.gd` | Adapts | The top of the rise. The camera needs a continuous path from shoulder height to the strategic map. |
| UI layer | `ui/`, `core/ui_data.gd` | Carries over, adapts | The empire view is the current campaign UI. Build mode and the on-foot HUD are new and also read through `UiData`. |
| Turn loop | `core/turn_loop.gd` | Open | Depends on section 7.2. The End Turn sequence can stay as the yearly or seasonal processing step. |
| Chronicle | `core/chronicle.gd` | Carries over as-is | The Grey Scribes record the god's deeds. |
| Asset manifest | `core/asset_manifest.gd`, `data/asset_manifest.json` | Carries over as-is | The god and villagers load through it like every other visual. |

### 7.1 What is replaced

- The player as a faction leader who never appears in person. The player is now a body in the world.
- Battles as the main way the player fights. The god is the main way; battles are what happens where he is not.

### 7.2 Turn-based to real-time **(Open, for slice 4)**

The strategy game is turn-based (one turn is one year). The god acts in real time. Options:

| Option | How it works | For | Against |
|---|---|---|---|
| **A. Turns for the empire, time passes locally** | The god acts in real time; the empire advances only at End Turn. Local actions within a turn change local numbers. | Keeps `core/turn_loop.gd` and every system as is. | Real-time village seasons and a yearly turn do not match; feels like two games. |
| **B. Real-time tick** | The world runs continuously. One turn = N in-game days, processed automatically every N days. | One clock for everything; threats appear while the god travels. | Every yearly system needs retuning to a shorter step. Turns become invisible. |
| **C. Pause on event** (CK3, Bannerlord) | Real-time as in B, but the game pauses for decisions, offers and major threats. The player can pause at will. | Proven in CK3 and Bannerlord. Keeps decisions calm. | Needs a speed control and an event queue. |

**Recommendation (not a decision):** option C. Run the world on one real-time clock, process the existing turn systems every N days (shortening the turn from a year to a season fits `core/seasons.gd`), and pause on events the way CK3 and Bannerlord do. This follows the rule in section 1.2: a known game already solved it. The owner decides in slice 4.

---

## 8. Scale (chosen for the look test; the owner may change it)

### 8.1 Character scale (the look test)

- 1 Godot unit = 1 m.
- A person is about 1.8 m tall. Doors are about 2.2 m tall.
- The culture kits were built at campaign kit scale: a kit door is 1.1 m and a kit storey is 1.25 m. The god test builds them at **2x**: door 2.2 m, storey 2.5 m.
- The god, **Edric Varn**, is **1.5x human height**: about **2.7 m**.
- Why 2x: it is the smallest whole factor that brings the kit's doors (1.1 m) and storeys (1.25 m) to human size, and it keeps every kit piece and landmark usable unchanged at both scales. The rule lives in `data/god_test.json` ("scale").

### 8.2 Campaign scale

- The campaign map (`map/map_view.gd`, Varos) is drawn at **2x** around the character-scale area, so Frosthold lines up and the rise to the empire view is one continuous motion.
- The strategy map compresses distances: settlements are close together for readability. Travel distances in the god game are therefore **open** for slice 4.

| Item | Character scale | Campaign kit scale |
|---|---|---|
| Person | 1.8 m | (oversized figures, per `CLAUDE.md`) |
| Door | 2.2 m | 1.1 m |
| Storey | 2.5 m | 1.25 m |
| Edric Varn | 2.7 m | n/a |
| Culture kits | built at 2x | built at 1x |
| Varos map | drawn at 2x around the god | 14,080 × 11,520 m at 1x |

---

## 9. Open questions

- Does the game stay turn-based, become real-time, or use real-time with pause on events (section 7.2)?
- How large is the world, and how long should flying from Frosthold to Caeloth take, given that Varos compresses distances?
- How much destruction does the reputation system tolerate before Loved turns to Feared, and Feared to Feared but weak?
- Do battles stay simulated, can the god join them, and what happens to a battle he joins?
- What are the Ages mechanically when the player is a god: the same triggers as `docs/war-and-realm.md` §8, or new ones?
- Does the god's power have limits (stamina, cooldowns, a cost per slam), or is it unlimited? The look test has none.
- Is Edric the only playable god, or can the player pick another founder (Varrenus, the Aurekids)?
- Does the god age, and what happens to House Varn's succession rules when the ruler is immortal from the start?
- Do villagers in a living village have names and stories, and how many are remembered after the handoff?
- Which existing strategy features (agents, schemes, religion) still make sense in a god game?

---

## 10. Look test results (slice 1, 2026-10-10)

Built on `god-pivot`; nothing on `main` changed. Main menu **God Test**, or `runtime\Godot.exe --path . god/god_test.tscn`. Controls are on screen (H hides them). Video and key frames: `captures/god_test/` (local only, git-ignored).

### 10.1 What was built

| Part | Files | Notes |
|---|---|---|
| Character-scale area | `god/terrain.gd`, `god/terrain.gdshader` | 2.4 km × 2.4 km at 2 m cells around Frosthold. Base heights from Varos at 2x, plus relief and a castle rise that fade out toward the edge. Three LOD grids per 150 m chunk, one HeightMapShape3D. A splat image (road mud, bare ground, fields, paving) painted by the town. |
| Frosthold | `god/town.gd`, `god/mesh_kit.gd` | The landmark's castle (`visuals/landmarks/frosthold_visual.gd`, stage 2 plus the stage-3 spires) and 198 culture-kit houses on burgage-style plots along 7 roads, a market with a well and stalls, a church, farmsteads with strip fields, fenced backyards. Kits built at 2x as about 36,500 pre-fractured chunks in 284 buildings. |
| Edric Varn | `god/god_model.gd`, `god/god_player.gd`, `god/pose_mod.gd`, `god/god_body.gdshader` | 2.7 m. Walk, run, sprint, jump, Threefold Skywalk and dash, wall-run, glide, flight with flight sprint and sonic boom, rapid climb, hard landings. Spring-arm camera behind the shoulder; FOV and speed lines with speed. |
| Destruction | `god/town.gd`, `god/debris.gd`, `god/vfx.gd` | Light punch, charged punch (charge-up swirl, body glow, time slow, 38-72 m cone), dive slam. Jolt debris (live cap 320; sleeping debris freezes into rubble; past 2,600 pieces the oldest rubble sinks away), rubble heaps, dust, chips, splinters, embers, fires, rings, craters. R resets. |
| Townsfolk | `god/villagers.gd` | 96 peasants (the CC0 Quaternius soldier model) on road routines: home, well, market, fields, carrying buckets. They stare when the god lands, flee from destruction, and get knocked down when he crashes through them. Suspicion bars and town approval. The Mixamo walk is retargeted to their rig at start. |
| Rise and dive | `god/empire.gd`, `god/clouds.gdshader` | Flight camera, then `core/camera_rig.gd`'s campaign zoom on Varos (drawn at 2x around the area through a hole in `map/terrain_view.gdshader`), then `ui/strategic_map.gd`. A cloud deck hides the swap between the two worlds. Picking a place dives there (Meteor Flight); outside the area the dive is refused ("not built yet"). |
| Look | `god/surface.gdshader`, `god/materials.gd`, `god/foliage.gd`, `god/fir_builder.gd`, `god/sky.gdshader`, `god/post.gdshader` | CC0 PBR sets, trim on kit pieces, firs, grass, rocks, props, a sky with clouds, volumetric fog, SSAO, TAA, a grimdark grade. |
| Showcase and measurement | `god/showcase.gd`, `god/frame_probe.gd`, `scripts/god_bench.sh` | `--showcase` (with `--write-movie` for the video), `--perf=<file>`, `--bench=<label>`, `--shot` and `--view`, `--flat`. |

### 10.2 Performance (1920 × 1061 window, RTX 4060, Windows 11, vsync off)

From the scripted showcase run in real time (`--perf`); wall-clock frame times; the first 2 s are warm-up and are left out.

| Segment | Avg frame | Worst frame | Frames > 33 ms | GPU | Render CPU | Draw calls (max) | Triangles (max) | VRAM |
|---|---|---|---|---|---|---|---|---|
| Ground (town, villagers) | 11.0 ms | 30.0 ms | 0 | 7.4 ms | 1.9 ms | 4,050 | 4.3 M | 1,185 MB |
| Flight (low, fast) | 8.2 ms | 13.2 ms | 0 | 5.7 ms | 0.8 ms | 3,202 | 4.0 M | 1,162 MB |
| Transition (rise to the campaign map) | 7.4 ms | 10.5 ms | 0 | 4.6 ms | 0.6 ms | 2,118 | 1.2 M | 1,162 MB |
| Strategic map | 5.5 ms | 15.6 ms | 0 | 4.6 ms | 0.9 ms | 1,581 | 0.9 M | 1,180 MB |
| Dive and slam | 12.4 ms | 39.9 ms (the slam frame) | 1 | 9.4 ms | 2.0 ms | 4,255 | 4.4 M | 1,185 MB |
| Charged punch and aftermath | 12.9 ms | 25.7 ms | 0 | 8.9 ms | 2.4 ms | 4,091 | 3.3 M | 1,186 MB |
| **The punch's own frame** | | **54.3 ms** | | | | | | |

Fixed street view (`--bench`, the god's start position): 102 fps, 9.8 ms frame, 7.6 ms GPU.

Feature costs at that view (measured before the foliage fix below, GPU per frame): SSAO 1.5 ms (kept); SSIL +0.9 ms, and SDFGI +1.3 ms with +400 MB VRAM (both off: little visible gain on a snowy, open, sunlit scene); FSR 2 at 0.77 saved only about 1 ms because the cost was geometry, not pixels (off; TAA is the anti-aliasing).

What it took to get there: rocks, stumps and props were each one MultiMesh over the whole area, so they never culled or dropped LOD, and cost 9 ms of a 15 ms GPU frame until they were chunked with visibility ranges. The campaign map re-streaming its trees and settlements (`map/map_view.gd update`) on the way up caused 100-300 ms frames until it was limited to long pans.

Over target: the slam frame (39.9 ms: breaking about 1,250 chunks and collapsing 8 buildings in one frame). Loading takes about 35 s (about half of it the strategic map's one-time parchment bake, the same cost the campaign pays).

### 10.3 Animations

| State | Source |
|---|---|
| Walk, run, sprint | The Mixamo walk; run and sprint are the walk sped up, with a forward lean and arms swept back (procedural) |
| Idle | The Mixamo landing clip's last frame, held, with breathing (no idle clip) |
| Jump | `wh.fbx` (a crouch and leap) |
| Fall | Mixamo falling idle |
| Hard landing | Mixamo falling-to-landing (no superhero landing; a crouch is added) |
| Flight | Mixamo flying, the body pitched along the flight path at speed, right fist forward (procedural) |
| Punch | Mixamo punching; the charge holds its wind-up frame with a spine twist and a crouch (procedural) |
| Wall-run, glide, dash, dive | Procedural poses over existing clips |

**Missing clips** (worth getting next): idle, run, sprint, superhero landing, wall-run (vertical and sideways), glide, air dash, a heavy wind-up and heavy punch, a ground slam, a flinch or stagger. The model has no texture (the clips carry only the mesh), so `god/god_body.gdshader` shades it as dark steel.

### 10.4 What works

- The traversal reads like Where Winds Meet: sprinting into a house runs up its wall onto the roof; Threefold Skywalk into flight; flight sprint with the boom, speed lines and widening FOV.
- The rise is one motion: shoulder camera, the land falling away, the cloud deck, the campaign map's zoom, the strategic map, and back down as a meteor onto Frosthold. The dive's view of Frosthold from a few hundred metres up is the strongest image in the test: the strategy map coming to life.
- Destruction at One Punch Man scale works and holds frame rate: a charged punch breaks about 1,000 pieces and brings down 6 buildings in a 72 m cone; collapsed buildings leave rubble heaps, fires and smoke; approval falls and the townsfolk flee with suspicion bars filling.
- From flight height and above (more than about 30 m), the snowy town, the firs and the long winter shadows come close to the Frosthold board.

### 10.5 What looks bad up close, and why

- **Buildings are boxes with good textures.** Every kit piece is a box, prism or cylinder. CC0 textures and the trim pass (barge boards, ridge beams, frames and sills, quoins, arrow slits) lifted them from flat colour to a tidy model village, but at 5 m there are no bevels, no sagging roof lines, no eave depth, no beam ends, no real doors or windows. That is geometry, not material.
- **The castle is the weakest part.** The landmark was built to read at campaign distance; at character scale its keep is a 28 m blank block with a roof.
- **Edric has no texture,** and several moves use stand-in poses.
- **Firs hold up from about 30 m out; close up** their branch cards read as flat cut-outs. Grass tufts are simple.
- **Rubble** is the buildings' own pieces heaped on a mound: rubble from a distance, tumbled boxes close up.
- **The townsfolk** are the stylised CC0 Quaternius model: fine at 20 m, plain up close.
- **From the empire view,** the cloud deck that hides the swap is heavy between 1 and 3 km up.

### 10.6 Verdict

Godot is not the limit: rendering, physics, destruction, crowds and the seamless rise run at 90-100 fps at 1080p on a mid-range GPU, with headroom. **The limit is the art.** Procedural kit shapes with good textures give a clean, toy-like look, not grimdark painterly realism, and no amount of material work fixes that at 5 m. To make ground level look great:

1. **Real modular building art** (bevelled walls, beams, roof tiles with thickness, windows, doors, trims) in place of the kit shapes, built to work at both scales. The destruction system already breaks whatever pieces it is given. This is the biggest gain.
2. **A textured, properly animated god** (the missing clips above) and better townsfolk.
3. **Better foliage:** game-ready firs with LODs, real grass and ground cover.
4. Or **lean into a stylised art style** (painterly textures, softer shapes, a stronger grade) where the kit shapes are a strength rather than a weakness. Cheaper, but a different look from the reference boards.

Recommendation: keep the systems, and try one hand-made or CC0 modular house and one textured god model in this scene before choosing between options 1-3 and option 4.
