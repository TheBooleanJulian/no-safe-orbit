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
| `KineticCannonConfig` (Resource, `data/weapons/*.tres`) | Muzzle velocity, rate of fire, magazine, round mass, penetration (scales with impact speed^1.4). Rounds never expire. |
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
| `CelestialFrame` | Real sky for the scenario date: ICRS ↔ PCI, Sun direction, sidereal time, Earth-fixed frame, eclipse. |
| `ShipSystems` | Runtime condition of a blueprint-built ship: armour, structure, system hit points and power, room pressure, hatches, power networks, heat; effective flight config. |
| `Penetration`, `DamageReport` | Round-through-hull damage walk and its plain-words report. |
| `GunneryAI` | Enemy gunner: aim at the lead point, fire when aligned. |
| `InputBindings` | Player rebinding, saved to `user://input_bindings.cfg`. |
| `HitCam` (UI) | X-ray replay of the player's latest most-severe hit from the `DamageReport` path and events. |
| `Rarity`, `LootRoller` | Rarity tiers; cascading weighted loot with cascade-down and hard pity. |
| `PlayerProfile` | Persistent player state: spare parts, owned units, unlocked blueprints, pity, loot RNG, hangar vessel. Versioned JSON at `user://profile.json`. |
| `ShipInstance` | The physical hangar vessel: its blueprint copy, condition (from `ShipSystems.condition()`), sorties and service history. |
| `ServiceYard` | Repair and refit jobs, costs, priorities, write-offs. |
| `Salvage` | Salvage rules (disabled, < 500 m, < 5 m/s) and yield. |
| `CrewRoster` | People per berth: role, station, current room, state (fit / wounded / dead). |
| `Docking`, `DockingLink` | Ports, docking tolerances; the gangway (extend, seal, hold, sever). |
| `BoardingAction` | Muster, crossing, room-by-room fighting, capture, withdrawal. |
| `GangwayView` | Draws active gangways. |

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
  Earth's north pole is PCI −X, so the sandbox orbit is prograde and
  equatorial (see "Real sky").
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
  existing rounds (move, swept hits, near↔far hand-over, entry) → new rounds join →
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

## Real sky (CelestialFrame)

`CelestialFrame` ties the simulation's planet-centred inertial (PCI) axes to the
real sky for a scenario date (`Main.SCENARIO_EPOCH_UTC`, 2026-10-19 12:00 UTC):

- ICRS/J2000 → PCI: celestial north → PCI −X, vernal equinox → PCI +Y, then a
  twist about the pole that puts the Sun where the scenario wants it relative to
  the start point (15° behind zenith → ~24 min to sunset). The start orbit
  (PCI +Y, moving −Z) is therefore a **prograde equatorial** orbit.
- Sun direction and Greenwich sidereal time use the Astronomical Almanac
  low-precision formulas (Sun ~0.01°), tested against Meeus's worked examples.
  Precession, nutation and aberration are ignored (< 0.4° since J2000).
- The Earth-fixed frame (`pci_to_ecef`) turns at the sidereal rate; the sky
  shader samples the Blue Marble map with it.

## Rendering at planetary scale

- **Floating origin:** every view is placed at `local_position − player_position`,
  so render coordinates stay small.
- **Planet as sky:** Earth (NASA Blue Marble map in Earth-fixed coordinates,
  procedural detail and drifting clouds), the limb glow up to the 100 km entry
  interface and the Sun are ray-traced in `shaders/planet_sky.gdshader`. A
  sphere mesh cannot keep a round limb at 6,371 km and sits outside any sane
  depth range; as the sky it always draws behind ships, which is correct
  because nothing in play is ever below the entry interface. The map is
  sampled at an explicit LOD from the pixel footprint (no date-line seam);
  noise uses an integer (PCG) hash so lattice cells match bit-for-bit.
