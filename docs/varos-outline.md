# Varos world outline (block A1)

**Status:** **Proposed**, waiting for the owner's approval. No Stage A content is built until the outline is approved: no armies, buildings, rosters, landmarks or generated names.
**Sources:**
- shapes after `docs/reference/world/varos_map.jpg` (shapes only; the reference's labels are not used);
- content after `docs/world-bible-v2.md` §6–§8 and Appendix A;
- the Stage A plan in `docs/map-pipeline-design.md` §8.

**Files:** `data/maps/varos/`, built by `scripts/build_map.gd -- --map=varos`; the validator passes with 0 errors.
- `sketch.svg`: editable in Inkscape. Layers: land, lakes, climates, ranges, passes, hills, forests, rivers, sites, stages.
- `world.json`, `factions.json`, a minimal `campaign_start.json`, `map.json`.

**Images** (`map/map_scene.tscn -- --map=varos --strategic --outline [--strategic-rect=0,180,3300,2700]`): the whole world and the Stage A slice. They show region and province borders, the Stage A boundary, the locked Ashlands, the Rift and faction start positions.

## 1. Frame (Proposed change)

- **5,632 × 4,608 m.**
- Design Addendum A has 5,632 × 3,584 m. This adds 1,024 m in the south, so the Sahren desert and the Sothmire jungle get TW:WH3-scale room (owner: "the south must be large").
- The north (Aldryn down to the Red Peaks, Ossara) keeps the Addendum's scale. The reference image is stretched only south of the Red Peaks.
- The outline builds at cell 4 m (fast); the content build uses cell 2 m. Region IDs do not change with the cell size.

## 2. The world

**Aldryn** (west): the bow-shaped continent from the Frostwaste to the desert peninsula.
- **The Greywall** across the far north. It is a wall feature: impassable except at Wardens' Gate. The Frostwaste lies beyond it.
- **The North:** forests, moors and the Long Lakes.
- **The Vale:** a ring of mountains around Skyreach, with a gap to the south-west.
- **Caeloth** on a marsh isthmus at the west shore of a central lake, where three rivers meet: from the North, from the Greek hills and from the Vale. The lake drains south-east to the sea.
- **The Middle Marches** around Caeloth.
- **The Greek west coast**, behind a ridge of sea cliffs with one pass. Delos Minor lies offshore.
- **The Western Isles:** a crescent of two dark elf isles around a bay with the volcanic Burning Isle.
- **The Roman south:** the Reach and the Crownlands.
- **The Stormlands** on the eastern peninsula facing Ossara across the Narrow Sea, with the Rainwood.
- **The Skulkmire swamp** in the south-east.
- **The Red Peaks:** a crescent of red mountains with two passes (Redgate and Karak).
- **The Sahren:** a large desert peninsula below the Red Peaks, with the oasis river, an oasis lake, canyons and two islands.

**Ossara** (east):
- the island-filled gulf in the west;
- the white-cliff Elven Coast (Lysar, Aelthas, Therin);
- the Horned Sea steppe with Hornstone;
- beyond an ash mountain wall with one pass, the Ashlands with the Rift. The Ashlands are locked for V1.

**Sothmire** (south-east): the jungle continent.
- the Gnawing Coast in the north;
- the Jungle Heart;
- the Serpent Coast;
- a black-rock spine;
- an island chain reaching west toward the Sahren.

## 3. Stage A slice

- **Extent:** Aldryn from just beyond the Greywall (the Snowtusk and Grimhollow fringe) to the Red Peaks' north face, coast to coast. It includes the Western Isles and the Stormlands peninsula.
- **Contents:** 73 regions in 36 provinces, placed as world bible Appendix A lists them, with every holder as listed there. Ashen Tower is the one unsettled region (the Wall is undermanned).
- **Factions:** 42.
  - **3 playable starts:** House Varn at Frosthold, House Varrenus at Varrenum, the Aurekids at Goldspire Rock.
  - **11 major AI factions** (§8.3).
  - **20 minor houses** (§8.3, approved as renamable placeholders):
    - North: Dunmoor, Kells, Rowen, the Barrow-lords.
    - Middle Marches: Tollan, Merrow, Bracke, Ashford.
    - Roman: the Tullan estates, Port Dallow, Fossa, House Verrin of Highbloom (Roman minor).
    - Greek: the Lannetids of Silverfall (Silverfall's tyrants), Delos Minor, the Lykourgids of Lykon.
    - Dwarves: Stonefast.
    - Orcs: Snowtusk, Grimhollow.
    - Dark elves: two reaver captains.
  - **8 generated houses** with placeholder names, named at Stage A content time (world bible §10): Blackpine, the Long Lakes, the Lower Vale, the Riverforks, the Elaian League, Sabellum, the Via Septem, Rainwick.
- **Placeholders:** faction colours and emblems.

Later stages are coarse, unowned areas so the outline tiles the whole world:
- Stage B: the Frostwaste, the Red Peaks' south face, the Sahren;
- Stage C: Ossara;
- Stage D: Sothmire;
- locked: the Ashlands.

They are not regions yet.

## 4. Pipeline changes made for the outline

- A `climates` sketch layer: ground colours only, in the render cache (snow, taiga, mediterranean, desert, red rock, swamp, marsh, steppe, ash, jungle, white cliffs). The gameplay climate per region comes with the content.
- Ridge cores (mountains and the Greywall between two regions) now join the nearest region after the ridge-respecting fill, so every land cell has a region. Maps whose regions are all pinned, such as the test map, are unchanged.
- The `stages` layer is kept in the sketch for tools. The pipeline ignores it; the outline overlay draws it.

## 5. Questions for the owner

1. The frame: 5,632 × 4,608 m (south enlarged), or another size?
2. Shapes and positions: anything to move? (Inkscape on `sketch.svg`, or notes on the images.)
3. Stage A's eastern edge includes the Stormlands peninsula up to the Narrow Sea. Is that right?
4. The Western Isles as two crescent isles (Brinecrag with Mor-Skerry; the Grey Stacks with Drakhaven and Vael-Shoal) plus the Burning Isle as an unsettled volcano. Is that right?
