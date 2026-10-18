# Architecture

Source-of-truth spec: [`GAME_DESIGN.md`](GAME_DESIGN.md). This file records how
the code actually implements it, and every simplification currently in force.

## Layers

```text
Input (InputMap) ──► PlayerInput ──► ShipControlInput ─┐
                                                       ▼
          WorldSimulation (fixed 60 Hz) ── LocalFrame.step()      (orbit origin)
                 │                     ── ShipDynamics.step()      (per ship)
                 │                     ── cannon fire, rounds, swept hits
                 │                     ── entry-interface check, rebase
                 │  owns ShipState[] by stable id, ProjectileState[]
                 ▼ read-only
   ShipView / ChaseCamera / DustField / PlanetSky / ProjectileView / HitFlashes / Hud
```

- **`scripts/simulation/`** is pure state + rules. It never touches nodes,
  meshes or the `Input` singleton, so it runs identically in tests, headless
  servers and (later) multiplayer authority.
- **Presentation** reads interpolated state each frame and never writes back.
- **`Main`** (`scripts/app/main.gd`) is thin wiring: sample input → advance sim
  → sync views → update HUD. It also builds the sandbox scenario.

## Core types (current)

| Type | Role |
|---|---|
| `ShipConfig` | Flight tuning: mass, inertia, per-direction thrust, torque, assist rates, hit box, cannon + muzzle position. Compiled from a blueprint by `ShipStats.to_ship_config()`; `data/ships/placeholder_frigate.tres` remains as a fixed fixture for flight unit tests. |
| `KineticCannonConfig` (Resource, `data/weapons/*.tres`) | Muzzle velocity, rate of fire, magazine, round mass, round lifetime. |
| `OrbitalBody` (Resource, `data/bodies/*.tres`) | μ, radius, entry-interface altitude (Earth: 100 km). |
| `ShipState` | Physical vessel: stable `id`, local position/velocity, orientation, body-frame angular velocity, last thrust/torque, Δv spent, status (active / entered atmosphere), cannon ammo and cooldown. |
| `ShipControlInput` | One tick's command: body-axis translation/rotation in [-1, 1], assist flag, translation hold (velocity or target id), trigger. |
| `ShipDynamics` | Static 6DoF integrator and flight-assist controller. |
| `LocalFrame` | Free-falling, non-rotating engagement frame. Origin PCI state in double precision; supplies the tidal acceleration. |
| `Vec3d` | Minimal double-precision vector for PCI quantities. |
| `OrbitElements` | Osculating orbit from a PCI state: apsides, period, true anomaly, time to apsis / to a radius, path points. |
| `ProjectileState`, `HitEvent` | Round in flight; recorded hit (body-frame point, relative speed, energy). |
| `HitTest` | Swept segment-vs-box test in the target's body frame. |
| `FireControl` | Straight-line intercept time and lead point. |
| `WorldSimulation` | Fixed-timestep clock, deterministic update order, frame, rounds, hits, entry check, rebasing, interpolation alpha. |
| `RelativeMotion` | Range, range rate, relative velocity. |

## Construction (Milestone 2)

```text
data/catalog/{hull,rooms,equipment}/*.tres ──► ConstructionCatalog
data/blueprints/*.json, user://blueprints/*.json ──► BlueprintIO ──► ShipBlueprint
                                                                          │
     ShipGrid (cell occupancy) ◄──────────────────────────────────────────┤
          │                                                               │
          ├──► ShipValidator → Report (ERROR blocks launch, WARNING = trade-off)
          └──► ShipStats (mass, CoM, inertia, thrust/torque, power, heat,
                          crew, rounds, cargo) ──► to_ship_config() ──► flight
ShipEditor (scripts/shipyard): edits a blueprint, re-derives the above
Shipyard UI: palette, DeckEditor, OrthoView ×2, ShipPreview3D, panels
```

