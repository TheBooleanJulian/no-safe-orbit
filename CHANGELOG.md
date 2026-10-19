# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
