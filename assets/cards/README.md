# Unit card art (optional)

Drop a hand-made card image here named after the unit type ID: `assets/cards/<unit_id>.png`
(or set `"card_art"` to an image path in `data/units/<unit_id>.json`). Without one, the card uses
the portrait auto-rendered from the unit's visual scene.

Unit type IDs: `archers`, `cavalry`, `commander`, `heavy_infantry`, `peasant_levy`, `spearmen`, `swordsmen`.

Then run `runtime\Godot.exe --headless --path . -s scripts/fit_card_art.gd` (center-crops and
downscales everything here to 192x360) and a headless import.

Art only: no frames, bars or text. The game draws the faction border, strength bar, rank chevrons
and unit count on top. Every file needs its source, author and license in `ASSETS.md`, and must
follow the card art rules in `CLAUDE.md` (original heraldry; orcs in their own crude style). The
mockups in `docs/reference/cards/` are references only and never go here.