- **Stars** (`Starfield`, `shaders/stars.gdshader`): the 9,096 stars of the Yale
  Bright Star Catalogue at J2000 positions, camera-facing quads sized in pixels
  by magnitude and coloured by B−V. The shader discards stars behind the
  planet and dims stars seen through the limb (same geometry as the sky shader).
- **Eclipse:** the sun light's energy follows `CelestialFrame.sunlight_fraction`
  (cylindrical shadow, ±10 km soft edge) at the player's position.
- **Tracers** are emissive streaks widened with distance; glow makes them bloom.

## Ship systems and damage (Milestone 3)

`ShipSystems` is the runtime condition of a ship built from a blueprint; ships
flown from fixed configs (test fixtures) have none and keep the simple
bounding-box hit test.

- **Hits:** broad phase = bounding box (`HitTest`); narrow phase walks the hull
  cells along the round's swept segment (`Penetration.first_hull_entry`), so
  rounds through empty corners miss.
- **Penetration** (`Penetration.apply`): a millimetre budget walked cell by
  cell. Entering the hull → external system on that face, then module armour at
  `plate / cos(incidence)` (≤ 3×). Inside → 2 mm and 2 structure points per
  cell, rooms breach, bulkheads cost 8 mm and destroy any hatch in them,
  internal systems absorb their shielding as damage. Leaving → armour, then the
  external system on that face. Penetration at impact =
  `penetration_mm × (v / v_muzzle)^1.4`. Armour thins 3 mm per penetration and
  1 mm per stop. Every step is written to a `DamageReport`.
- **Power:** one distribution junction per module; junctions connect where
  modules attach (`ShipGrid.attachments`). A wrecked module (structure ≤ 0)
  isolates itself. Each network shares its reactors' output; a short network
  sheds loads in order: cannons, then main engines, then RCS (rooms last).
- **Heat:** one thermal mass (6.5 J/K per kg of ship). Generation follows use
  (reactor load × waste heat, engine throttle, RCS use, shots fired, rooms);
  rejection = (bare hull + working radiators) × (T⁴ − 250⁴)/(300⁴ − 250⁴).
  At ≥ 380 K the reactor throttles to 50 %, at ≥ 450 K it scrams, and it
  restarts below 360 K; at ≥ 520 K internal systems take damage.
- **Pressure and access:** a breached room vents; vacuum spreads only through
  destroyed hatches (intact ones seal). Crew can pass between pressurised rooms
  only; `cut_off_rooms()` lists those no longer reachable from the bridge.
- **Flight:** `effective_config()` rebuilds thrust, engine torque, RCS thrust and
  torque from what still works and is powered; dead or unpowered cannon mounts
  don't fire; a destroyed tank spills its share of the remaining propellant.
- **Enemy:** `GunneryAI` turns the nose onto the lead point (line-of-sight rate
  feed-forward plus proportional correction) and fires inside 0.35°. Same
  physics and limits as the player.

## Persistent rounds and impact physics

- **Rounds never expire.** Within 80 km of the frame origin a round is
  integrated like a ship (leapfrog with the tidal term, swept hit tests).
  Beyond that it goes *far*: its exact PCI state is kept in doubles and
  propagated analytically (`OrbitElements.propagate`, universal variables —
  elliptic, parabolic and hyperbolic), checked round-robin once per simulated
  second, and brought back to local integration inside 60 km. Far rounds
  re-enter at their predicted entry-interface time; escaping rounds beyond
  30 planet radii are dropped; at most 5,000 far rounds are kept (oldest
  first). A round cannot hit its own ship for its first 1 s.
- **Recoil:** each shot gives the ship `−m·v_muzzle` of momentum along the
  barrel and `−r_muzzle × p / I` of spin.
- **Impacts:** a hit transfers `m·Δv` at the hit point, scaled by the fraction
  of the round's penetration the ship absorbed, so the target is pushed and
  spun. A round that leaves the hull with penetration to spare flies on at
  `v × (pen_exit / pen_entry)^(1/1.4)`.

## Ship control, station economy and UI (2026-10-19)

