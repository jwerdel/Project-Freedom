# TW:WH3 UI parity spec

Status: written in Phase A of the parity pass (2026-10-02); section 12 gives each item's status after Phases B-C. It applies the constitution's TW:WH3 parity principle: everything the player touches matches Total War: Warhammer III; only game rules differ.

This is a checklist of each interaction and UI element. For each it gives how TW:WH3 does it (with source and confidence), how Project Freedom does it now, and the gap. The **Status** column is filled in Phase D.

## Sources and confidence

- **Official:** the Xbox Wire hotkey list (Sega/CA, Feb 2022: https://news.xbox.com/en-us/2022/02/16/total-war-warhammer-3-hot-keys-revealed/); Total War Academy (https://academy.totalwar.com/campaign-keyboard-and-mouse-controls/ and related pages; some are written for WH2); WH3 patch notes (Update 3.0, 4.0); CA's WH3 scripting docs for end-turn warnings (https://chadvandy.github.io/tw_modding_resources/WH3/campaign/campaign_ui_manager.html); a CA developer post on Backspace (https://community.creative-assembly.com/total-war/total-war-warhammer/bugs/5698).
- **Guides and community:** gamepressure's WH3 guide pages and Steam threads, cited per row below.
- **Confidence:**
  - **C:** confirmed by an authoritative source or several sources
  - **S:** a single community or guide source
  - **U:** uncertain or conflicting
  - **?:** unknown (no written source found; needs in-game observation)
- **Rule:** where TW:WH3 is unknown, we do not invent a convention. The row is left open until verified. The exceptions are explicit owner instructions, marked "owner".

## 1. Selection

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| S1 | Left-click selects own army, hero or settlement | C | Same (click under 6 px of drag) | none |
| S2 | Left-click on empty terrain cancels the selection | C (Xbox Wire) | Clicking empty ground does nothing | **Gap:** deselect on an empty left-click |
| S3 | Selecting on the map does not move or zoom the camera | ? (no source says it does; owner requires it) | `select_army` flies the camera to the army and zooms to 26 m | **Gap (owner):** selection never moves or zooms the camera |
| S4 | Double-click | ? | Nothing | Open: leave as is until verified |
| S5 | Clicking an army or settlement in a list or panel moves the camera to it | C (Academy); whether it zooms is ? | Minimap click pans; army cycling zooms to 26 m | **Gap (owner):** pan at the current zoom |
| S6 | Esc opens the game menu | C (Academy); whether Esc closes panels first is U | Esc closes the topmost panel first, then opens the pause menu | Different by design (approved earlier) |

## 2. Army movement

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| M1 | Right-click on a destination or target orders the move or attack | C | Same (on release) | none |
| M2 | **Hold right-click** shows a preview arrow without committing; releasing commits | S (several Steam threads) | The preview follows the mouse whenever an army is selected (no button held); right-click release orders | **Gap:** preview only while right-click is held; release commits; Esc during the hold cancels |
| M3 | Path colours: green = this turn; later turns another colour (red reported for "beyond this turn"); the full multi-turn palette is ? | C for green, U after | Green / yellow / orange / red per turn | Keep: green this turn, then distinct colours per later turn |
| M4 | No numbers on the arrow | U (nothing describes numbers) and owner | Turn-number markers ("2", "3") on the path; a hover tooltip with "Move: 3 turns"; the blocked marker shows the reason as map text | **Gap (owner):** no numbers or text on the map or path. Remove turn numbers; blocked = a red cross marker only; the reason stays in the cursor tooltip |
| M5 | Movement range = a highlighted boundary (yellow in WH2 Academy; green per one WH3 guide) | C boundary, U colour | A light-blue translucent fill with a pale edge | **Gap:** a boundary line (gold-yellow, WH2 Academy colour) with almost no fill |
| M6 | Attack cursor over enemies | ? | None | Open: needs in-game observation |
| M7 | Movement bar on the army/lord panel; the part a preview would spend shown green (red if out of range) | C bar; WH3 shows point numbers in a tooltip | Bar plus text "1 / 60" | **Gap (owner): no numbers.** Bar only; the preview spend is shown on the bar in green |
| M8 | Backspace = cancel order | C (CA developer) | Backspace cancels the **commander army's** order whatever is selected (bug) | **Gap:** cancel the selected army's order |
| M9 | Multi-turn orders continue automatically; how the remaining path is drawn is ? | C continue, ? drawing | A dim path with turn numbers | Remove the numbers (owner); keep the dim coloured path |
| M10 | Zone of control (red/pink boundary) | C (WH2), likely WH3 | No zone of control | Not yet possible: no such rule (constitution open item) |

## 3. Camera

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| C1 | WASD pan (Shift = faster) | C | WASD and arrows pan; no Shift boost | **Gap:** Shift = faster pan |
| C2 | **Q / E rotate** | C | No rotate keys | **Gap:** add Q/E |
| C3 | Mouse wheel zoom | C | Same | none |
| C4 | Middle-drag: the Academy says it moves (pans) the camera; other sources say rotate | U | Middle-drag pans | **Owner:** middle-drag orbits (yaw and tilt) |
| C5 | Right-drag does not move the camera (hold right-click is the path preview) | U, consistent | Right-drag orbits | **Gap:** right-drag no longer orbits |
| C6 | Edge scroll | ? | None | Open |
| C7 | Home = pan to capital; End = default rotation | C | Home = reset to the overview; no End | **Gap:** Home pans to the capital, End resets rotation |
| C8 | Tilt flattens toward top-down as the camera rises (minimum angle about 35°, data-driven) | S (modder, specific) | Fixed pitch, changed only by right-drag | **Gap:** tilt follows zoom (steeper when high, about 35° when low); middle-drag adds an offset |
| C9 | Zooming far out switches to the parchment strategic map; Tab toggles it | C | Zoom out is clamped; Tab hides the interface | Not yet possible (no strategic map). Tab keeps "hide UI" until one exists |
| C10 | `,` / `.` = previous / next army (settlement when a settlement is selected) | S (community, WH1–WH3) | C = next army | **Gap:** `,` / `.` cycle armies (and settlements); camera pans at the current zoom (owner) |
| C11 | Clicking an end-turn notification flies the camera close to the item | S | n/a | **Owner:** pan at the current zoom |
| C12 | Hold Space = campaign overlays (settlement info at any zoom) | C | Space = pause traffic (debug key) | **Gap:** hold Space shows settlement banners at any zoom; the debug traffic pause moves to F8 |

## 4. Army panel and recruitment

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| A1 | The lord's card and details are at the left, unit cards along the bottom, the movement bar on the lord panel | C | Header (name, movement box, buttons) above a card row; the general is the first card | Close enough in structure. Movement bar without numbers (M7) |
| A2 | **Recruitment buttons below the unit cards** open the recruitment panel (global and local tabs) | C | A "Recruit" button in the header opens a large tiled window over the map | **Gap:** a recruit button at the end of the card row opens a **recruitment drawer**: a strip of unit cards above the army panel. Each shows its turns above the portrait and its cost and upkeep. Click a card to recruit |
| A3 | Local recruitment = units allowed by your buildings in the **province the army stands in**; empty when not in controlled territory; global pool costs more and takes longer | C local and global; the exact territory rule is U | Required being inside or within 12 m of an own settlement; units from that one settlement | **Gap (owner rule, Phase B):** any own region of a province; units from your buildings in the province; reason shown when unavailable. Global recruitment: not yet (constitution open item) |
| A4 | Recruitment capacity (slots per province) | C | No capacity | Different by design for now (constitution open: recruitment slots) |
| A5 | Recruiting locks the lord's movement | C | Movement not locked | **Deliberate difference (owner, 2026-10-02):** recruiting does not lock movement |
| A6 | Queued units shown on cards with a banner (green / blue / orange in older text) | U for WH3 | Veiled cards with turns, appended after all units (they fall off-screen in a full army) | **Owner:** greyed cards with a turn counter, always visible (cards shrink to fit up to 20); click to cancel |
| A7 | Cancel a queued unit | ? | Click the queued card (full refund) | Keep (owner) |
| A8 | Unit card hover tooltip (sticky, inspectable tooltips since Update 3.0) | C | Plain tooltip: name, men, upkeep, description | Partial. Sticky tooltips need a custom tooltip system: later |
| A9 | Right-click on a unit card | ? | Nothing | Open |
| A10 | Ctrl+P = disband the selection; Ctrl+M = auto-merge | C | Disband button only; no merging | **Gap:** Ctrl+P disbands the selected unit. Merging: not yet possible (no merge system) |
| A11 | Key 4 = show recruitment | C | No key | **Gap:** 4 opens the recruitment drawer for the selected army |

## 5. Settlement and province panel

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| P1 | Selecting a settlement opens the province panel: stats on the left, every settlement of the province with building slots in the centre | C / S | Same structure (province stats left, settlement tabs and slot cards bottom-centre) | none |
| P2 | Arrows beside the settlement name cycle settlements | S | Tabs | Close; `,` / `.` cycle settlements when one is selected (C10) |
| P3 | Empty slot opens the building browser; key 3 = building browser | C | Clicking a slot opens the browser; no key | **Gap:** 3 opens the browser on the first empty slot of the selected settlement |
| P4 | 1 = overview, 2 = garrison | C | none | Not yet possible: no separate overview or garrison panels |

## 6. Top bar, menus and events

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| T1 | Top centre: treasury, projected income, faction resources, with tooltips | C | Treasury, income, population, year, with a ledger tooltip | none |
| T2 | Top left: game menu, advisor, help, unit browser, camera settings. Mission, diplomacy and technology buttons sit **around the End Turn button** in WH3 (top-left in WH2) | S (gamepressure, Steam) | Round placeholder buttons top-left (faction, diplomacy, technology, lords, finance, objectives) plus the chronicle | **Owner decision needed:** the constitution's UI direction names "round menu buttons top-left". Moving the panel buttons to the End Turn cluster follows WH3; layout unchanged until decided |
| T3 | Top right: tactical-map toggle, dropdown lists (events, lords and heroes, provinces, factions), faction summary | S | Minimap top-right, Event Messages list on the right (constitution layout) | Same decision as T2 |
| T4 | Dilemmas and incidents as pop-ups; events list | C | Toasts plus the Event Messages list | Not yet possible: no event/dilemma system |
| T5 | `-` = finance, `=` = clan | C | none | Not yet possible: no finance or clan panels |

## 7. End Turn and warnings

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| E1 | Enter = end turn; Shift+Enter = end turn skipping warnings | C | Button only | **Gap:** add both keys |
| E2 | While warnings are pending, the End Turn button acts as "jump to notification": clicking it moves the camera to the item and selects it, then loads the next. A label shows the warning type; small arrows cycle its items; skipping moves to the next category; then End Turn | C (community, several) | No warnings | **Gap:** implement for the systems that exist (E3) |
| E3 | Warning types (CA): bankrupt (low funds), tech, edict, character, settlement upgrade, siege, army morale, repair, **construction (building available)**, office, **army_ap (army can still move)**, hero_ap, rebellion, garrison_ap | C | n/a | Implement **construction available**, **army can still move** and **low funds / in debt**. The rest are not yet possible (no such systems) |
| E4 | A gear next to End Turn configures which warnings show | C | n/a | **Gap:** settings checkboxes per warning type |
| E5 | H = jump to the end-turn notification | C | n/a | **Gap:** add H |
| E6 | AI turn: top-centre controls (pause, `>`, `>>` skip) and per-faction camera tracking settings | C (community) | Follow AI armies (setting), Space/Esc skip | Partial. Add a top-centre "Enemy movements" bar with a skip (`>>`) button during the follow; per-faction tracking settings later |

## 8. Tooltips

| # | TW:WH3 | Conf. | Ours now | Gap and plan |
|---|---|---|---|---|
| H1 | Rich tooltips with a title, description and effects; sticky (after a delay they pin and can be inspected); options for delay, pin-to-element and auto-stick | C (patch notes) | Godot tooltips styled as parchment; multi-line text, no title styling | **Gap (partial now):** the first line of every tooltip is styled as a title (bold); unify tooltip text style. Sticky or inspectable tooltips: later (custom tooltip system) |
| H2 | Hover on map settlements and armies shows info | ? (contents unverified) | Name, faction, province / general, army, units | Keep |
| H3 | Help links in orange text | C (WH2) | none | Not yet (no help pages) |

## 9. Hotkeys (TW:WH3 defaults that apply)

| Key | TW:WH3 | Ours after Phase C |
|---|---|---|
| WASD (+Shift) | pan (faster) | same |
| Q / E | rotate | same |
| Wheel | zoom | zoom toward the cursor; past the farthest 3D zoom it opens the strategic map; on the strategic map, scrolling in returns to the 3D map at its highest zoom (Ctrl+wheel zooms the parchment) |
| Home / End | pan to capital / default rotation | same; Home is also the "Go to capital" button beside the minimap |
| Shift+Home | (none; camera-mod convenience) | **Frame my realm** (owner 2026-10-06): fits the camera to all your land and armies from nearly straight above; also a button beside the minimap |
| `,` / `.` | previous / next army or settlement | same |
| Backspace | cancel order | same (selected army) |
| Enter / Shift+Enter | end turn / skip warnings | same |
| H | jump to the end-turn notification | same |
| Ctrl+S / Ctrl+L | quicksave / quickload | same (already) |
| Ctrl+P | disband selection | same (selected unit) |
| 3 / 4 | building browser / recruitment | same |
| Hold Space | overlays | settlement banners at any zoom |
| Tab | strategic map | same |
| Esc | game menu | closes the top panel, then the pause menu (by design) |
| F12 | (screenshot, Steam) | screenshot |

Debug keys (ours, behind the Settings switch): F5, F6, F7, L, and F8 (traffic pause, moved from Space).

## 10. Owner decisions recorded here

- No numbers anywhere on the map or path; the movement bar has no numbers (M4, M7, M9).
- Selecting never moves or zooms the camera; cycling and notification jumps pan at the current zoom (S3, S5, C10, C11).
- Middle-drag orbits; right-drag does nothing (hold right-click is the preview) (C4, C5).
- Recruitment rule (Phase B): any own region of a province; units from that province's buildings; queued units greyed with a turn counter, click to cancel (A3, A6, A7).
- Turn start (owner, 2026-10-05): a clear "Your turn / Year X" announcement when control returns, on top of the TW behaviour (§15).
- Attack flow (owner, 2026-10-05): a war declaration window first, then the lord marches over as many turns as needed; the pre-battle panel opens only on arrival or when the target is in attack range this turn (§15).
- Lords & Heroes window (owner, 2026-10-05): also opened from a magnifying-glass button on each row of the top-bar Lords list (TW's list only selects and pans). Skills are a placeholder tree (`data/skills.json`, rows Command / Logistics / Conquest, one point per level, no gameplay effect yet); auto-allocate is per general and always on for AI generals (§15).
- Diplomacy screen layout (owner, 2026-10-05): TW:WH3's three columns (your faction left, known factions with Quick Deal / Negotiate / War Coordination centre, the selected faction mirrored right). This replaces the column layout sketched in docs/diplomacy-design.md §15 for the screen's frame; the proposal builder, reasons and acceptance bar from that section arrive with the diplomacy system. Wired now: declaring war (with a confirmation), war/peace status, strength and tendencies; attitude ("Indifferent"), reliability and deal chances are placeholders; treaties are greyed "Coming later".
- Strategic map zoom (2026-10-05, ours; changed 2026-10-06): scrolling in returns to the 3D map at its highest zoom, centred on the cursor (owner); Ctrl+wheel zooms the parchment map (up to 3×, around the cursor; right/middle drag pans). Zoomed out it names provinces and the larger settlements; zoomed in, every settlement. The painted look follows `docs/reference/world/varos_map.jpg` (palette and style only).
- Lord figure (2026-10-05): the rigged Blender general (`art_source/general_aurek`, exported to `assets/models/general_aurek.glb`) replaces the procedural figure, at the same campaign size, with the faction colours on its cape, tabard and shield and the faction standard beside it. It has no walk animation yet.

## 11. Open: needs in-game observation, or an owner decision

- Double-click behaviour (S4); attack cursor (M6); edge scroll (C6); right-click on a unit card (A9).
- The path colours after the first turn and for blocked destinations (M3).
- Range boundary colour (M5: we use the WH2 Academy's yellow-gold).
- Whether recruiting should lock the lord's movement (A5: a rule, not UI).
- **Layout (T2/T3):** move the mission, diplomacy and technology buttons to the End Turn cluster and use top-right dropdowns (WH3), or keep the constitution's described layout.

## 12. Status (parity pass, Phases B and C; updated after the layout pass, 2026-10-02)

Legend:
- **Matched:** behaves as TW:WH3, or as the owner's explicit instruction where TW:WH3 is unknown.
- **By design:** deliberately different (an owner or constitution decision).
- **Not yet possible:** the underlying system doesn't exist.
- **Open:** TW:WH3 behaviour unverified.

| ID | Item | Status | Notes |
|---|---|---|---|
| S1 | Left-click select | Matched | |
| S2 | Left-click empty ground deselects | Matched | |
| S3 | Selection never moves or zooms the camera | Matched (owner) | |
| S4 | Double-click | Open | |
| S5 | List and panel jumps pan at the current zoom | Matched (owner) | |
| S6 | Esc | By design | Closes the top panel first, then pause |
| M1 | Right-click order | Matched | |
| M2 | Hold right-click preview, release commits, Esc or left-click cancels | Matched | |
| M3 | Path colours (green this turn) | Matched | Later-turn colours are ours: yellow, orange, red |
| M4 | No numbers on the map or path | Matched (owner) | Plain discs at turn ends; a blocked destination is a red X, with the reason in the cursor tooltip |
| M5 | Range boundary | Matched | Gold-yellow line (WH2 Academy colour; WH3 colour unverified) |
| M6 | Attack cursor | Open | The preview tooltip says "Attack Greyhaven" meanwhile |
| M7 | Movement bar without numbers, with the preview spend | Matched (owner) | |
| M8 | Backspace cancels the selected army's order | Matched | Fixed: it used to cancel the commander army whatever was selected |
| M9 | Standing orders without numbers | Matched | |
| M10 | Zone of control | Not yet possible | |
| C1 | WASD pan, Shift faster | Matched | |
| C2 | Q / E rotate | Matched | |
| C3 | Wheel zoom | Matched | |
| C4 | Middle-drag | By design (owner) | Orbits |
| C5 | Right-drag | Matched | No camera move (it is the preview) |
| C6 | Edge scroll | Matched (owner 2026-10-06) | The camera mods' edge pan, on by default (Settings), speed scaling with height like WASD; never in captures |
| C7 | Home pans to the capital, End resets rotation | Matched | |
| C8 | Tilt follows zoom | Matched (owner 2026-10-06) | One smooth curve over a continuous zoom from close to a high overview (TW:WH3 plus its camera mods): about 40° close, 60° mid, 87° at the top (core/camera_rig.gd, data/campaign_view.json "camera"); the farthest 3D zoom is half the map's longer side (Varos: about 7 km up) |
| C9 | Strategic map: Tab or zooming out | Matched | Only scrolling out past the farthest 3D zoom opens it; scrolling in on it returns to the 3D map at the highest zoom, centred on the cursor (2026-10-06). Map modes: Political and Diplomacy (Religion, Culture, Resources ready; Culture, order, development and terrain kept). Painted parchment map (relief, mountain and forest glyphs, rivers, inked coasts, watercolour territory, owner borders), settlement and army icons; the wheel zooms it (labels thin out zoomed out), click or scroll in past the closest zoom returns there (L11) |
| C10 | `,` / `.` cycle armies or settlements at the current zoom | Matched | C removed |
| C11 | Notification jumps | Matched (owner) | Pan at the current zoom |
| C12 | Hold Space for overlays | Matched | Settlement banners at any zoom; debug traffic pause moved to F8 |
| A1 | Army panel structure | Matched (close) | Three parts (L7): lord card, greyed equipment, traits and stances, movement; recruit buttons above the cards; upkeep, replenishment, greyed stance (right column ours) |
| A2 | Recruit buttons below the cards open the recruitment panel above the army | Matched (owner) | Local and Global buttons below the cards (section 14); the panel stays open across clicks and closes with Close, its button again, Esc or deselection |
| A3 | Local and global recruitment | Matched | Local: the province's buildings, own territory. Global: anywhere, the whole realm's units, 2x cost and 2x turns (placeholders) |
| A4 | Recruitment capacity | Matched | 3 per lord per turn (data); overflow +1 turn per started batch beyond it; slots shown in the panel; hooks for buildings, traits, skills. Separate local and global capacities: unverified (ours is shared) |
| A5 | Recruiting locks movement | By design | Owner decision 2026-10-02: no lock |
| A6 | Queued units greyed with turns and a colour banner, always visible | Matched | Green local, blue global, orange overflow (wiki); cards narrow so 20 fit |
| A7 | Click a queued card to cancel | Matched (owner) | |
| A8 | Unit card tooltips | Partial | Rich styling (bold title); sticky or inspectable tooltips not yet |
| A9 | Right-click on a unit card | Open | |
| A10 | Ctrl+P disband | Matched | Ctrl+M merge: not yet possible |
| A11 | Key 4 opens recruitment | Matched | |
| P1 | Province panel | Matched (close) | Three parts (L6): growth, income, public order; settlement tabs with building slots or garrison; resources, climate (terrain) and effects (right column ours) |
| P2 | Cycling settlements | Matched | `,` / `.` |
| P3 | Key 3 building browser | Matched | |
| P4 | Keys 1 / 2 | Matched | Building slots / garrison of the selected settlement (or of the one the selected army stands in). 5 (heroes): not yet possible |
| T1 | Top bar | Matched | |
| T2 | Top-left buttons; WH3's round End Turn menu | Matched (owner: layout follows TW:WH3) | Menu, Advisor, Help, Unit browser, Camera settings (L1); round menu with hourglass, notification gear, Objectives, Diplomacy, Technology, culture slot (L5); greyed where no system exists. Ring positions are ours |
| T3 | Top-right drop-downs | Matched | Tactical map, Events, Lords and heroes, Provinces, Missions (greyed), Known factions, Faction summary (L3, L4); row contents are ours |
| T4 | Pop-up events | Matched (close) | War declared on you, a settlement lost, landless, destroyed; which events TW pops up is unverified (L8) |
| T5 | Finance / clan keys | Not yet possible | |
| E1 | Enter / Shift+Enter | Matched | |
| E2 | End Turn button jumps through warnings; arrows cycle; Skip | Matched | |
| E3 | Warning kinds | Matched for funds, construction, army can move | The others: not yet possible |
| E4 | Warning settings | Matched | Gear on the round menu (also in Settings) |
| E5 | H jumps to the warning | Matched | |
| E6 | AI turn controls | Matched (owner) | Pause, 1x / 2x / 4x (owner; TW has none), ">> Skip", Space/Esc; following AI movements Off / Only near my territory / All, default Off (TW's per-faction-group camera settings: not yet) |
| H1 | Tooltips | Partial | Title plus body, pinned beside the element, 0.45 s delay; not sticky |
| H2 | Map hover | Matched | |
| H3 | Help links | Not yet possible | |
| K1 | K hides the interface, Alt+K with letterbox bars | Matched | Esc also brings it back. Whether Alt+K works on WH3's campaign map is unverified |
| K2 | Ctrl+T labels | Matched | Settlement banners |
| K3 | R move speed | Matched (close) | Your armies' map animation 1x / 2x (also in camera settings and Settings); WH3's exact behaviour unverified |
| K4 | Tab | Matched | Was "hide interface"; now the strategic map |
| L1 | Top-centre faction resources and effects | Matched | Two greyed resource slots; the effects icon lists debt, landless and wars. The Treasury panel is not yet possible |
| L2 | Map layers | Matched (close) | Affiliation, Diplomatic status, Public order, Development, Climate and terrain; Attitude, Faith, Culture greyed; Winds of Magic and Corruption have no system |

## 13. Layout research (round 2, 2026-10-02) and decisions

Sources, beyond section 0:
- gamepressure's WH3 UI walkthrough (https://www.gamepressure.com/total-war-warhammer-3/user-interface/z9f67f, plus its provinces, movement and recruiting pages)
- CA's WH3 campaign UI script docs (https://chadvandy.github.io/tw_modding_resources/WH3/campaign/campaign_ui_manager.html)
- Steam threads cited inline in the research notes
- the official Xbox Wire hotkey list

Confidence uses the same labels as section 0.

| # | TW:WH3 | Conf. | Ours (this pass) |
|---|---|---|---|
| L1 | Top-left buttons, left to right: Menu, Advisor, Help pages (encyclopedia), Unit and spell browser, Camera settings | C | Same order. Menu opens the game menu; Camera settings opens our camera and speed settings. Advisor, Help and the unit browser are greyed ("Coming later") |
| L2 | Top centre: treasury (click opens a Treasury panel with Summary, Details and Trade tabs), income projection, faction-specific resources, then faction-wide effects at the right end | S (order), C (parts) | Treasury and income (breakdown tooltip), population, two greyed faction-resource slots, and an effects icon listing what affects your faction (debt, landless countdown, wars). The Treasury panel is greyed |
| L3 | Top right, left to right: tactical-map toggle (a small map under the bar), Events, Lords and heroes ("forces"), Provinces, Known factions, round Faction Summary (tabs Summary, Records, Statistics). Lists are drop-downs. Missions is also a list | S (order), C (drop-downs) | Same order. Tactical map toggles our minimap under the bar (the strategic map is Tab or zooming out). Events shows or hides the feed. Lords and heroes, Provinces and Known factions are drop-downs built from existing data. Missions is greyed. Faction Summary has Summary, Records (the Grey Scribes' chronicle) and Statistics (greyed) |
| L4 | Row contents of those lists | ? | Lords: general, army, units, location, movement. Provinces: income, growth, public order. Factions: war or peace with you, attitude (greyed until diplomacy) |
| L5 | Round menu: End Turn in the centre, the warning on the button with a skip arrow to its right; hourglass turn counter below it; notification gear beside the hourglass; Objectives, Diplomacy and Technology around it. Faction-specific buttons vary | S | Same. Objectives, Diplomacy and Technology are greyed; a greyed culture slot (Senate / League / Vassals) stands for the culture buttons. Button positions on the ring are ours (positions unknown) |
| L6 | Bottom panel, province selected: left = province info (growth, income with tax toggle, control, corruption, effects); middle = settlements of the province with headers and building slots, Recruit Lord and Hero below | S | Left = growth, income, public order (and population); middle = settlement tabs with building slots and a garrison tab; right = resources, climate and effects (owner; TW right column unknown) |
| L7 | Bottom panel, army selected: left = lord portrait and info, stances rollout, movement bar; middle = unit cards with recruit buttons above them (local and global pools) | S | Left = lord card, greyed equipment and trait slots, greyed stance buttons, movement bar; middle = recruit button above the cards, drawer, cards; right = army info (upkeep, replenishment, stance placeholder; owner) |
| L8 | Events: a drop-down list under the top-right bar; pop-up windows for dilemmas, missions and notifications (war declared, faction destroyed…) | C / S | The feed sits under the minimap, toggled by Events, with collapsible categories. Important events (war declared on you, a settlement of yours lost, your house landless or destroyed) also open a pop-up |
| L9 | AI turn: top-centre Pause / Play and fast-forward (">>"); fast-forward skips the enemy-turn camera | C | Pause, 1×, 2×, 4× and Skip (owner: speed steps; TW has none) |
| L10 | Camera settings: per faction group (yours, allied, enemy, neutral) × lords / heroes: animation speed (slow → fastest) and camera (off / cinematic / low / medium / high / strategic) | C (community) | Our first version: follow AI movements (Off / Only near my territory / All; default Off), AI turn speed, own-army animation speed (1× / 2×), display toggles (borders, banners, armies) |
| L11 | Strategic (tactical) map: Tab or zooming far out; layers Affiliation, Diplomatic status, Attitude, Control, Development, Winds of Magic, Climate, Corruption; markers for armies | C | Tab or zooming out; layers Affiliation, Diplomatic status, Attitude (greyed), Public order (= Control), Development, Climate and terrain, Faith (greyed, owner), Culture (greyed, owner). Clicking or scrolling in returns there. Winds of Magic and Corruption have no system |
| L12 | Hotkeys: K = toggle UI; Alt+K = toggle UI with letterbox borders (cinematic); 1–5 = overview, garrison, building browser, recruit units, recruit agents; R = toggle character move speed; Ctrl+T = toggle labels | C / S | K, Alt+K (hide UI and add letterbox bars), 1–5, R (own-army animation 1× / 2×), Ctrl+T (settlement and army labels) |

Still unverified: the treasury tooltip contents; the button positions on the ring; a right-hand column in the bottom panel; which events pop up; the strategic map's visual style and whether clicking it jumps the camera; whether Alt+K works on the campaign map; R's exact WH3 behaviour.

Key changes this pass:
- Tab was "hide UI"; it is now the strategic map, and K hides the UI.
- C (cycle armies) was already replaced by `,` / `.`.
- F (follow army) and G (Goldspire bookmark) are ours, with no TW key.
- Space: hold for overlays on the map, and skip during the AI turn.
- R is TW's character move speed.

## 14. Recruitment research (round 3, 2026-10-02) and the rebuilt flow

Sources:
- totalwarwarhammer wiki, [Recruitment](https://totalwarwarhammer.fandom.com/wiki/Recruitment) and [Global recruitment](https://totalwarwarhammer.fandom.com/wiki/Global_recruitment). The pages themselves returned HTTP 402 to our fetcher, so these findings rest on their search-result extracts.
- gamepressure, [Army: recruitment and replenishment](https://www.gamepressure.com/total-war-warhammer-3/army-recruiting-and-replenishment/z8f97b) and [Recruitment](https://www.gamepressure.com/total-war-warhammer-3/recruitment/z7f980).

| # | TW:WH3 | Conf. | Ours |
|---|---|---|---|
| R1 | Two recruit buttons on the army panel: local and global | S | "Local recruitment" and "Global recruitment" below the unit cards (owner); they open the panel above the army |
| R2 | Local: units from the buildings in the province the army stands in | C | Same (constitution: province-wide recruitment) |
| R3 | Global: units available at any of your settlements across the faction, at about double the upfront cost and double the time (a 2-turn unit takes 4). The wiki says it needs encampment outside your territory; gamepressure doesn't mention that | C (cost and time), S (conditions) | Anywhere, including abroad, with no stance (owner); 2x cost and 2x turns as placeholders |
| R4 | Recruitment capacity: a lord recruits up to 3 units in a turn; more units take one or more extra turns; buildings, traits and skills raise the capacity | C (wiki, gamepressure) | 3 by default; each started batch of 3 beyond it adds a turn (placeholder); hooks for buildings (`recruit_capacity` effect), traits and skills (the general's `recruit_capacity`) |
| R5 | Capacity is shown as small squares | C (gamepressure) | Capacity squares in the panel, filled by queued units, with "+N" for overflow |
| R6 | Queued units show a banner: green regular, blue global, orange over the limits | C (wiki) | Same colours, with the turns left on the banner |
| R7 | Turns above the unit card, upkeep below, cost at the top | C (gamepressure) | Turns above (orange when the next unit would overflow), cost, then men and upkeep below; locked units are greyed with the reason underneath |
| R8 | Whether local and global have separate capacities: gamepressure's example shows 2 global and 2 local squares; the wiki says "regular or global" limits | ? | One shared capacity (owner wording); left open |
| R9 | Recruiting locks the lord's movement | C | No lock (owner, deliberate difference; constitution) |

**The playtest bug (the drawer closed after one click):**
1. Unit cards act on the mouse press. Queuing a unit changes the campaign data, and the panel rebuilds at once.
2. The card under the mouse was freed inside its own input callback, before Godot marked the press as handled. The press fell through to the map.
3. The release then had no control to go to (its card was gone) and fell through too.
4. main.gd saw a press and a release at the same spot and treated them as a click on empty ground, which deselected the army and closed the panel.

Fixed in two places:
- Cards accept the press before acting.
- The map counts a release as a click only if it also received the press.

## 15. Playtest fixes research (round 4, 2026-10-05)

Web research (guides, Steam discussions, patch notes and UI mods; the Fandom wiki was unreachable). Items marked **[unverified]** are recollection to confirm against in-game footage before polishing.

**Lords & Heroes character window**
- **Opening it:** the magnifying glass under the portrait in the bottom-left army panel. The top-right Lords and Heroes list (level, army strength) selects the character and pans to it. **[unverified]** Double-clicking the portrait also opens it.
- **Tabs:** across the top. Details (default) and Skills; item management on the right (Equipment; Quests for legendary lords).
- **Details tab:** the full-body character model on a dark backdrop. Name with epithet, level, rank chevron and XP bar. Stats: Leadership, Speed, Melee Attack, Melee Defence, Weapon Strength, Armour, HP. Traits as an icon row with tooltips. Equipped items and followers next to the model.
- **Skills tab:** horizontal rows read left to right.
  - Rows 1–2: signature perks and spells. Then battle rows. Then army-influence and campaign rows (lords); heroes get agent-action rows instead.
  - One point per level, with an unspent-points count.
  - Auto-allocate is a checkbox at the upper left; it also removes the character from the unspent-points end-turn warning.
- **Equipment tab:** slots for Weapon, Armour, Talisman, Enchanted Item, Arcane Item, followers and a banner. Rarity colours: grey, green, blue, purple/gold.

**Diplomacy screen**
- **Opening it:** the Diplomacy button (a hand holding a scroll) on the round End Turn menu, or double-clicking a foreign army or settlement.
- **Layout:** a full screen in three columns.
  - Left: your faction (leader portrait, strength, pacts, trade goods; reliability rating under the portrait, in yellow).
  - Centre: the known factions list with attitude. Quick Deal has a "deal chance" column and deal buttons: non-aggression, trade, military access, defensive alliance, military alliance, peace. Negotiate and War Coordination (axes) buttons sit under the list.
  - Right: the selected faction mirrored, with its diplomatic traits.
- **Negotiation:** new agreements, existing agreements and offers/demands along the bottom; an acceptance score in the lower right (accepted above 0).
- **Attitude:** a number with an itemised breakdown on hover.
- **Declaring war:** cancels every agreement, after a confirmation that warns about broken treaties.

**Turn transitions**
- **Ending the turn:** End Turn, or Enter.
- **AI turns:** a bar at the top centre scrolls the factions taking their turns. ">>" skips AI movement, ">" restores normal display. Pause opens the per-group (friendly / neutral / enemy) movement display settings.
- **Your turn:** event messages open in sequence, the hourglass turn counter advances and the camera returns. **[unverified]** In single player there is no large "Your Turn" banner, only a chime.
- **Owner request:** a clear announcement is wanted. We add a "Your turn / Year X" banner, recorded as an owner decision (§10).

**End Turn warnings**
- End Turn with pending items shows a list by the round menu.
- Each item jumps the camera to the army, character or settlement. H goes to the next item. Shift+Enter ends the turn anyway.
- Types: settlement upgrade available, construction slots free, characters with movement left, unspent skill points, army can recruit (plus research and rites).
- A cog by End Turn toggles each type.

**Upgrade indicators**
- A green hammer marks "upgrade available" in the Provinces list. **[unverified]** It also appears on the settlement's map label.
- **[unverified]** In the settlement panel, an upgradeable building's card shows a small green up-arrow; hovering it shows the next tier's cost and turns.

**Attack flow**
- Select the lord, then right-click an enemy army or settlement.
- If you are not at war, a confirmation warns about the declaration and broken treaties.
- The army marches over as many turns as needed: the path preview is green this turn, red next turn, cyan after.
- The pre-battle panel opens only when the army reaches the target with movement to spare. If the target was hidden in the shroud, the army stops at the zone-of-control edge to confirm.

**Strategic map**
- Opened by Tab or by zooming out.
- A stylised parchment and painted map with faction-coloured region fills and a layers panel.
- Ctrl+T toggles labels. **[unverified]** Province names show when zoomed out, settlement names when zoomed in.
- Armies appear as banner tokens with the faction emblem.

**Lord figures**
- One figure per army: the lord, often mounted, oversized against settlements, with a faction standard on a pole.
- The selected figure gets a ground ring.
- **[unverified]** Heroes have no standard.

**Sources:**
- gamepressure.com Total War: Warhammer 3 guide: user interface, skills, equipment, diplomacy, movement, settlement development.
- Xbox Wire, "Total War: Warhammer III hot keys revealed" (2022-02-16).
- thegamer.com diplomacy guide.
- github.com/emmanuel-h/wh3-quick-deal-indicator.
- Steam community discussions in app 1142710: AI movement display, notifications, skill auto-allocate, upgrade arrows, zone-of-control attacks.
- gamewatcher.com autoresolve article.
- moddb "Building progression icons".

## 16. Territory, zoom and minimap (owner, 2026-10-06)

| Item | Ours | Notes |
|---|---|---|
| High zoom | Fog thins, trees give way to the forest canopy carpet, small props and houses cull, lord figures give way to their banners (crests), small settlements show only their pennants while your own and the great cities keep their names | Far terrain tiles (2 km) replace the 256 m chunks beyond 2.6 km (`map/map_view.gd`), so the whole world costs a few dozen terrain draw calls |
| Borders on the 3D map | Projected by the terrain shader: a thin line between regions, a thicker line in the owner's colour between factions, the player's realm border thickest in the player's colour with a soft glow band inside; widths grow with camera height | `map/terrain_view.gdshader` |
| Faction wash | None up close, rising to about 24% (others) and 34% (yours) at the highest 3D zoom | Hovering a settlement or army (or its banner) washes that faction's whole territory more strongly |
| Strategic map modes | Political (default): your land saturated and outlined in your colour, others muted, occupied or besieged land hatched in the occupier's colour, vassals striped in the liege's colour, Caeloth stippled gold on ivory; Diplomacy: you, vassals, allies, trade partners, neutral, hostile, at war, with a legend | Crest and name labels at each realm's centre, sized by realm size |
| Minimap | The strategic map's political painting at minimap size, settlement dots, army pips, the camera's view box; click or drag to jump | Shares the strategic map's textures (`ui/minimap.gd`) |
| Frame my realm / Go to capital | Shift+Home / Home, and two buttons beside the minimap | Ours (camera-mod conveniences); TW:WH3 has Home only |

## 17. Court, realm and diplomacy screens (Part 4, 2026-10-06)

| Item | Ours | Notes |
|---|---|---|
| Court | Round button "Court" (top left): a full screen with the family tree (ruler and spouse, children and grandchildren, siblings beside them; placeholder portraits), the rest of the court, and the selected character's card: name and epithet, age, career, level, traits, loyalty with its reasons in the tooltip, role; actions Name heir, Make ruler, Arrange marriage, Appoint governor, Choose a path (formative years), Gift, Rename, Details | Ours (CK depth in a TW frame); TW:WH3 has no court screen. Details opens the Lords & Heroes window with the career's skill tree, traits, loyalty breakdown and history |
| Realm | Round button "The Realm" (top left): tabs Vassals (loyalty with reasons, goal, economic goal, tribute, the cap, gifts), Titles (holders, conditions, powers, granting), Realm Standing (level, progress, caps, reputation), Banners and Hosts (standing's terms, muster points, dismiss levies) | Ours. Hosts form from the army panel (Form Host / Leave Host) |
| Diplomacy | TW:WH3's three columns; the centre lists every faction (met first; envoys reach anyone) with attitude faces, relation and treaty locks, and the proposal builder (You offer / You demand, items grouped: Treaties, Payments, Land, Characters) with the live acceptance bar and their reasons with numbers; Send envoy, Send embassy, Declare war (with justification, betrayal warning and allies), Order (allies and vassals); a Dossier tab | docs/diplomacy-design.md §15. Orders from a right-click on the map: later |
| Proposals | AI offers and calls to arms wait at the top of the Diplomacy screen (Accept / Decline; Join / Support / Refuse), announced in Event Messages | At most one per AI faction a turn |
| Map | Host leaders' banners carry a gold star, Host armies a gold pip; a muster point's banner reads MUSTER | |
| Recruitment bar | Culture rosters run to 16 units: the card row scrolls sideways inside the army panel | TW:WH3 scrolls its recruitment bar the same way |

## 18. Playtest fixes (owner spec, 2026-10-07)

Reference screenshots in `docs/reference/tw/` (`lothern_lords.png`, `terrain_1.png`, `terrain_2.png`) were studied first. Where the spec and the screenshots differ it is noted in the row.

| Item | Ours | Notes |
|---|---|---|
| Free movement | Lords move anywhere passable; roads are about 35% faster (`data/movement.json` dirt road 0.74) and the planner takes them when faster; forest 1.6, marsh 1.8 (new terrain: swamp and marsh climates); deep water, peaks and rivers (except bridges and fords) impassable. Fast in own and allied land, slow abroad, zone of control by army size (unchanged) | TW: free movement with road bonuses |
| Select and reach | Left click selects; the reachable area this turn is a soft gold fill with a crisp edge drawn over trees and roofs | |
| Preview | With your army selected, the path to the cursor shows on hover at once; holding right click also previews; releasing (or a single right click) commits | Supersedes §15's "preview only while right click is held" (owner) |
| Path line | A thick ribbon projected on the terrain and drawn over everything (no depth test against trees, buildings, hills or walls), chevrons running toward the destination; this turn bright green, later turns amber, red when blocked or unreachable; a numbered marker at each turn break; the end marker shows the action (move, attack, enter, merge, besiege, blocked) | Supersedes the earlier "no numbers on the map" (owner) |
| Cursors | The cursor shows the action icon (move, attack, enter, merge, besiege, blocked) while previewing | TW: action cursors |
| Committed orders | The selected army's order in full with its markers; every other army of yours with an order as a thin faint line (Settings "Show my armies' orders", default on) | |
| Movement points | A bar under your armies' banners and on the army panel; the reach area updates after every move | |
| Multi-turn orders | No army of yours moves at End Turn or turn start unless you ordered it that turn. Settings "Continue multi-turn orders automatically" (default off): with it off the order keeps its path and waits for "Continue order" (army panel) or "Continue all orders"; waiting orders are an End Turn notification. Host followers and levies wait the same way | Owner rule (TW continues orders automatically) |
| Hotkeys | Backspace cancels the selected army's order; Space toggles your armies' movement speed (1x/2x); double-click an army centres the camera on it | Space previously showed labels while held (dropped) |
| Animation | Lords walk smoothly along the path from where they stand to where they will stand (never snap) | |
| Lords | Twice the previous size (lord_scale 4.0, banners x2) and one fixed size at every zoom (hotfix 2026-10-07 removed the growth with camera height and the minimum on-screen size; only banners and name plates stay screen-readable); garrisoned lords stand just outside their settlement's walls | Matches `lothern_lords.png` |
| End Turn button | The notification is the button: the top pending item's icon on it, a count badge, and a red plate across its foot naming the item ("Lord has skill points"); a click goes to it, the next click to the next; nothing pending: the hourglass and End Turn. End turn anyway: the small button on the ring, Shift+click or Shift+Enter. The separate "warning" box above the button is gone | `terrain_2.png` shows the blocker plate under the button (as built) and a stack of red event ribbons above it; the owner's spec removes any separate stack, so the ribbons are not built (Event Messages carries events) |
| Pending items | Choices (absorbed families, careers due), diplomatic replies and proposals, low funds, skill points, settlement upgrades, idle building slots, waiting orders, lords that have not moved, armies that can recruit | Each switchable in the notification settings |
| Text | Fira Sans (OFL) body text, Cinzel headers; labels at least 14 px; brighter dim text; settlement names with a dark outline on their plates; a lord's name plate on hover or selection | Replaces Alegreya Sans |
| Construction | Every empty slot can build at the same time, each paid when started; a realm construction queue (top right, hammer) lists everything building with turns left, a jump to the settlement, and cancel with refund | |
| Placement | Port only on the sea coast, Fishing Camp only by sea, lake or river, Mines only with hills or mountains near; unavailable chains are not offered (validator test) | |
| Recruitment | One card per unit with its best source (local, else global); the global drawer lists only units not recruitable locally; the main building gives basic infantry | |
| Diplomacy list | Quick filters (Hates me, Dislikes, Neutral, Likes, Loves, At war with me, Allies, Vassals, Met, Not met) and an attitude sort; red-to-green faces on every row; hover a row for the attitude and its reasons | |
| Offer builder | Items already active between you are not offered; they show as Active with Cancel (locked while protected); items in the offer leave Add Item on both sides; "No more items available" when none remain | |
| Replies | Every envoy and proposal returns an answer: a reply pop-up with the ruler's portrait, their words (by attitude) and the outcome; it feeds the End Turn button; envoys on the road are listed with turns to arrival | |
| Turn summary | Event Messages: Turn Summary (your settlements, your armies and battles, diplomacy, your court, threats near your borders; each row jumps to its subject), Your Wars and Battles, Court and Realm, and World (this turn only, collapsed by default) | |

## 19. Resources, markets and seasons (owner spec, 2026-10-07, Part B)

| Item | Ours | Notes |
|---|---|---|
| Top centre | Faction emblem (name and realm in its tooltip), treasury, income, population, then food, wood and stone, each as stock (change per turn); the season icon (sun, or snowflake in winter and the dry season) with the turns until it changes; the market button; faction effects | Follows `lothern_lords.png`: TW:WH3 shows the emblem and resources only, no faction name. The name was dropped because the bar overflowed at 1440×900 |
| Resource tooltips | Stock and change per turn, then a line per settlement that produces it and what your people and armies eat | TW: the treasury tooltip ledger |
| Market | A window (top-bar scales button, M, Esc closes): each resource with stock, buy and sell price per unit, and lots of 50/100/250 to buy or sell; the header explains the prices; the End Turn food warning opens it | Not in TW:WH3 (no market screen); styled like our other windows |
| Supply | Army panel, info column: a supply bar (green, amber under 60, red under 30) with next turn's change; the tooltip gives the reason and how to refill; a "Raiding stance" checkbox for your armies | Replaces the greyed Stance slot. TW: the stance buttons on the army panel; raiding works like TW's raid stance (lives off the land, slower) |
| End Turn | Food: "Food will run out" while food runs out within 3 turns (or "Your people are starving"); Supply: "Army low on supply" | Through the same End Turn notification as Part A (§18) |
| Seasons | The forecast and the change of season arrive as pop-ups ("Winter is coming", "Winter has come", "The thaw"); the terrain whitens over two winter turns, most in the north, and thaws in summer | TW has no seasons; built from the war-and-realm spec |
| Trade routes | Each of your trade agreements is a steady gold band from capital to capital, under army orders and without chevrons or markers | TW:WH3 draws trade routes on the map only for sea trade; ours are land lines from the spec |

## 20. Hotkeys (hotfix, 2026-10-07)

Every key the campaign map handles (`main.gd _unhandled_input`, `camera_update`; panels close on Esc). The owner's rule follows TW:WH3: **Tab opens the strategic map, M opens the market.** M was never bound to the strategic map in code (only Tab was); M became the market key in Part B.

| Key | Action | Notes |
|---|---|---|
| W A S D, arrow keys | Pan the camera | Off while Ctrl is held (Ctrl+S, Ctrl+L) |
| Q / E | Rotate the camera | |
| Shift (held) | Pan faster | |
| Mouse wheel | Zoom toward the cursor; scrolling out at the maximum opens the strategic map | |
| Middle drag | Orbit | |
| Left click | Select (army, settlement); empty ground deselects. Double-click an army: centre on it | |
| Right click | Order the selected army (hold to preview, release to order) | |
| Tab | Strategic map (open and close) | TW:WH3 |
| M | Market (open and close) | Owner rule |
| Enter | End Turn (first goes to the pending notification) | TW:WH3 |
| Shift+Enter | End Turn anyway (skips the notifications) | TW:WH3 |
| H | Go to the next pending notification | |
| Esc | Cancel a held preview, then close the top panel, then the pause menu | TW:WH3 |
| Backspace | During a held preview: drop it (no order on release); otherwise cancel the selected army's order | Owner rule |
| Space | Your armies' walk speed 1x / 2x; while AI moves play: skip them | Context: no clash |
| R | Your armies' walk speed 1x / 2x | Same action as Space (duplicate, kept) |
| F | Camera follows the selected army (on/off) | |
| , / . | Previous / next own army (or own settlement when a settlement is selected) | |
| Home / Shift+Home | Centre on the capital / frame the whole realm | |
| End | Reset the camera rotation and tilt | |
| 1 / 2 | Settlement panel: buildings / garrison tab | |
| 3 | First empty building slot of the selected settlement | |
| 4 | Recruitment for the selected army | |
| 5 | Heroes (coming later) | |
| K / Alt+K | Hide the interface | |
| G | Goldspire (test map shortcut) | Prototype |
| F12 | Save a screenshot to captures/ | |
| Ctrl+S / Ctrl+L | Quicksave / quickload | Ctrl branch handled first: no clash with S (pan) or L (debug light) |
| Ctrl+P | Disband the selected army | |
| Ctrl+T | Show or hide map labels | |
| F5 F6 F7 F8, L | Debug keys (Settings: on by default): upgrade city, cycle Goldspire, upgrade roads, pause, light | Debug only |
| F9 | Strategic map debug layer (debug keys) | Debug only |

Clashes checked: none left. Tab is only the strategic map; M is only the market; Space's two actions never apply at the same time; R duplicates Space on purpose; Ctrl combinations are handled before plain letters. Tests: `tests/test_hotkeys.gd` (Tab, M, Backspace) and `tests/test_movement_input.gd` (Backspace during a preview, Enter and Shift+Enter, Ctrl+S).
