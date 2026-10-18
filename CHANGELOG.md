# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