- **Power** (`ShipSystems.pips`, `divert`, `channel_factor`): zero-sum pips;
  factor 0.5 + 0.25 × pips scales ENG → translation thrust and engine torque,
  WEP → rate of fire, SYS → RCS torque, assist turn rates and field-repair
  speed.
- **Ship AI**: without fit command crew on a pressurised bridge, thrust and
  turn rates × 0.5 and the world forces flight assist on for that ship.
- **Reactor explosion** (`ShipSystems._explode`): a reactor at 0 hit points
  damages modules (150 structure points × falloff), systems (90 hp × falloff)
  within 15 m and breaches rooms within 9 m; falloff = 1 − d/15. Chains.
  Reported in the hit report (`explosion` events) and drawn as a fireball.
- **Crew orders** (`cover_role`): the nearest free general crew member walks
  to the role's station and takes the role on arrival.
- **Economy** (`PlayerProfile` schema 2): salvage → `ShipInstance.cargo`
  (at risk); `bank_cargo()` → bank (spare parts, units, blueprints;
  duplicates scrapped at banking). `credits`: salvage bounty; respawn fee
  50 + 5 per berth; spare parts 10 for 25. Losing the vessel loses only the
  cargo; the same design is rebuilt (installed rare parts kept). Destroyed
  rare parts are rebuilt at their fitting cost, not written off.
- **Debrief** (`CombatLog`): per-sortie record (hits each way with the entry
  face, armour stops, systems lost, crew, explosions, boarding, salvage),
  saved as JSON; `CombatLog.insights()` turns it into lessons.
- **Enemies** (`EnemyFactory`): the template with parts swapped for rarer
  ones, chances rising per mission, deterministic per mission, validated.
- **UI** (`CyberTheme`, `ShipSchematic`, `TacticalOverview`, `DockingCam`,
  hit-cam boarding mode, `DebriefPanel`): cyan/magenta panels; the docking
  cam renders the main World3D from a second camera at the collar.
- **Ship look** (`ShipModelBuilder`): triplanar procedural plating, the name
  on the most exposed flanks, hazard-striped collars with beacons; RCS jets
  in `ShipView` from each block's share of commanded thrust and torque.

## Crew and boarding (Milestone 5)

- **Crew** (`CrewRoster`, owned by `ShipSystems`): one person per berth,
  default complement by role and station (see the class header). The access
  graph is rooms joined by hatches; `ShipSystems.route()` finds a way for
  unsuited crew (pressurised rooms only) or suited (any), past sealed doors
  only if destroyed. A room that depressurises wounds half (rounded up) of
  the people in it and kills the rest. Effects in `effective_config()`: no
  fit command crew on a pressurised bridge → ship AI (thrust, turn rates × 0.5); no fit
  weapons crew who can reach a magazine → rate of fire × 0.5. Field repairs
  take the nearest free damage-control (else engineering) member, who walks
  there (5 s per room) first. Casualties persist in the vessel condition by
  role; the wounded recover at docking; recruits cost 2 spare parts.
- **Docking** (`Docking`, `DockingLink`): ports are working docking collars
  (ours) and intact collars or room-backed outer hull faces (theirs).
  Tolerances: port gap ≤ 25 m, relative speed ≤ 0.5 m/s, turn rate ≤
  0.06 rad/s, ≤ 20° off square. Extending takes 10 s to a collar, 45 s to cut
  the hull (that room vents). Sealed: grapples cancel relative velocity with
  equal and opposite impulses each tick and co-rotate the target; needing
  more than 200 kN to hold, or ports out of reach, severs it. A target with
  power, thrust and a crew in command tries to break contact
  (`GunneryAI.break_contact`).