| Type | Role |
|---|---|
| `HullModuleDefinition`, `RoomDefinition`, `EquipmentDefinition` (Resources) | Immutable parts. Modules: size in cells, mass, per-face connectors, pressurised or not, armour. Rooms: role and per-cell mass/power/heat/capacity. Equipment: internal (room roles) or external (faces), mass, power, heat, thrust, cannon. |
| `ConstructionCatalog` | Loads every definition by scanning `data/catalog/*/`; adding a part is adding a `.tres`. |
| `ShipBlueprint` | The design: placed modules (cell, quarter-turn rotation), rooms (deck + rectangle), hatches (two cells), equipment (cell [+ face]). Stable string ids. `to_dict`/`from_dict` with `schema_version`. |
| `ShipGrid` | Which module/room/equipment occupies each cell; overlaps and unknown ids recorded. Face/rotation helpers. |
| `ShipValidator` | Structure (overlap, attachment graph through matching connectors), rooms (inside pressurised hull, no overlap), hatches, equipment mounting, crew access from the bridge, systems warnings. |
| `ShipStats` | Derived engineering numbers and the flight `ShipConfig`. |
| `BlueprintIO` | JSON files. JSON, not `.tres`: a shared blueprint is plain data and cannot run code on load. |
| `ShipEditor` | UI-free editing operations + "what errors would this placement add?" preview. |
| `ShipModelBuilder` | Placeholder 3D geometry from a blueprint, shared by flight and shipyard. |

Grid conventions: a cell is a 3 m cube; `Vector3i(x, deck, z)` with +x
starboard, +deck up, +z aft — so the nose is at low z and grid axes equal body
axes (body origin = centre of mass). Module rotation is quarter turns about +Y,
counter-clockwise from above (fore → port → aft → starboard).

The shipyard draws the deck with the nose to the right and starboard down; side
view nose right; front view seen from ahead (starboard on the left).

Scene flow: flight (`main.tscn`) ⇄ shipyard (`shipyard.tscn`) via
`change_scene_to_file`; the design crosses over in `Main.launch_blueprint`.

## Conventions

- **Units:** SI throughout — metres, seconds, kilograms, newtons, N·m, kg·m²,
  radians internally (HUD converts to °/s and km for display only).
- **Axes (body and world):** Godot convention — +X right, +Y up, **−Z forward**.
  Rotation commands follow the right-hand rule: +X pitch up, +Y yaw left,
  +Z roll left.
- **Planet-centred inertial (PCI) axes** are the world axes: the local frame
  does not rotate. The sandbox starts at PCI (0, R+400 km, 0) moving along −Z,
  so at the start the planet is straight "down" and prograde is "forward".
  The planet's pole is PCI +X (the sandbox orbit is equatorial).
- **Identity:** ships are keyed by `StringName` ids, never by node path.
- **Tuning** lives in `.tres` resources, not literals in logic.

## Time

- `WorldSimulation.advance(frame_delta)` accumulates real time and runs whole
  fixed steps (`1/60 s`), returning an interpolation alpha for rendering.
  Tested: identical state for steady vs jittery frame pacing.
- At most 8 catch-up steps per frame; excess time is discarded and counted in
  `dropped_time` (prevents the spiral of death after a hitch).
- Input is sampled once per rendered frame and held across that frame's ticks.
- Tick order: frame origin → ships (in id order; firing spawns rounds) →
  existing rounds (move, swept hits, lifetime, entry) → new rounds join →
  entry-interface check → rebase.

## Orbital precision: the free-falling local frame

Godot's `Vector3` is 32-bit: at Earth-orbit radius (6.8×10⁶ m) that is ~0.5 m
resolution, far too coarse to integrate. The implementation:

- `LocalFrame` holds an origin position and velocity in **planet-centred
  inertial coordinates, in double precision** (`Vec3d`; GDScript `float` is
  64-bit). The origin free-falls (kick-drift-kick leapfrog).
- Ships and rounds keep **small 32-bit offsets** from that origin. Their local
  acceleration is thrust plus the tidal term `g(origin + x) − g(origin)`,
  computed entirely in doubles. This is exact for a free-falling, non-rotating
  frame: origin + offset follows true two-body motion, and the ship integrator
  is effectively leapfrog in PCI.
- When the player is more than 5 km from the origin, the origin moves onto the
  player (**rebase**); every local position shifts by the same amount. The
  origin keeps its own velocity, so local velocities, the dust cue and flight
  assist do not jump. `rebase_offset` keeps a continuous coordinate for the dust.
- Measured: 10 orbits with 486 rebases, radius within 6.8×10⁻⁷ and energy within
  1.7×10⁻⁷ (dt 1 s); 6.4×10⁻⁸ energy over one orbit at 60 Hz.

