# Known issues

Honest list of limitations in the current build. Design simplifications are
tabulated, with their consequences, in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **No human play-test yet.** Flight, the shipyard and combat were verified by
  automated tests, end-to-end smoke tests and reviewed renders — not by a person
  playing. Mouse and gamepad feel, readability of the orbit path and damage
  reports, and whether real-scale orbital drift matters in a fight are untested.
- **The enemy ship is only a gunner.** With T it turns and shoots and (from
  mission 3) launches a fighter; the ship itself doesn't manoeuvre, evade,
  manage heat or retreat. It is passive by default.
- **Craft are simple.** No formations, no landing-bay geometry or
  collisions; a recovered craft is serviced for free (its ammunition and
  propellant don't come from the carrier's stores). EW jamming exists only
  as a hook (Milestone 7).
- **The station is abstract.** The jump drive takes you there from anywhere
  out of combat; there is no station to fly to.
- **Loot balance is untested by play.** Rates, pity, costs and salvage yields
  are tested for correctness, not for fun; expect tuning.
- **Crew are abstract.** Roles, stations, routes and casualties are
  modelled; skills, morale, medical treatment in flight and individual
  equipment are not. The wounded only recover at the yard.
- **Only the player boards.** Enemies never board you yet, and the defender
  policy is fixed (security falls back to the bridge, doors ahead are locked).
- **Boarding balance is untested by play.** A full crew repels a full party;
  whether that is fun needs a person to try it.
- **One gun type per ship.** Mixed batteries (e.g. railgun + autocannon) are
  refused because one fire-control solution serves every mount.
- **Ship geometry is boxes with procedural plating.** Wrecked modules turn
  dark and destroyed external systems disappear, but nothing breaks off.
- **No point defence exists yet**; the weapon strip shows "PD none fitted"
  (Milestone 7).
- **Fonts:** Space Grotesk and JetBrains Mono are used when installed;
  otherwise the system's sans and monospace fonts stand in (nothing is
  bundled, to avoid a font dependency).
- **The tactical drawer covers the right side** (target card, hit cam,
  radar) while open; the TARGET tab shows the same information.
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
  the aim cursor itself is fixed to mouse movement (on a gamepad the aim is
  the screen centre).
- **Wedges are approximations in two places:** collisions and the blast treat
  a wedge cell as a full cell; the HUD damage map draws it as a full cell.
- **Older designs keep their legacy sections** and their automatic power
  distribution; convert them by rebuilding from blocks (the template shows
  how).
- **No audio.** (Milestone 8.)

## Fixed (2026-10-19, third pass)

Enemies vary and escalate by mission · salvage strips the wreck's best intact
rare part · Earth texture 5400 × 2700.

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
