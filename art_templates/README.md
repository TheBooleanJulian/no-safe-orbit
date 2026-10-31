# Art templates

Everything to make your own sounds, textures and part models for the game
(they go in `data/custom/`; see the README there).

- `custom_assets.xlsx` — every slot: when it plays or where it shows, the
  file to save, how to record or paint it, and a status column.
- `textures/<slot>_base.png` — the game's texture today, to paint over.
  `textures/<slot>_guide.png` — tile edges, metre grid and notes, for a
  layer above (hide it before saving).
- `models/<part id>.png` — each external part as the game builds it, from
  above, the side and the bow, on a 1 m grid (gold lines: 3 m cells); the
  gold cross is the model's origin, the teal cross a turret's pivot.
- `manifest.json` — the slot and part list the sheet is built from.

Made by `tools/make_art_templates.gd` (`godot --path . -s
res://tools/make_art_templates.gd`; it renders, so it needs a display).
Godot ignores this folder (`.gdignore`).
