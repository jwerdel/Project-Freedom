# Card style references (reference material only)

`men_style_reference.jpg` and `orc_style_reference.jpg` are 3x3 grids of mockup unit cards, used as **style targets only**: painterly full-figure portrait, dark red backdrop with ruined architecture, worn card edge, one figure per card.

They are not game assets:

- Do not slice, crop or copy them into `assets/cards/` or anywhere the game loads from, and do not use them in-game.
- `docs/reference/.gdignore` keeps Godot from importing or exporting them.
- They were AI-generated mockups; provenance metadata was stripped before committing.

What the final cards must change from these mockups:

- **Original faction heraldry.** No real-world crosses (Teutonic/cross pattee, Latin cross), eagles, or other real-world religious, national or order symbols. Use each faction's own heraldry from `docs/world.md` / `data/factions.json`.
- **Orcs get their own crude visual language**: scavenged and mismatched armor, bone, fur, hide, war paint, crude glyph-daubed shields, rough hand-forged weapons. The orc mockup reuses human plate, tabards and crosses; that is exactly what to avoid.
- The game draws all overlays (faction border, strength bar, rank chevrons, unit count) on top of the art; card art itself carries no UI.