- **Boarding** (`BoardingAction`): up to 8 security/general crew muster at our
  collar, cross (5 s) and advance room by room towards the bridge. Defenders
  lock intact doors out of every room the boarders hold (20 s to cut); their
  security walk to the bridge (travel time; a vented route stops them). In a
  room with both sides, each side loses 0.08 × the other's strength hit
  points per second (strength by role; defenders × 1.25). Bridge held with
  no fit defender → captured (surrenders; salvage pays +2 crates). Withdraw
  only over a sealed gangway; otherwise stranded. Boarders left behind when
  the player docks are lost.

## Progression (Milestone 4)

- **Blueprint vs vessel.** `ShipBlueprint` is the design; `ShipInstance` is
  the hangar vessel — a copy of the design plus its *condition*:
  `ShipSystems.condition()` lists only what differs from new, keyed by stable
  part ids, as fractions (equipment hit points, module armour and structure,
  breached rooms, destroyed hatches). `apply_condition()` restores it on
  launch, so damage persists between sorties. The condition is captured when
  the sortie ends: dock (B), restart (Backspace), quit, or vessel loss.
- **Ownership.** Common parts are unlimited (fabricated). Rarer equipment is
  counted in units owned in total (installed or not); a design may use at
  most that many. Rarer hull modules and rooms are blueprints, unlocked once
  found. `PlayerProfile.check_design` adds `blueprint_locked` /
  `part_not_owned` errors to the validator report in the shipyard.
- **Losses** (revised later the same day, see "Station economy" above): a
  destroyed rarer unit is rebuilt at its fitting cost; losing the vessel
  loses only its cargo, and the same design is rebuilt for a credit fee.