"Local velocity" (HUD, dust) is therefore velocity relative to a free-falling
reference near the player — after a burn it reads the Δv you added. Orbital
speed, apsides and prograde use the full PCI state.

## Rendering at planetary scale

- **Floating origin:** every view is placed at `local_position − player_position`,
  so render coordinates stay small.
- **Planet as sky:** Earth, the limb glow up to the 100 km entry interface, the
  sun and the stars are ray-traced in `shaders/planet_sky.gdshader`. A sphere
  mesh cannot keep a round limb at 6,371 km without thousands of segments and
  sits outside any sane depth range. As the sky it always draws behind ships,
  which is correct because nothing in play is ever below the entry interface.
  Surface noise uses an integer (PCG) hash so lattice cells match bit-for-bit
  on the GPU; a float hash showed block seams.
- **Tracers** are emissive streaks widened with distance so they stay a few
  pixels wide; the environment's glow makes them bloom.

## Simplifications in force (and their gameplay consequence)

| Simplification | Consequence | Revisit |
|---|---|---|
| Spherical, non-rotating Earth; no J2, no third bodies | Orbits never precess; the surface doesn't turn under you | If missions need ground tracks or long-duration accuracy |
| No atmosphere/drag: crossing 100 km = entry, vessel removed | Skimming 100–120 km has no cost; dipping to 99 km is fatal | If aerobraking or reentry gameplay is wanted |
| Ships lit by a fixed sun; no eclipse shadowing | Ships stay lit on the night side; only the planet shows night | Presentation polish (M8) |
| Rounds inherit the ship's CoM velocity; muzzle velocity from rotation (ω × r) ignored | Firing while turning hard is slightly more accurate than reality (~1 % lateral at 0.5 rad/s) | When weapon mounts are placed (M2/M3) |
| Hit box is one oriented box per ship | Hits register on empty space between sponsons; no localised damage yet | M2 (hull modules) / M3 (damage) |
| Fire control assumes straight-line relative motion, no target acceleration | Lead is exact for coasting targets over seconds (tidal error ~cm); a manoeuvring target defeats it | Missiles / AI (M6–M7) |
| Diagonal inertia, gyroscopic term (ω × Iω) ignored | Multi-axis tumbles don't precess; asymmetric designs spin "too cleanly" | M3 or when it visibly matters |
| Thrust and torque are independent budgets; engine thrust off the CoM is only a shipyard *warning* | Off-axis engines don't actually make the ship turn in flight | M3 (placed-thruster dynamics) |
| RCS blocks thrust equally in all six directions; torque = thrust × perpendicular lever arm | Block orientation doesn't matter; no per-nozzle layout | When RCS needs real quads |
| Power and heat are ship-wide budgets (one shared bus); no wiring or coolant loops | A deficit is a warning, not a failure; cutting a cable does nothing yet | M3 (power and thermal graphs) |
| Hull modules are boxes; collision is one box around the whole hull | Hits land on empty corners of the bounding box | M3 (hits resolved against module cells) |
| Only the first cannon is flown | Extra cannons add mass/power/heat but don't fire | When weapon groups exist |
| Ammunition mass not counted | A full magazine weighs nothing | M3/M4 (inventory) |
| Δv is counted, propellant is not modelled | No fuel limit yet; Δv spent is shown so the cost of assist is visible | Propellant graph (M3/M4) |
| Rotation: semi-implicit Euler | Fine for the current rates; untested for long, fast tumbles beyond normalisation | If gyroscopic coupling lands |

## Testing

- `tests/run_tests.gd` — headless runner; methods named `test_*` in
  `tests/unit/test_*.gd` (subclasses of `TestCase`). Failure messages state
  measured quantity, expected and actual.
- `tests/smoke/smoke_main.gd` — boots the real main scene and drives it via
  InputMap actions.
- `tests/smoke/smoke_shipyard.gd` — shipyard end to end: real mouse click on
  the deck editor, validation, save/reload, launch into flight, B back.
- Both smoke tests have a 120 s watchdog so a script error fails the run
  instead of hanging it.
- `tools/run_checks.sh` — runs everything and also fails on engine errors in logs.
- `tools/capture_screens.gd` — renders scripted moments to PNG for visual review.
- Long orbit tests use a 1 s step for 10 orbits (≈2 s run time); one full
  orbit also runs at the real 60 Hz step. The unit suite takes ≈15 s.
