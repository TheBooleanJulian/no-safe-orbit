# Your own sounds, textures and models

A file here named for its slot replaces the game's own; with none, the game
uses what it has. Open the project in the Godot editor once after adding
files (or run `godot --headless --path . --import`) so they are imported.

- `audio/<slot>.ogg` (or `.wav`, `.mp3`), variants `<slot>_2` … `<slot>_4`
- `textures/<slot>.png` (or `.jpg`)
- `models/<part id>.glb` (or `.gltf`), and `<part id>_turret.glb` for a gun's head

The slots, file names and how to make each are in
`art_templates/custom_assets.xlsx`, with templates beside it. The list in
code is `scripts/presentation/custom_assets.gd`.
