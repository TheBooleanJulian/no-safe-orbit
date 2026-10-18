# Known issues

Honest list of limitations in the current build. Design simplifications are
also tabulated in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **No human play-test yet.** Everything below "understandable" in the M1 exit
  criteria was checked by tests and by reviewing rendered frames, not by a
  person flying it. Mouse feel, readability of the orbit path and whether
  real-scale orbital drift is noticeable in a fight are all unverified.
- **No drag; the 100 km entry interface is a hard line.** Crossing it removes
  the vessel (or round). Skimming just above it costs nothing.
- **Hit box is a single box** per ship, so rounds can "hit" the gap between
  the hull and the sponsons. Hits are counted and flashed, but do no damage
  until Milestone 3.
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
