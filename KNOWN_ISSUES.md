# Known issues

Honest list of limitations in the current build. Design simplifications are
tabulated, with their consequences, in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **No human play-test yet.** Flight, the shipyard and combat were verified by
  automated tests, end-to-end smoke tests and reviewed renders — not by a person
  playing. Mouse and gamepad feel, readability of the orbit path and damage
  reports, and whether real-scale orbital drift matters in a fight are untested.
- **The enemy is only a gunner.** With T it turns and shoots; it doesn't
  manoeuvre, evade, manage heat or retreat. It is passive by default.
  (Directives and tactics: Milestone 6.)
- **Docking is abstract.** B docks from anywhere; there is no station to fly
  back to, and propellant and ammunition are refilled free at every launch.
- **Loot balance is untested by play.** Rates, pity, costs and salvage yields
  are tested for correctness, not for fun; expect tuning.
- **Every enemy is the same Common-parts Kestrel**, and loot comes from crates
  rather than the wreck's own fitted parts.
- **Field repairs ignore crew.** Any workshop patches any reachable system,
  instantly staffed (crew roles and travel: Milestone 5).
- **One gun type per ship.** Mixed batteries (e.g. railgun + autocannon) are
  refused because one fire-control solution serves every mount.
- **Crew consequences are not modelled.** Breached rooms and rooms cut off from
  the bridge are reported, but nothing stops working because of them yet (M5).
- **Ship geometry is placeholder boxes.** Wrecked modules turn dark and
  destroyed external systems disappear, but nothing breaks off.
- **Earth's texture is 5400 × 2700 (~7.4 km per pixel)**, the October Blue
  Marble composite, with procedural detail on top; from 400 km straight down
  the ground is still a little soft. Clouds are procedural, not
  real weather. The Compatibility (OpenGL) renderer shows Earth slightly more
  saturated than Forward+.
- **Full Windows .exe export is unverified**: export templates aren't installed
  on the development machine. The data export is verified — every check run
  packs the project with the Windows preset and boots the game from the pack.
- **Shipyard: rotating or moving a module carries only what lies entirely
  inside it.** A room spanning two modules stays put (and the validator flags
  it). Carrying is ambiguous while modules overlap.
- **In-game rebinding covers keys, mouse buttons and gamepad buttons/axes**;
  the mouse virtual stick itself is fixed to mouse movement.
- **No audio.** (Milestone 8.)

## Design decisions (not defects)

- **No drag; the 100 km Kármán line is a hard entry interface** (decided
  2026-10-19). Crossing it removes the vessel or round; skimming above it costs
  nothing.

## Environment notes

- On Google Drive (or other Windows virtual drives) Godot logs
  `get_filesystem_type` errors at startup. Harmless; `run_checks.sh` ignores
  exactly that error. Drive can also briefly lock files during git operations;
  retry once the lock clears.
- In containers without a sound card Godot logs ALSA errors and falls back to the
  dummy audio driver. Harmless; `run_checks.sh` runs with `--headless`, which
  avoids it.
- If the Godot editor is open while `project.godot` changes on disk (e.g. new
  input actions), reload the project (Project → Reload Current Project) so the
  editor doesn't save its stale copy over it.

## Fixed (2026-10-19, second pass)

Undo/redo in the shipyard · modules carry their contents and turn in place ·
off-axis engine thrust torques the ship · propellant and Δv · gyroscopic
coupling · every cannon fires · hits use hull cells, not one box · ships go dark
in Earth's shadow · real Earth geography, rotating · real star sky · orbit path
dense near the ship · gamepad defaults and in-game rebinding · export includes
data files · dust no longer visibly repeats · Compatibility renderer checked ·
power and heat are networks, not just budgets.
