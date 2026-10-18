# Known issues

Honest list of limitations in the current build. Design simplifications are
also tabulated in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **No human play-test yet.** Everything below "understandable" in the M1 exit
  criteria was checked by tests and by reviewing rendered frames, not by a
  person flying it. Mouse feel, readability of the orbit path and whether
  real-scale orbital drift is noticeable in a fight are all unverified. The
  shipyard has likewise only been driven by the smoke test and screenshots.
- **Shipyard: no undo.** Right-click removes immediately. Load the template or
  your last save to recover.
- **Shipyard: moving or rotating a module does not carry its rooms and
  equipment.** They stay where they were and the validator flags them.
- **Shipyard: modules rotate about their corner cell**, so a rotated module
  usually needs moving back into place (arrow keys).
- **Off-axis engine thrust is only a warning.** Flight still treats thrust and
  torque as independent, so an unbalanced design doesn't actually yaw in flight.
- **Power and heat are budgets, not networks** (no wiring, coolant or
  breakers yet), and only the first cannon on a design fires.
- **Exported builds:** the JSON templates in `data/blueprints/` need a
  `*.json` include filter in the export preset (no export preset exists yet).
- **No drag; the 100 km entry interface is a hard line.** Crossing it removes
  the vessel (or round). Skimming just above it costs nothing.
- **Hit box is a single box** around the whole hull, so rounds can "hit" empty
  space beside the side pods or above the nose. Hits are counted and flashed,
  but do no damage until Milestone 3.
- **Target ship is passive** — no AI, no evasion. The lead solution assumes a
  coasting target.
- **No propellant limit.** Δv spent is tracked and displayed but nothing runs out.
- **Ships are lit on the night side** (no eclipse shadowing). The planet itself
  does show day/night.
- **Procedural Earth, not real geography.** Continents and clouds are noise;
  the planet does not rotate and clouds do not move.
- **Orbit path rendering is approximate near the ship.** The path is sampled
  every 2° (~240 km) from one sample ahead of the ship, so it starts slightly
  ahead of the prograde marker.
- **Gyroscopic coupling ignored** (diagonal inertia only).
- **Rebinding only via Project Settings** — no in-game rebinding UI; no gamepad
  bindings yet.
- **Dust field repeats** every 1.5 km per axis; distance fade hides the seams but
  a sharp eye may spot the repetition.
- **No audio.**
- **Compatibility (OpenGL) renderer not re-checked** since the planet sky shader
  was added; frames were reviewed under Forward+ only.

## Environment notes

- On Google Drive (or other Windows virtual drives) Godot logs
  `get_filesystem_type` errors at startup. Harmless; `run_checks.sh` ignores
  exactly that error.
- In containers without a sound card Godot logs ALSA errors and falls back to the
  dummy audio driver. Harmless; `run_checks.sh` runs with `--headless`, which
  avoids it.
- If the Godot editor is open while `project.godot` changes on disk (e.g. new
  input actions), reload the project (Project → Reload Current Project) so the
  editor doesn't save its stale copy over it.
