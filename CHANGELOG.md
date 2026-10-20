# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### README screenshots (2026-10-20)

#### Added
- Gameplay screenshots in the README (flight, gunnery, missile salvo,
  damage control, crew, debrief, shipyard) and `tools/capture_readme.gd`,
  which renders them on a scratch profile.

#### Fixed
- Debrief accuracy counted missile strikes as gun hits (e.g. "48 hits from
  7 rounds, 686 %"); missile strikes are now counted on their own
  ("18 missiles launched, 41 struck") and accuracy is rounds only.

### Milestone 9 — play-test batch 2: salvos, wrecks, crew (2026-10-20)

#### Added
- Missile salvos: M fires every missile the mode allows (all,
  conventional, EMP, nuclear, or a sequence in a chosen order); `,` cycles
  the mode; Tab › WEAPONS shows launchers, mode and order. Saved.
- Saturation missile pod (rare): 48 small missiles, 8 per launch.
- Missiles shot down or self-destructing break up in a fireball with sound;
  small warheads show as fireballs.
- Crew: Tab › CREW reorganised — crew map with post-coloured dots, roster
  tree by post (who, where, status), one "send to" control; boarders shown
  as dots on the target map and in the boarding view; the station's crew
  list grouped by post against the standard complement.
- The target card says how many boarders would go before N.

#### Changed
- Launchers hold more (rack 12, EMP 6, nuclear 3) and cycle a launch every
  0.4 s; restocking is cheap (8 / 20 / 150 cr, saturation 2).
- Beaten contacts stay as silent derelict wrecks (guns, point defence and
  craft stop) that drift clear, instead of vanishing.
- Boarding party limit 24 (enemy parties stay at 8).
- Our own missiles are small unlabelled HUD markers; our launches no longer
  flood the ticker.

### Milestone 8 — vertical-slice polish (2026-10-20)

#### Added
- Mission chain with stated goals and rewards: disable, capture, escort a
  courier, survive two waves, then patrols. Shown on the HUD (gold, top
  centre), in the hangar and in the debrief.
- Opt-in guided first sortie (F2): fly, aim, fire, disable, salvage, jump,
  repair — prompts advance on what the player does; skippable; saved.
- Debrief opens with a sortie summary (goal, dealt, taken and from where,
  systems lost, crew); hit-cam caption says how the round got in and lists
  what it broke with state glyphs.
- `tools/bench_sim.gd`: simulation frame-time profile under load (two
  frigates, every gun, 12 missiles; ~1 ms a tick with 200+ rounds).

#### Changed
- Save hardening: profile schema 5 (tutorial and mission progress); a save
  is read back before it replaces the profile, the previous save is kept as
  `.bak`, a damaged profile is replaced by its backup with a clear message,
  an interrupted save is finished on the next start, and an older schema is
  copied aside before migrating.
- Design tokens follow the design system: void #050508, surface #0A0E14,
  teal #00D4C8, gold #F5C842 (magenta and red stay as hostile/danger states).

### Milestone 7 — EMP and advanced weapons (2026-10-20)

#### Added
- Guided missiles: launchers (missile rack, EMP launcher, nuclear launcher;
  uncommon / rare / legendary), fired with **M** at the U target. Missiles
  are small ships in the simulation: proportional-navigation guidance,
  arming, a swept proximity fuse, self-destruct; rounds and point defence
  shoot them down.
- Warheads: anti-ship (penetrator plus blast), EMP (resets unhardened
  electronics, which recover on their own), nuclear (radiation dose behind
  the facing armour, heat, ablation close in, EMP; no momentum).
- EMP hardening: hardened sensor mast and power distribution unit; reactors
  half-hardened.
- HUD: `MSL` weapon-strip entry, MISSILE INBOUND danger alert, EMP RESET
  caution, MSL markers; missile views with exhaust, blue EMP ring, white
  nuclear flash; launch and detonation sounds.
- Enemies carry a missile rack from mission 4 (EMP launcher sometimes from
  mission 6) and fire it with a lock inside 12 km.
- Spent missiles persist in the vessel's condition and are restocked at the
  yard for credits (shown in the hangar's resupply line).

#### Changed
- Enemy gun upgrade: the heavy kinetic cannon (the template already carries
  autocannons).

### Play-test bug fixes (2026-10-20)

#### Fixed
- Tab drawer (and the controls, loot and debrief panels): a click no longer
  re-captures the mouse while a panel is open.
- Armour plates covered by a newly built deck or module are removed with
  that edit (same undo step), and dropped from designs and saves on load.
- Deleting a room deletes its hatches (one undo restores both).
- Engine sound: fuller, louder rumble that rises with the throttle and
  follows every main engine (reverse and side ones too); new RCS hiss.

#### Added
- Shipyard armour palette: **Clear all armour** (undoable).

### Play-test feedback pass (2026-10-20)

#### Added
- Controls: W/S pitch, A/D yaw, Q/E roll, R/F main engine / reverse, IJKL
  strafe; X cycles hold orbit → match target → target markers (yellow
  markers without matching velocity); wheel zoom levels while zoomed;
  closest-approach (CPA) line on the target card; U cycles the lead target
  through enemy craft; craft markers in sensor range.
- Grappling arm (Y): steadies a tumbling ship, matches velocity, lines up
  collars for a gangway, siphons a hulk's propellant and rounds.
- Emergency jump: leaves craft and boarders behind, with a red countdown.
- Crew: spacesuits at general quarters, damage control seals breaches,
  named crew, hiring, shipyard role changes and in-flight reassignment.
- Quartermaster (rarer parts for credits) and upgrades (ship technology,
  captain's training).
- Fires and automatic foam suppression; optional auto-routed coolant loops.
- Main engines on any face with an engine room inside; high-thrust engine.
- Cutter Mk I and Corvette Mk I templates (common parts only).
- Shipyard: zoom/pan, click-and-drag moves, CoM marker [C], top/underside
  toggle [V], rotate/flip buttons; same-type rooms side by side join up.
- Visuals: 3-cell accordion radiators, triangular wedge-side plates, open
  truss lattice, charred/buckled worn plates, rotating radar array, windows
  and running lights that go dark without power, room colours in the
  schematic and hit cam, centre-screen red alerts, smaller dimmer far tracers.

#### Changed
- Guns: light autocannon common (45 mm, 120 rpm), heavy kinetic uncommon
  (90 mm, 60 rpm), railgun 220 mm at 24 rpm — similar damage rates; no
  penetration fall-off; magazines hold mass, not rounds.
- Armoured propellant tank 40 mm; crew quarters 3 berths a cell; medic
  25 s a patient; bigger bridges, workshops and life support work faster.
- Craft carry 1.5× fuel and ammo; crate loot odds 60 % / 90 %.
- Engines balanced on thrust × Isp; owned rare parts usable on any vessel.
- Profile schema 4: saves using the once-common heavy cannon keep their
  units. Boot checks use a throwaway profile, never the real save.

#### Fixed
- Rate of fire compounding on every recompute (no bullets / sudden bursts).

### Added
- Enemies board a disabled player (from mission 2); crew defence policy
  (hold the bridge / counter-attack); V cuts their gangway.
- Point-defence turrets (two on the Frigate Mk I) engage hostile craft.
- Shipboard sound, synthesised at startup.
- Shipyard: move groups of modules (Shift-click, Ctrl+A); convert old
  sections to blocks.
- Medics treat the wounded in flight; craft fly in formation.

### Fixed
- The drawer keeps the target card in view; collisions respect wedges;
  a magazine and lead marker per gun type; wrecked modules break up.
- The enemy uses its power pips and works round to your stern.
- Propellant and rounds carry over between sorties and are bought back at
  launch (credits); craft refuel and rearm from their carrier's stores.
- The enemy keeps a fighting range, jinks, holds fire when hot and flees
  when beaten (escapes beyond 40 km).
- Mixed gun batteries: each mount keeps its own gun and, with a lock, its
  own lead.

## [0.10.0] — 2026-10-20 — Operations pass: turrets, blocks and armour, power bus, jump drive

### Added
- Turrets: every gun trains on the mouse aim at its own traverse rate and
  fires once on target; per-gun reticles; guns hold fire when their own hull
  is in the way. Mouse aim cursor; right-drag camera orbit; Shift zoom toggle
  centred on the aim.
- Scans (lock + sensor mast, 4 s): approximate cargo, scrap value, bounty.
- Ship-to-ship collisions with ramming damage.
- Dimensional jump drive (hold B 5 s, out of combat) to Earth Shipyard.
- Salvage beacon (50 % scrap) vs boarding takeover (80 % scrap, better
  crates into the hold, automatic withdrawal); cargo capacity and venting;
  loot carousel; loot tables in the shipyard; DEV +100 cr.
- Hull building blocks (2×2×1 pressurised, 1×2×1 / 1×1×1 wedges, 1×2×1
  truss); angled armour; painted 40 / 80 mm plates.
- Player-routed power bus with distribution units; auto-route.
- 2-cell radiators; internal fighter bay and hangar; models for the sensor
  mast, docked drones, hangar doors, fighter and drone.
- Isometric shipyard view (edits too); build new ships into a hangar fleet.
- Reactor explosion effect and camera shake.

### Changed
- A/D yaw (strafe while the docking camera is up); R/F only for up/down.
- Kinetic cannon 50 rpm, 48 mm; ship AI keeps the guns at half rate.
- Gangway attached: primary weapons locked. Contacts turn hostile when hit.
- Modules attach on any common face; underside equipment placement fixed.
- Passive hull cooling per exposed face; reactor blast scaled per module.
- Profile schema 3 (hangar of vessels); blueprint schema 2 (flips, plates,
  bus).

## [0.9.0] — 2026-10-19 — UI simplification and polish

### Added
- Design tokens (`CyberTheme`) and a code-built Theme; state glyphs.
- Consolidated HUD: own-ship card with actionable alerts, target card with
  sensor-track quality (MEAS / EST / STALE), confidence and lock, weapon
  strip, event ticker; orbit (O), details & combat log (J), help (H).
- Damage-control drawer with clickable schematic and contextual actions
  (dispatch repair, switch loads off to reroute power, divert, isolate).
- Shipyard: searchable categorised palette, key figures, expandable views,
  tabbed hangar (Service / Cargo & Bank / History), primary Launch.
- Sensor mast and tracks; contacts arrive far out and must be detected
  before they engage.
- Ricochets with visible deflected tracers; black hull entry/exit holes.
- Shift zoom for gunnery; yellow target-relative markers in match mode.

### Changed
- RCS Isp 900 s (heavy 950 s): manoeuvring no longer burns more propellant
  per m/s than the main engines.

## [0.8.0] — 2026-10-19 — Milestone 6: fighters, drones and directives

### Added
- Wasp fighter and recon drone on external racks (Frigate Mk I carries
  both); craft fly in the same physics, have hull hit points and can be
  shot down.
- Directives (intercept, strike with subsystem priority, recon, escort,
  return), risk tolerance and automatic disengagement, comms fallback.
- Launch / recovery / servicing; craft losses and damage persist and are
  replaced or repaired at the station. L / K; air-wing controls in Tab.
- Recon drones give the close look at the target's systems.
- Enemy fighters from mission 3.
- `test_air_wing.gd` (11), `smoke_wing.gd`.

## [0.7.0] — 2026-10-19 — Ship control, station economy, cyberpunk UI

### Added
- Power distribution (1/2/3/4), crew orders (cover lost roles), damage
  control pick, boarding party size; tactical overview (Tab).
- Ship AI flies a ship whose bridge crew is lost (half thrust and turn
  rate). Reactors explode at 0 %.
- Station: cargo hold (salvage at risk until banked), credits (bounties,
  spare parts shop), respawn fee; death loses only the cargo and rebuilds
  the same design. Combat log and debrief with lessons for the shipyard.
- Always-visible damage map, boarding overlay in the hit cam, docking cam.
- Procedural hull plating, ship names on the hull, hazard-striped collars
  with beacons, white RCS jets, reactor fireballs.
- Enemies vary and get tougher by mission; salvage strips the wreck's best
  intact rare part.

### Changed
- Medium kinetic cannon: 1000 m/s, 120 rpm (was 1500 m/s, 240 rpm).
- Cyan/magenta UI throughout. The shipyard is the station.
- Destroyed rare parts are rebuilt instead of written off.

## [0.6.0] — 2026-10-19 — Milestone 5: crew and boarding; real-season Earth

### Added
- Abstract crew: roles and stations per berth, routes through the access
  graph (5 s per room, suits for vacuum), casualties when rooms vent,
  command and gun-crew effects, crewed field repairs with travel time,
  casualties saved with the vessel, recruits at the yard.
- Docking collar (Frigate Mk I has one); docking tolerances; gangways that
  mate to collars or cut into the hull; grapples that hold, and tear when a
  target thrusts away; the target AI tries to break contact.
- Boarding: muster, cross, fight room by room (Lanchester attrition, locked
  doors to cut, defenders falling back to the bridge), capture, withdraw,
  stranding; capture bonus on salvage. V / N, HUD lines, gangway tube.
- `test_boarding.gd` (12), `smoke_boarding.gd`.

### Changed
- Earth texture: NASA Blue Marble NG October composite, 5400 × 2700.
- Docking heals the wounded; the stored condition can include crew losses.

## [0.5.0] — 2026-10-19 — Persistent rounds, hit cam, Milestone 4 + loot

### Added
- Rounds never expire: far from the fight they coast on exact two-body
  orbits (`OrbitElements.propagate`) and come back; HUD counts rounds near /
  in far orbit and warns of incoming rounds; a ship can be hit by its own
  returning rounds.
- Recoil and impact physics: firing pushes and spins the firing ship; hits
  push and spin the target; overpenetrating rounds fly on, slower.
- Hit cam: X-ray replay of your latest most-severe hit and the modules it
  damaged.
- Milestone 4 — persistence and recovery: player profile and hangar vessel
  saved as versioned JSON; damage persists between sorties; salvage of
  disabled enemies (G); spare parts; shipyard HANGAR & SERVICE panel with
  priority repairs; paid refits at launch; write-offs for rarer parts lost in
  flight or with the ship; workshop field repairs (C).
- Loot with cascading weighted rarity (Common → Legendary, 30/30/25/20 %
  climb), cascade-down past empty tiers, hard pity (Rare+ / 10, Legendary /
  80), published rates; 14 rarer parts: equipment (railgun, light autocannon,
  torch drive, high-Isp engine, heavy RCS, compact and Mk II reactors,
  heat-pipe radiator, armoured tank), hull blueprints (armoured fuselage and
  nose, monocoque fuselage) and room blueprints (workshop, dense magazine).
- Validator: `blueprint_locked`, `part_not_owned`, `mixed_cannon_types`.
- `smoke_campaign.gd` (M4 exit test); `test_rounds.gd`, `test_progression.gd`.

### Changed
- B docks the ship (its damage is kept); Backspace and quitting dock first.
- Rarity colours in the shipyard palette; owned counts and locked blueprints.

## [0.4.0] — 2026-10-19 — Real sky, known-issue fixes, Milestone 3

### Added
- Real sky for the scenario date: the 9,096 stars of the Yale Bright Star
  Catalogue (J2000), the Sun's true direction, Earth's pole and sidereal
  rotation (`CelestialFrame`, tested against Meeus); NASA Blue Marble
  geography; eclipse darkens ships in Earth's shadow; HUD sunset/sunrise.
- Milestone 3 — damage and ship systems: hull-cell hit detection, armour
  penetration with obliquity, damage along the round's path, room breaches
  and hatch sealing, crew access cut-offs, power networks through module
  junctions with load shedding, ship heat with reactor throttle/scram and
  over-temperature damage, damage-reduced flight config, readable damage
  reports, destroyed parts shown on the model.
- Enemy gunner (T): aims at the lead point with line-of-sight feed-forward.
- Propellant and Δv: tanks, engine/RCS Isp, falling mass, empty = no thrust.
- Shipyard undo/redo; modules carry their contents and turn in place.
- Gamepad defaults; in-game rebinding (F1), saved per user.
- Windows export preset; checks export a .pck and boot from it.

### Changed
- Sandbox orbit is prograde equatorial (it was retrograde relative to Earth's
  spin once the sky was made real).
- Off-axis engine thrust now torques the ship; rotation includes the
  gyroscopic term (RK4); every cannon mount fires.
- Two dust layers so the field no longer visibly repeats.

### Fixed
- Enemy aim lagged crossing targets by rate/gain (~0.6°) and stopped firing;
  feed-forward removes the lag.

## [0.3.0] — 2026-10-19 — Milestone 2: ship blueprint and builder

### Added
- Construction model (`scripts/construction/`): hull module, room and
  equipment definitions (`data/catalog/`), `ShipBlueprint` (versioned JSON),
  `ShipGrid`, `ShipValidator` (errors block launch; warnings are trade-offs),
  `ShipStats` (mass, CoM, inertia, thrust/torque from placed thrusters,
  power/heat, crew/rounds/cargo) compiled into the flight `ShipConfig`.
- Frigate Mk I template (`data/blueprints/frigate_mk1.json`): 392 t, six
  modules, eleven rooms, full crew access, validates with no issues.
- Shipyard (`scenes/shipyard/`, `scripts/shipyard/`): palette, deck grid
  editor (place / select / move / rotate / remove / hatches), placement
  ghost that names the error before you click, side and front views, 3D
  preview, live stats, clickable validation panel, save/load, templates,
  launch (blocked while errors exist).
- Flight: ships are built from their blueprints (geometry and numbers);
  `B` opens the shipyard with the flown design.
- Tests: `test_blueprint.gd` (22), `test_ship_editor.gd` (5),
  `smoke_shipyard.gd` (15 checks); 120 s watchdog on both smoke tests.

### Changed
- The player and target fly the compiled Frigate Mk I instead of the fixed
  placeholder config (which remains as a test fixture).

## [0.2.0] — 2026-10-19 — Milestone 1b: Earth orbit, cannon, fire control

### Added
- Real-scale Earth (`data/bodies/earth.tres`): two-body gravity, 100 km
  Kármán-line entry interface. Sandbox starts in a 400 km circular orbit.
- `LocalFrame`: free-falling, double-precision engagement frame with tidal
  acceleration and automatic rebasing on the player (`Vec3d` for PCI maths).
- `OrbitElements`: apsides, period, time to apsis, time to entry interface,
  projected path points.
- Atmospheric entry: ships and rounds crossing 100 km leave the engagement;
  the HUD predicts it ("ENTRY IN m:ss") and shows a loss screen. Backspace
  restarts.
- Kinetic cannon (`data/weapons/medium_kinetic_cannon.tres`): inherited
  velocity, recoil, rate of fire, magazine, round lifetime; rounds feel
  gravity. Swept hit tests (no tunnelling), hit events and flashes.
- Fire control: intercept time and lead pip; round TOF in the target panel.
- Flat radar (bearing, range, elevation stalk, closing/opening, motion tail).
- Orbit panel (altitude, orbital speed, Ap/Pe with times, period, entry
  status), projected orbit path with Ap/Pe/entry markers, entry warning banner.
- Planet, limb glow, sun and stars rendered as a ray-traced sky shader.
- Input actions: `fire` (LMB, Enter), `toggle_velocity_hold` (X),
  `restart_scenario` (Backspace).
- Tests: `test_orbit.gd`, `test_weapons.gd`, `test_radar.gd` (46 unit tests
  total); smoke test extended to 14 checks.

### Changed
- Godot 4.7.2 (was 4.5.1).
- Flight assist: holds the current orbit by default (no translation damping,
  no Δv while coasting); X switches to matching target velocity.
- Ship translation integrates with kick-drift-kick leapfrog.
- Prograde/retrograde markers show orbital velocity.
- Dust field stays continuous across frame rebases.

### Removed
- Mesh starfield (replaced by stars in the sky shader, which can be hidden by
  the planet).

## [0.1.0] — 2026-10-19 — Milestone 0 + Milestone 1a

### Added
- Godot 4.5.1 project "No Safe Orbit" with rebindable InputMap actions.
- Simulation core (`scripts/simulation/`): `ShipConfig` resource, `ShipState`,
  `ShipControlInput`, `ShipDynamics` (6DoF, per-direction thrust limits,
  flight assist and manual modes), `WorldSimulation` (fixed 60 Hz timestep,
  interpolation, catch-up cap), `RelativeMotion` (range, range rate).
- Placeholder frigate tuning data: `data/ships/placeholder_frigate.tres`
  (250 t, 1 g main engine, 0.2 g RCS).
- Flight sandbox scene: player frigate, passive drifting target, chase camera,
  floating render origin, wrapping dust field, starfield, twin engine plumes.
- HUD: velocity (total and per body axis), angular rates, Δv spent, sim clock,
  assist state; target range / range rate / relative speed; heading reticle,
  prograde/retrograde markers, target bracket with off-screen edge arrow,
  mouse virtual-stick indicator; on-screen controls help.
- Test harness: `tests/run_tests.gd` (20 unit tests), `tests/smoke/smoke_main.gd`
  (end-to-end through the real scene), `tools/run_checks.sh` (also fails on
  engine errors in logs), `tools/capture_screens.gd` (visual review frames).
- Docs: README, GAME_DESIGN (title set to NO SAFE ORBIT), ARCHITECTURE,
  ROADMAP, KNOWN_ISSUES.

### Fixed
- HUD overlay built a negative-size `Rect2` on viewports smaller than the edge
  margin (caught by the log-error gate in headless runs).
