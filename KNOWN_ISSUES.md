# Known issues

Honest list of limitations in the current build. Design simplifications are
tabulated, with their consequences, in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Open

- **Balance is still in development.** The play-test feedback pass retuned
  guns (equal damage rates, penetration tiers), magazines, engines, loot
  odds, the medic and crew sizes; hiring fees, quartermaster prices and
  upgrade costs are first guesses. Expect further tuning.
- **Fires, coolant loops and named crew are new** and covered by tests,
  not yet by play.
- **The release executables have not been exported or launched on the
  development machine**: Godot's export templates aren't installed there.
  The data pack is exported and booted on every check run; see
  `docs/STEAM.md` §3.
- **No application icon yet** (the Godot default is used); see
  `docs/STEAM.md` §6.
- **Derelicts are new** (Milestone 14): the yields, decay and how many are
  found are first guesses; a derelict is rebuilt from its design and worn
  to one overall figure, so it doesn't keep the exact damage it was left with.
- **Artifacts are new** (Milestone 14): survey fees, range and time are
  first guesses; the models are simple shapes at the real size. Depending
  on where the Sun is at the start, you may first see an object's dark
  side (the ISS starts in Earth's shadow at the scenario time).
- **Very large fights are still heavy**: four carriers with 46 craft out run
  at ~20 fps (slightly slower than real time), down from 7; the simulation
  is GDScript and each round, craft and missile costs microseconds.
- **Craft roles are new** (play-test batch 5): the interceptor, bomber,
  gun runs and avoidance distances are first guesses covered by seeded
  tests, not yet by play. Avoidance is a local nudge, so a craft can be
  pinned against a big hull for a moment.
- **Countermeasures are new** (Milestone 11): flare signature and burn
  time, seeker discrimination, jamming strength and the burn-through range
  are first guesses, covered by seeded tests, not yet by play.
- **Encounter balance is still being tuned** (play-test batch 6):
  `tools/balance_sim.gd` (a scripted player in a stock Frigate, no repairs)
  wins 1v1 in 3–10 s, survives 1v2 to the 480 s limit at missions 3 and 7
  (lost at 327 s at mission 5) and loses 1v3 at 188–273 s; a single gun
  knocked out early is still what decides most fights. Enemy armour grows
  with the mission number; salvo counts and intervals are first guesses.
- **Surface maps are 4–5 km per texel** (Moon and Mars 4096 px, Earth
  5400 px): from low orbit the ground looks soft, and crater rims blocky.
  Bigger maps would cost ~180 MB of video memory each, uncompressed.
- **Locations are new** (2026-10-20): jump costs, the reserve, the tow fee
  and the Lunar Shipyard's prices and traffic are first guesses. Upgrades
  are still the same at every station.
- **With the Tab drawer open the alert banner can overlap the top of the
  moved target card** (layout).
- **Audio is silent in headless runs** (tests and checks): the dummy
  driver never retires a playback, so ShipAudio skips playing there
  (`ShipAudio.silent`); the alert and ducking logic still runs and is tested.
- **Capital templates are plain**: generated slabs of hull blocks armed
  with standard parts (autocannons, point defence); no sloped bows or
  heavy guns until you refit them. Enemies don't field capital ships yet.
- **Contracts are new** (Milestone 12): payouts and threat levels are first
  guesses; a failed contract stays until it is met or abandoned.
- **Missions and the tutorial are new** (Milestone 8): rewards and the
  courier's toughness are first guesses; the tutorial is verified by tests
  and the smoke run, not yet by a new player.
- **Frame time is profiled by hand, not by the checks**:
  `tools/profile_frames.gd` needs a window and a GPU (75 fps mean, 95th
  percentile 20 ms on an RTX 3060 Ti against three ships, 50 missiles and
  ~380 rounds); `tools/bench_sim.gd` (in the unit tests) covers the
  simulation alone. A frame where many hits land at once can still take
  ~50 ms (catch-up ticks).
- **Missiles are new** (Milestones 7 and 9): ranges, prices, warhead
  strengths, the saturation swarm and the enemy's firing interval are first
  guesses, covered by tests, not yet by play. **M** and **,** have no
  gamepad default (every pad button is taken).
- **Wrecks** drift away at 4 m/s and only the four most recent are kept;
  they can still be shot but not salvaged again.
- **Older designs with odd-length sections:** "Convert to blocks" rebuilds the
  old large sections from blocks, but a section of odd length (the old
  3-long engine section) doesn't tile and stays as it was.

## Fixed (2026-10-20, README screenshots)

- **Debrief accuracy over 100 %:** missile strikes were counted as gun hits.
  They are counted separately now; accuracy is rounds only.

## Fixed (2026-10-20, play-test bugs)

- **Tab drawer lost the mouse cursor:** a click beside the open drawer (or
  the controls, loot or debrief panel) captured the mouse again. Clicks no
  longer capture while a panel is open, and the cursor stays free.
- **Armour stuck under a new deck or module:** a plate on a face you later
  built over stayed in the design (dead mass, impossible to remove). Covered
  plates now go with the edit (one undo step), designs and saves drop them
  on load, and the armour palette has **Clear all armour**.
- **Hatches outlived their room:** deleting a room now deletes its hatches
  (one undo brings both back).
- **Engine sound barely audible:** the rumble is fuller (brown noise, a low
  35–55 Hz hum and crackle), louder and rises a little with the throttle; it
  follows reverse and side engines too, and the RCS has its own quieter hiss.

## Fixed (2026-10-20, play-test feedback)

The user play-tested (the "no human play-test" item is closed). From the
57-point feedback list: rate of fire no longer compounds (bullets missing /
suddenly rapid fire) · enemy guns fire at the same rated rate as yours ·
hatch placement no longer flips up or down (middle = ladder up, Shift =
down) · building on the underside: a **Mount on: TOP / UNDERSIDE [V]**
toggle · the isometric view looks from the front-left and picks on the deck
floor · thin dark-grey armour and thin conduit no longer hide room names ·
disabled ships that tumble can be held steady with the grappling arm and
docked · the jump drive is only blocked while a hostile is actually firing ·
beacon loot goes into the hold · fewer empty crates.

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
- **Crew are named, with a role and a skill (0–2 stars)** — no morale or
  individual kit; the wounded recover with a medic aboard or at the yard;
  the dead leave their berths for new hires.
- **Coolant loops are optional:** a design with no pipes cools as before;
  once piped, only radiators on a reactor's loop work.
- **Penetration does not fall off with range** (vacuum); a head-on closing
  speed adds up to 30 %.
- **Ships are blocks with procedural plating.** A wrecked module breaks up
  visually (shrinks and sheds plating), but its cells still count in the
  damage model.
- **Sound is your own ship heard through the hull** (there is none in
  vacuum); an enemy's reactor going up is faint. Recorded CC0 samples,
  synthesis for any slot without one.
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
