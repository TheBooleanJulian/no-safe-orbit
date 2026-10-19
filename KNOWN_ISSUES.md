# Known issues

Honest list of limitations in the current build. Design simplifications are
tabulated, with their consequences, in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **No human play-test yet.** Flight, the shipyard and combat were verified by
  automated tests, end-to-end smoke tests and reviewed renders — not by a person
  playing. Mouse and gamepad feel, readability of the orbit path and damage
  reports, and whether real-scale orbital drift matters in a fight are untested.
- **Balance is untested by play.** Loot rates, pity, costs, salvage yields,
  resupply prices, boarding (a full crew repels a full party) and point
  defence are tested for correctness, not for fun; expect tuning.
- **EW jamming exists only as a hook** for craft communications (Milestone 7).
- **Older designs with odd-length sections:** "Convert to blocks" rebuilds the
  old large sections from blocks, but a section of odd length (the old
  3-long engine section) doesn't tile and stays as it was.

## Fixed (2026-10-20, second pass)

The damage-control drawer no longer hides the target card (it moves beside
the drawer) · collisions treat wedges as solid only below their slope · a
magazine and a lead marker per gun type · medics treat the wounded in flight
· craft fly in formation · the enemy spends its power like a fighter and
works round to your stern · enemies board a beaten player, and you choose
the crew's defence (hold the bridge or counter-attack) · groups of modules
(Shift-click, Ctrl+A) move with everything inside them · old sections convert
to blocks (free on your own vessel) · wrecked modules break up and shed
plating · point-defence turrets engage hostile craft · shipboard sound.

## Fixed (2026-10-20)

Propellant and rounds are no longer refilled for free: they carry over and
are bought back at launch · craft refuel and rearm from the carrier · the
enemy manoeuvres, cools and runs · mixed gun batteries · cargo capacity ·
B no longer docks from anywhere (jump drive, out of combat) · underside
equipment placement · connector mismatches.

## Fixed (2026-10-19, third pass)

Enemies vary and escalate by mission · salvage strips the wreck's best intact
rare part · Earth texture 5400 × 2700.

## Design decisions (not defects)

- **No drag; the 100 km Kármán line is a hard entry interface** (decided
  2026-10-19). Crossing it removes the vessel or round; skimming above it costs
  nothing.
- **The station is reached by jump drive**, not flown to (decided 2026-10-20).
- **Crew are roles, not characters:** no skills, morale or individual kit;
  the wounded recover with a medic aboard or at the yard.
- **Ships are blocks with procedural plating.** A wrecked module breaks up
  visually (shrinks and sheds plating), but its cells still count in the
  damage model.
- **Sound is your own ship heard through the hull** (there is none in
  vacuum); an enemy's reactor going up is faint. Synthesised, no audio files.
- **On a gamepad the guns aim at the screen centre**; the aim cursor follows
  the mouse.
- **Fonts:** Space Grotesk and JetBrains Mono are used when installed;
  otherwise the system's fonts stand in (nothing is bundled, to avoid a font
  dependency).

## Environment notes

- On Google Drive (or other Windows virtual drives) Godot logs
  `get_filesystem_type` errors at startup. Harmless; `run_checks.sh` ignores
  exactly that error. Drive can also briefly lock files during git operations;
  retry once the lock clears.
- In containers without a sound card Godot logs ALSA errors and falls back to the
  dummy audio driver. Harmless; `run_checks.sh` runs with `--headless`, which
  avoids it.
- **Earth's texture is 5400 × 2700 (~7.4 km per pixel)**, the October Blue
  Marble composite, with procedural detail on top; from 400 km straight down
  the ground is still a little soft. Clouds are procedural. The Compatibility
  (OpenGL) renderer shows Earth slightly more saturated than Forward+.
- **Full Windows .exe export is unverified**: export templates aren't installed
  on the development machine. The data export is verified — every check run
  packs the project with the Windows preset and boots the game from the pack.
- If an export fails to find a newly added resource, delete its stale copy
  under `.godot/exported/` and export again.
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
