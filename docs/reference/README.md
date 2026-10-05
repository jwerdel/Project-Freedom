# Reference art (reference material only)

Nothing under `docs/reference/` is a game asset. `docs/reference/.gdignore` keeps Godot from importing or exporting any of it, and nothing here may be copied into `assets/` or loaded by the game.

| Folder | Contents | Used as the target for |
|---|---|---|
| `cards/` | unit card mockups (see its README) | card style |
| `landmarks/` | Gemini concept images of the landmark settlements, plus `landmark-prompts.md` | landmark models (e.g. Goldspire: `goldspire rock.jpg`) |
| `biomes/` | one culture biome board per culture, plus `biome-prompts.md` | each culture's biome profile (terrain, ground cover, trees, weather, land conversion) and building kit |
| `specializations/` | six-panel specialization sheets per culture, plus `specialization-prompts.md` | each culture's specialization looks (military, farming, mining, lumber, market) |
| `tw/` | Total War: Warhammer III screenshots | **never committed** (copyrighted); kept locally only |

The images were AI-generated (Gemini). They were re-encoded before committing, which strips all metadata; images without an extension were PNGs and are now JPGs.

**Style rule (owner, 2026-10-04):** these images are references for palette, materials and architectural style, **not for layout or composition**. They skew generic: circular walled forts on bare ground. The settlement generators never copy their layouts. Layouts follow terrain and culture (see `docs/game-design.md` and `constitution.md`).