- **Loot** (`LootRoller`): the tier climbs from Common with
  `Rarity.UPGRADE_CHANCE` (30/30/25/20 %), then pity (Rare+ by the 10th pull,
  Legendary by the 80th), then a weighted pick by `drop_weight` within the
  tier, falling to lower tiers if a tier is empty. The Common tier pays spare
  parts crates. The RNG seed and state are saved (as strings — 64-bit values
  don't survive JSON numbers), so reloading never re-rolls a pull.
- **Service costs** (spare parts): new equipment 1 per tonne (rarer: ¼, it
  comes from owned units), hull modules 1 per 4 t, rooms 1 per 2 t. Repair =
  new cost × damage fraction, so swapping a damaged part for a new one never
  beats repairing it. Refits (parts the vessel doesn't have) must be paid in
  full at launch; repairs are optional and chosen by priority when parts are
  short.
- **Salvage**: needs a disabled target (no power, no reachable command room,
  or every gun out), < 500 m and < 5 m/s. Yield: `10 + 50·f` spare parts and
  `1 + ⌊4f⌋` crates, `f` = surviving fraction of the wreck's system hit points.
- **Field repair**: a powered, pressurised, reachable workshop room lets the
  crew patch one damaged (not destroyed) reachable system at a time, to 75 %,
  taking 10 s + 1 s per hit point; it stops if access or the workshop is
  lost.
- **Saving**: `PlayerProfile.save()` writes a temporary file, then swaps it
  in. An unreadable profile is kept aside as `.unreadable`, never
  overwritten. Newer schema versions are refused.

## Propellant

Main engines and RCS have their own specific impulse (Frigate Mk I: 900 s /
300 s). Mass flow = F / (Isp · g₀); RCS rotation uses the thrust the torque
needs at the RCS's effective lever arm. Mass and inertia fall as propellant
burns; nothing fires with empty tanks. Δv left = Isp_main · g₀ · ln(m / m_dry).

## Simplifications in force (and their gameplay consequence)

| Simplification | Consequence | Revisit |
|---|---|---|
| Spherical Earth for gravity; no J2, no third bodies | Orbits never precess | If missions need ground tracks or long-duration accuracy |
| No atmosphere/drag: crossing 100 km = entry, vessel removed (design decision) | Skimming 100–120 km has no cost; dipping to 99 km is fatal | If aerobraking or reentry gameplay is wanted |
| Rounds inherit the ship's CoM velocity; muzzle velocity from rotation (ω × r) ignored | Firing while turning hard is slightly more accurate than reality | When weapon mounts gain turrets |
| Fire control assumes straight-line relative motion, no target acceleration | A manoeuvring target defeats the lead | Missiles / AI (M6–M7) |
| Diagonal inertia (principal axes = body axes) | Designs with skewed mass don't tumble off-axis | If asymmetric hull modules arrive |
| RCS blocks thrust equally in all six directions; torque = thrust × perpendicular lever arm | Block orientation doesn't matter | When RCS needs real quads |
| Centre of mass fixed at the full-tanks position | Burning propellant doesn't shift the CoM | If tank placement should matter in flight |
| Ammunition mass not counted | A full magazine weighs nothing | Logistics |
| Penetration is a millimetre budget, not ballistics: no spall cone, ricochet or fragmentation; armour per module, not per face | Damage is predictable and explainable, never surprising | M7 (fragmentation, nukes) |
| Overpenetrating rounds fly on slower but in a straight continuation; no deflection | Exit direction is always the entry direction | M7 (fragmentation) |
| Docking is abstract: B docks from anywhere; no station or transfer orbit | Returning costs nothing | When stations / logistics arrive |
| Propellant and ammunition are refilled free at every launch | Only damage and parts carry over | Logistics |
| Crew move abstractly (5 s per room); no skills, morale or in-flight medicine | Who is where matters; how good they are doesn't | Later |
| The grappled gangway forces equal velocities and turn rates (no compound-body dynamics) | Turning hard while docked can tear the gangway | If docked manoeuvring matters |
| Boarding fights are Lanchester attrition per room; fixed defender policy | Predictable, explainable outcomes | M6 (directives) |
| All gun mounts on a ship must be one type (one fire-control solution) | No mixed batteries | Turrets / per-mount fire control |
| Every enemy is the common-parts Kestrel; loot comes from crates, not the wreck's own parts | Salvage never returns a specific fitted part | When enemy loadouts vary |
| Wrecked modules stay attached; no debris | Ships never break apart | Later (structural detachment) |
| One power junction per module; no batteries, breakers or cabling; fixed shedding order | Redundancy comes from reactors and module layout only | M4/M5 (repairs, rerouting) |
| One thermal mass per ship; radiators can't retract | An idle ship settles at ~258 K; heat can't be stored locally | When heat sinks / radiator control arrive |

## Testing

- `tests/run_tests.gd` — headless runner; methods named `test_*` in
  `tests/unit/test_*.gd` (subclasses of `TestCase`). Failure messages state
  measured quantity, expected and actual.
- `tests/smoke/smoke_main.gd` — boots the real main scene and drives it via
  InputMap actions, including the hostile target hitting the player.
- `tests/smoke/smoke_shipyard.gd` — shipyard end to end: real mouse click on
  the deck editor, undo/redo by key, validation, save/reload, launch into
  flight, B back.
- `tests/smoke/smoke_campaign.gd` — the Milestone 4 exit test: fight, salvage
  with G, dock damaged with B, repair and refit in the shipyard, relaunch;
  then checks the profile on disk.
- `tests/smoke/smoke_boarding.gd` — the Milestone 5 exit test: docking
  refused out of tolerance, a live target tearing free, then seal, board,
  capture and salvage, with simulated time sped up while waiting.
- Smoke tests have a watchdog (120–180 s) so a script error fails the run
  instead of hanging it, and use a throwaway profile path.
- `tools/run_checks.sh` — runs everything, exports a `.pck` with the Windows
  preset and boots the game from it, and fails on engine errors in any log.
- `tools/capture_screens.gd` — renders scripted moments to PNG for visual review.
- Mutation checks: each core rule (tidal gravity, recoil, connector matching,
  parallel axis, exterior faces, armour obliquity, junction isolation, hatch
  destruction, AI feed-forward, self-hit arming, loot pity, loot RNG
  persistence, rare-replacement availability) was deliberately broken once;
  each time the matching test failed.
