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
| A5 | Recruiting locks the lord's movement | C | Movement not locked | Rule difference (not UI). Open item for the owner |
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
| Wheel | zoom | same |
| Home / End | pan to capital / default rotation | same |
| `,` / `.` | previous / next army or settlement | same |
| Backspace | cancel order | same (selected army) |
| Enter / Shift+Enter | end turn / skip warnings | same |
| H | jump to the end-turn notification | same |
| Ctrl+S / Ctrl+L | quicksave / quickload | same (already) |
| Ctrl+P | disband selection | same (selected unit) |
| 3 / 4 | building browser / recruitment | same |
| Hold Space | overlays | settlement banners at any zoom |
| Tab | strategic map | hides the interface until a strategic map exists |
| Esc | game menu | closes the top panel, then the pause menu (by design) |
| F12 | (screenshot, Steam) | screenshot |

Debug keys (ours, behind the Settings switch): F5, F6, F7, L, and F8 (traffic pause, moved from Space).

## 10. Owner decisions recorded here

- No numbers anywhere on the map or path; the movement bar has no numbers (M4, M7, M9).
- Selecting never moves or zooms the camera; cycling and notification jumps pan at the current zoom (S3, S5, C10, C11).
- Middle-drag orbits; right-drag does nothing (hold right-click is the preview) (C4, C5).
- Recruitment rule (Phase B): any own region of a province; units from that province's buildings; queued units greyed with a turn counter, click to cancel (A3, A6, A7).

## 11. Open: needs in-game observation, or an owner decision

- Double-click behaviour (S4); attack cursor (M6); edge scroll (C6); right-click on a unit card (A9).
- The path colours after the first turn and for blocked destinations (M3).
- Range boundary colour (M5: we use the WH2 Academy's yellow-gold).
- Whether recruiting should lock the lord's movement (A5: a rule, not UI).
- **Layout (T2/T3):** move the mission, diplomacy and technology buttons to the End Turn cluster and use top-right dropdowns (WH3), or keep the constitution's described layout.

## 12. Status after the parity pass (Phases B and C, 2026-10-02)

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
| C6 | Edge scroll | Open | |
| C7 | Home pans to the capital, End resets rotation | Matched | |
| C8 | Tilt follows zoom | Matched | Our curve: about 35° close in |
| C9 | Strategic map, Tab | Not yet possible | Tab hides the interface meanwhile |
| C10 | `,` / `.` cycle armies or settlements at the current zoom | Matched | C removed |
| C11 | Notification jumps | Matched (owner) | Pan at the current zoom |
| C12 | Hold Space for overlays | Matched | Settlement banners at any zoom; debug traffic pause moved to F8 |
| A1 | Army panel structure | Matched (close) | |
| A2 | Recruit button below the cards, recruitment drawer | Matched | Local recruitment |
| A3 | Local recruitment from the province's buildings | Matched | Global recruitment: not yet possible |
| A4 | Recruitment capacity | By design | Constitution open item |
| A5 | Recruiting locks movement | By design | Rule, not UI; open for the owner |
| A6 | Queued units greyed with turns, always visible | Matched (owner) | Cards narrow so 20 fit |
| A7 | Click a queued card to cancel | Matched (owner) | |
| A8 | Unit card tooltips | Partial | Rich styling (bold title); sticky or inspectable tooltips not yet |
| A9 | Right-click on a unit card | Open | |
| A10 | Ctrl+P disband | Matched | Ctrl+M merge: not yet possible |
| A11 | Key 4 opens recruitment | Matched | |
| P1 | Province panel | Matched | |
| P2 | Cycling settlements | Matched | `,` / `.` |
| P3 | Key 3 building browser | Matched | |
| P4 | Keys 1 / 2 | Not yet possible | |
| T1 | Top bar | Matched | |
| T2 | Top-left buttons; WH3's End Turn cluster | By design (constitution layout) | Owner decision pending |
| T3 | Top-right dropdowns | By design (constitution layout) | Owner decision pending |
| T4 | Pop-up events | Not yet possible | |
| T5 | Finance / clan keys | Not yet possible | |
| E1 | Enter / Shift+Enter | Matched | |
| E2 | End Turn button jumps through warnings; arrows cycle; Skip | Matched | |
| E3 | Warning kinds | Matched for funds, construction, army can move | The others: not yet possible |
| E4 | Warning settings | Partial | Checkboxes in Settings, not a gear beside End Turn |
| E5 | H jumps to the warning | Matched | |
| E6 | AI turn controls | Partial | Top-centre ">> Skip" bar and Space/Esc; no pause button or per-faction tracking settings |
| H1 | Tooltips | Partial | Title plus body, pinned beside the element, 0.45 s delay; not sticky |
| H2 | Map hover | Matched | |
| H3 | Help links | Not yet possible | |
