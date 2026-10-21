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
real sky for a scenario date (`Main.SCENARIO_EPOCH_UTC`, 2026-10-19 12:00 UTC)
and the location's central body:

- ICRS/J2000 → PCI: the body's equatorial frame (its north pole, and its
  equator's ascending node on the ICRS equator, from the `OrbitalBody`'s IAU
  pole) maps with the body's north → PCI −X, then a twist about the pole that
  puts the Sun where the scenario wants it relative to the start point (15°
  behind zenith → ~24 min to sunset). The start orbit (PCI +Y, moving −Z) is
  therefore a **prograde equatorial** orbit about any body. For Earth (pole
  ICRS +Z) this is the original mapping, tested against its old numbers.
- The Moon's pole and prime meridian (Archinal et al. 2018) include only the
  largest periodic term (E1, the node's 18.6-year cycle), evaluated at the
  epoch: the pole lands 1.51° from the ecliptic pole (Cassini state ~1.54°).
- Sun direction and Greenwich sidereal time use the Astronomical Almanac
  low-precision formulas (Sun ~0.01°), tested against Meeus's worked examples.
  Precession, nutation and aberration are ignored (< 0.4° since J2000).
- The body-fixed frame (`pci_to_body_fixed`, W = W0 + rate · days) turns at the
  body's sidereal rate (for Earth W = GMST − 90°); the sky shader samples the
  body's `surface_map` with it.

## Locations and the map (2026-10-20)

- `Location` (`data/locations/*.tres`, listed in `Location.FILES` so exports
  find them): station name, `OrbitalBody`, circular start altitude, map
  position and colour. Earth orbit (400 km, Earth Shipyard) and lunar orbit
  (100 km, Lunar Shipyard).
- `OrbitalBody` carries gravity (μ, radius), the entry interface (an
  atmosphere's top, or the terrain floor for an airless body:
  `has_atmosphere`, `entry_word()`), IAU rotation and the surface map.
- `PlayerProfile` (schema 7) keeps `location` (where the vessel is docked),
  `known_locations` (Earth and the Moon from the start; brokers sell more in
  Milestone 13) and `encounter_size` (1–3). `relocate()` refuses unknown ids.
- Shipyard HANGAR › MAP (`SystemMap`): click a body → `relocate`, save; three
  toggle buttons set the encounter size. The route button beside LAUNCH
  shows both and opens the tab.
- **Jumps (Milestone 13)**: `JumpDrive` (data `data/jump/jump_drive.tres`):
  `cost_kg(mass, distance)` = t × (base + per-decade × log10(1 + d / 1000 km));
  `pay(main, reserve, cost)` takes the main tank first; `tow_credits(mass)`.
  The reserve is `reserve_fraction` of the tankage, kept in the vessel's
  `condition.stores.jump_reserve_kg` (schema 9) and in `Main.jump_reserve_kg`
  during a sortie. `PlayerProfile.relocate(id, catalog)` charges the docked
  vessel (`vessel_tanks`) or refuses with the refuel price;
  `ContractBoard.accept` refuses when it does. `Main.pay_jump_home` charges
  the B jump and an alive-ship restart, or tows (credits, floored at 0).
  `ServiceYard.resupply_needs` includes `reserve_kg`.
- **Sun-centred positions (Milestone 13 part 2)**: `CelestialFrame.KEPLER_ELEMENTS`
  (Standish, 1800–2050, J2000 ecliptic) → `heliocentric_icrs(ephemeris, jd)`
  as `Vec3d` (Earth = barycentre − Moon / 82.3; Moon = Earth + the lunar
  series; Mars from its elements); `separation_m` for jump distances
  (`Location.distance_m`, at `Main.SCENARIO_EPOCH_UTC`); `sun_direction_from`
  (the Almanac's Sun for Earth and the Moon, unchanged; the elements
  otherwise), used by `for_scenario` and `sun_direction_pci`.
  `geocentric_icrs` covers Mars for completeness.
- **Artifacts (Milestone 14)**: `Artifact` (`data/artifacts/*.tres`,
  listed in `Artifact.FILES`): Horizons state (km, km/s, ICRF) about
  `center` at `epoch_utc` (the scenario epoch), source, uncertainty, size,
  mass, fee, record. `PlayerProfile.survey_target` / `codex` (schema 10),
  `choose_survey` (location rule; deep-space round trip ≤ full tanks +
  reserve, `survey_cost_kg` = 2 × `JumpDrive.cost_kg`), `complete_survey`.
  `Main` reads the target in `_ready`: a deep-space one swaps the location
  for `Location.deep_space(home)` (the Sun, `is_star`; station name from
  home). `_start_scenario` spawns the anchor `START_BEHIND_M` back along
  the object's velocity (`icrs_to_pci_d`, doubles), sets the star frame's
  Sun from that point (`set_star_sun`), spawns the object (`ARTIFACT_ID`,
  `ship_config()`: hull_hp 0 → undamageable, neutral, derelict) instead of
  the encounter, and pays the deep-space round trip (`_jump_prepaid`, so
  `pay_jump_home` is free). `_update_survey` accumulates sim time while in
  range, slow and with a mast; HUD `survey` / `artifact_id` drive the
  survey card, marker and SURVEY alert. Restart after a survey reloads the
  scene (back to the home location). `ArtifactView` draws a procedural
  model by kind. Star centre: `OrbitalBody.shadow_radius_m()` /
  `disc_radius_m()` are 0 (no shadow, no planet disc); the sky's Sun disc
  scales with `CelestialFrame.sun_distance_m`, never below a pixel.
- **Derelicts (Milestone 14 part 2)**: `DerelictField` records in
  `PlayerProfile.derelicts` (schema 11): {id, location, name, template,
  mission, variant, intact, salvaged, age}. `Main._update_derelict_field`
  (from `close_sortie`, after docking or loss) updates the flying ones'
  `intact`, ages everything (`age_all`: ×0.85, break-up < 0.1 or age 8),
  then records this sortie's retired wrecks (`_wreck_meta`, salvaged 1) and
  disabled contacts (salvaged 0). `_spawn_derelicts` rebuilds the newest
  two with `EnemyFactory.design(mission, template, variant)` and
  `wreck_to` (hit points set directly: no reactor blast; seeded), neutral
  and derelict, at `spawn_offset`. G with nothing to beacon salvages the
  nearest in reach (`salvage_derelict`: `resalvage_yield`, strip, once per
  sortie). HUD `derelict_ids` marks them.
- **Builder palette (play-test batch 6)**: `Shipyard.palette_place(kind, def)`
  → [category, section] (`CATEGORIES`, `SECTIONS`); `_fill_palette_list`
  sorts rows by category, section, rarity, mass and adds non-selectable
  header rows; long radiators get two rows whose metadata carries a preset
  `place_rotation` (0 along, 1 across). `palette_items()` lists pickable rows.
- **Hull visuals (play-test batch 6)**: armour plates use
  `ShipModelBuilder._armour_mat` (gunmetal, metallic 0.75, one panel per
  cell); a wrecked module's mesh becomes `ShipModelBuilder.dented()`
  (subdivided, inner face points pushed in, edge and corner points fixed)
  at full scale.
- **Beam weapons (play-test batch 6)**: a `KineticCannonConfig` with
  `beam_range_m > 0` (`is_beam`, `beam_penetration_at`, `beam_color`;
  muzzle speed = c so fire control leads by nothing). `_update_cannon`
  queues a pulse instead of spawning a round (a ship's beam needs no rounds;
  a craft's spends a charge) and holds it while the lead target is beyond
  reach; `_fire_beam` resolves the queue after every ship has moved,
  against their start-of-tick poses (`prev_position/prev_orientation`):
  bounding sphere → hit box → `Penetration.first_hull_entry` from the box
  entry (the grid walk is 512 cells) → `Penetration.apply` (no ricochet, no
  impulse). Within `BEAM_STEER_DEG` of the barrel a beam is laid on a
  craft or missile target. `ShipState.beam_pulses` → `ShipSystems.tick`
  heat (mount `heat_kw` × interval per pulse); beams take no magazine share
  beside other guns. `take_beams()` → `BeamView` (pooled cylinders, body-frame
  ends, 0.18 s fade). `AirWing._resupply_from` recharges beam craft without
  drawing the carrier's magazine.
- **Capital templates (play-test batch 6)**: generated by
  `tools/make_capital_templates.gd` (prow taper `_row_blocks`, wedges ahead
  of each step, a two-deck superstructure, flank/top/bow armour `_armour`,
  long parts claim their whole span). `ServiceYard.dealer_price` adds
  `units` (`rare_units` at `PlayerProfile.VENDOR_PRICES` × margin);
  `PlayerProfile.buy_ship` banks them. `ChaseCamera.fit_to(hull bounds)`
  scales its offsets above a frigate's size.
- **Brokers**: `Location.broker_price/name/pitch`;
  `PlayerProfile.brokers()` and `buy_location()` add to `known_locations`
  (already saved, so no schema change). Shipyard MAP lists them.
- **Bodies**: `OrbitalBody.air_color` and `clouds_and_seas` drive the sky
  shader's `air_color`, `has_clouds` and `far_has_clouds` (clouds and sea
  glint off on Mars).
- **Per station** (`Location`): `vendor_stock_size`, `vendor_max_rarity`,
  `price_factor` (quartermaster and hiring, applied in
  `PlayerProfile.refresh_station`), `enemy_templates` / `enemy_weights`
  (seeded per mission and slot by `enemy_template`) and `threat_bonus`
  (added to the mission number in `Main._spawn_encounter`).
- `Main` reads the location in `_ready`: central body and start orbit,
  celestial frame, sky (`PlanetSky.configure(body)`: radius, entry radius,
  air on/off, surface map), stars' occlusion, eclipse, station names (HUD
  `station_name`). `EnemyFactory.encounter_size(chosen)` clamps the pick.

## The station (Milestone 12, 2026-10-20)

- `ShipyardSections` turns the shipyard into a station: a station directory
  (play-test batch 6; it replaced a rail of section tabs) beside full-width
  pages. `DIRECTORY` groups the sections into districts with place names;
  `directory_status()` gives each its live line and whether it needs the
  player (skipped in REFIT, where the directory narrows — the builder
  refreshes on every edit). The berth (STATION) is a `ShipPreview3D` with
  `berth = true` (docking-bay set dressing) filling the page, with overlaid
  cards and the dockmaster's log (`_dock_log`); the CREW page is a roster
  board of department cards and a hiring hall. The builder's body is the REFIT page, and the
  builder's top-bar controls and keys work only there. The old right-hand
  tabs' pages were moved into their sections (SERVICE → REPAIRS, CARGO &
  HISTORY → HANGAR, QUARTERMASTER → ARMOURY, …). New pages: STATION (3D
  preview and status cards), MISSIONS, DEALER (a 3D preview per template)
  and the fleet cards in HANGAR.
- Economy (`ServiceYard`): `parts_value` (a whole ship's parts) feeds
  `dealer_price`: (parts × 2.5 cr + hull fee) × 1.25, plus crew × hiring
  fee. `scrap_value` is (parts − repairs) × 0.5 in spare parts.
  `PlayerProfile.buy_ship` / `scrap_vessel` use them.
- Contracts (`ContractBoard`): seeded offers (profile `board_seed`, sorties
  flown) from five givers. `accept` sets `active_contract`, the location
  and the encounter size. Main runs it through `MissionChain.contract`
  (goal, brief, reward); `complete` pays and clears it without advancing
  the chain. The contract's `threat` replaces the mission number for enemy
  designs. Profile schema 8.
- Capital templates are generated (`tools/make_capital_templates.gd`) and
  written only when the validator finds nothing. `CrewRoster` indexes
  rooms by role once per roster, making a 300-module hull's crew linear.

## Countermeasures and EW (Milestone 11, 2026-10-20)

- **Flares:** `WorldSimulation.decoys` holds flares as plain records (id,
  side, owner, position, velocity, age, life, signature). They drift in
  the local frame, ride rebases and burn out. `launch_decoys` fires every
  ready `DECOY_LAUNCHER` once; flare use is kept in `missiles_used`, so it
  saves, resupplies and prices with the missiles (`ServiceYard.FLARE_CREDITS`).
- **Seekers** (`_update_seekers`, before guidance): a missile weighs each
  enemy flare once, when the flare is inside its cone
  (`MissileConfig.seeker_cone_deg`) and no further than 1.5 × its target.
  The chance is `seduction_chance` = s_flare / (s_flare + s_ship ×
  discrimination), with `signature_of` growing with mass^(1/3) and engine
  burn. The roll is seeded by the (missile, flare) pair. A seduced missile
  guides on the flare and bursts on it. When its flare burns out it
  re-acquires the ship only inside its cone, else it is lost and
  self-destructs 3 s later.
- **Jamming:** `jamming_of(ship)` is the ship's working `JAMMER`s plus EW
  craft of its side within `EW_ESCORT_M`. `jam_effect` is noise × (1 −
  resist) × a 0 → 1 ramp from `BURN_THROUGH_M` to `JAM_FULL_M`. It feeds
  two places:
  - `SensorTrack.update(…, jamming)`: confidence × (1 − 0.75 × effect), no
    lock under 0.45; the resist is the best mast's EMP hardening.
  - Missiles: a seeded 10 % × effect chance a second to lose lock (the
    resist is `MissileConfig.jam_resist`).
- **Automation:** `ShipPolicy.cm_auto` / `cm_lead_s` (additive keys,
  defaults from the preset). `Main._auto_countermeasures` runs them for the
  player and every live contact; Space fires manually (`fire_countermeasures`).
  `DecoyView` draws flares.

## Alerts and audio (Pass A, 2026-10-20)

- `Hud._alerts` reports every condition each frame as an `AlertQueue.Alert`:
  key, class (threat, damage, systems, nav, info), level (advisory,
  caution, danger), a noun, one value, a bearing, a key chip, the
  system or room it is about, and a body-frame direction for threats.
- `AlertQueue` (pure logic, tested) deduplicates by key and keeps an alert
  up for 0.8 s after its condition clears. It raises a level at once and
  lowers it after 1 s, and shows at most three, sorted by level, class and
  age. Non-danger alerts can be acknowledged. `raised` lists new or
  escalated alerts so Main can sound them (`ShipAudio.alarm`).
- What the HUD does with them: the banner shows the visible alerts as
  chips, and the attention line repeats a danger. The overlay draws
  threat chevrons (`HudOverlay.threats`), and the damage map flashes the
  top alert's subject (`ShipSchematic.alert_id`). The own-ship card's
  STATUS line is computed directly (reactor, breaches, fires, vented
  rooms).
- `ShipAudio` takes samples from `data/audio` (CC0, in `SAMPLES` / `ALARMS`)
  with synthesis as the per-slot fallback. It has three buses: Effects,
  Alarms and Ambience. An alarm plays 1–3 blips by level and ducks Effects
  and Ambience by 9 dB until 0.8 s after its last blip. Headless runs don't
  play anything (the dummy driver never retires playbacks); every stream
  is stopped and released on exit.

## Frame-time performance (2026-10-20)

Measured with `tools/profile_frames.gd` (opens a window; per-section times
from `Main.frame_ms`, per-phase tick times from `WorldSimulation.take_phase_ms`,
renderer CPU/GPU time, spike frames, a mesh census):

- **Rounds broadphase:** a uniform grid (256 m cells) of ships, rebuilt each
  tick with each ship's swept box padded by the fastest round's step; a
  round tests only the ships in its cell.
- **Caches with explicit invalidation:** `ShipSystems.disabled_reason()`
  (every state-changing entry point calls `_state_changed()`), docking hull
  ports per ship (blueprint-only). `Docking.best()` ranks pairs on range and
  alignment and assesses only the winner.
- **HUD:** the orbit path (~260 Kepler solves) and the orbit panel refresh
  every 200 ms; between refreshes the path is shifted by the render
  origin's movement (`HudOverlay.orbit_offset`).
- **Merged meshes:** `ShipView` hides each module and plate node and draws
  them as one `ArrayMesh` (a surface per material) built from cached
  ship-space triangle lists (`ShipModelBuilder.flat_arrays`); wear and
  wrecks edit the hidden nodes, recompute only those pieces' triangles and
  concatenate. External systems' fixed pieces are merged at build time
  (`_merge_static`); pivots, turntables and beacons stay separate.
  `MissileView` shares one body mesh per side.
- **Logging:** `GameLog.hold(true)` during flight; Main flushes once a frame.

Play-test batch 6 (2026-10-21), "lag when thousands of rounds are fired by
many fighters" — `profile_frames.gd -- --carrier` (own Carrier against three
frigates) and `-- --carriers` (four carriers, 46 craft):

- **Sleeping rounds** (`WorldSimulation._safe_ticks`): a round that can't
  reach any ship's hit sphere (less a 150 m margin) within up to 60 ticks
  only coasts — no hit test, no tidal term — and settles the tidal pull on
  waking (trapezoid over the sleep). A round in a broadphase cell with ships
  stays awake without being measured for 4 ticks. 53–83 % of round-ticks
  sleep. Awake rounds reuse the tidal pull from the end of their last tick
  (invalidated by a frame rebase), and test each ship's bounding sphere
  before its box.
- **Point defence** gathers trackable rounds and air targets once per tick
  and filters by distance before hostility. Its gun fires a third as many
  rounds (300 rpm, 0.3 kg, 18 mm; flak radius 2.6 m): PD rounds had been
  69 % of everything in flight.
- **Craft** think every 2 ticks (staggered; every tick within 300 m of their
  rack on the way home) and work out avoidance every 4.
- **Collisions** pair only ships with hulls with everything else, distance
  before the string checks.
- **Tracers** are built on the GPU: each instance carries its position and
  relative velocity; the vertex shader turns and sizes the streak.
- **The HUD ship schematic** redraws at 10 Hz (a Carrier's was ~9 ms a frame).
- **Catch-up** is capped at 3 ticks a frame (was 8; still 8 under a
  deliberate fast-forward, `Engine.time_scale` > 1, as in the smoke tests):
  overloaded, the fight runs slower than real time instead of the frame
  rate collapsing.

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
- **The other body** (`Location.sky_body`): `CelestialFrame.position_of` places
  it (the Moon by the Astronomical Almanac low-precision series, Earth as the
  Moon's opposite) and `body_fixed_of` turns its map; the sky shader ray-traces
  it in units of its own radius (metres lose the disc to float precision at
  384,000 km) behind the near body's limb, lit by the Sun (so it shows its
  phase), and hides the Sun behind it. The stars shader discards stars behind
  it. From afar, Earth's clouds are domain-warped and latitude-banded (only
  their coarse octaves survive); up close they are unchanged.
- **Reflected light:** `CelestialFrame.reflected_fraction` (geometric albedo ×
  (R/d)² × phase law) gives each body's light on the other; `PlanetSky`
  maps it to shown brightness (`perceived_light`: night adaptation, full Moon
  = 5 % of the Sun, Stevens exponent 0.5) and feeds the shader (`near_fill`
  on the central body's night side, `far_fill` as earthshine on the far
  body) and `Main.sky_light` (a light-only directional light on ships, 0
  while the source is below the horizon).
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

## Sensors, hits and UI (2026-10-19, UI pass)

- **Sensors** (`SensorTrack`): range = best working sensor mast (25 km)
  else 3 km visual. Measured inside range; otherwise dead-reckoned from the
  last measurement (stored relative to the observer, so frame rebases don't
  move it), stale after 2 s, confidence halving every 15 s; lock inside
  10 km. Main keeps a track each way; a contact engages only after the
  player has detected it (5 s grace) and it has the player in its own
  sensors. Contacts after a salvage arrive 30 km out at 150 m/s.
- **Ricochets** (`Penetration.RICOCHET_MIN_DEG` 60°): stopped by the first
  plate at ≥ 60° incidence, the round is mirrored about the plate at 55 %
  of its relative speed; the plate takes the momentum change.
- **Hull holes**: reports carry outward entry/exit normals; ShipView adds
  black discs (exit: wider, ragged), at most 80 per ship.
- **UI tokens** (`CyberTheme`): colours, sans/mono fonts (Space Grotesk /
  JetBrains Mono when installed, system fallbacks otherwise), spacing, panel
  surfaces, state glyphs, and a Theme built in code that the HUD and the
  station use. `ShipSchematic` lays out its hit areas (`layout_hits`) for
  clicks; the drawer (`TacticalOverview`) works from them.
- **Damage-control actions** (`ShipSystems`): `set_switched_off` (a load
  takes no power, freeing it for others; reactors can't be switched) and
  `set_isolated` (crew routes avoid the compartment; suited boarders still
  cut through).

## Operations pass (2026-10-20)

- **Turrets** (`WorldSimulation._train_turret`): each blueprint gun mount
  keeps a barrel direction (`ShipState.turret_dirs`) and trains towards the
  input's aim point at `KineticCannonConfig.traverse_deg_s`, limited to above
  its face plane (`TURRET_ARC_MIN_DOT`). It fires only within 0.3° of the aim
  and when a ray from its barrel clears its own hull (cached per ~0.3° of
  movement). Status per mount (READY / SLEWING / BLOCKED / OUT_OF_ARC /
  OFFLINE / LOCKED) drives the HUD reticles. Craft and fixtures keep fixed
  nose guns. Spread: the gun's own plus the ship AI's.
- **Collisions** (`_step_collisions`): bounding spheres, then hull-cell
  probes; an impulse with restitution 0.2 along the centre line, a push
  apart, and impact energy ½μv² shared by (mass × local armour)^1.5;
  3 points per 100 kJ, 60 % to the nearest module, 40 % over the modules
  within three cells (by distance), 60 % to external systems within two
  cells.
- **Hull blocks**: `HullModuleDefinition.shape` (box / wedge), `legacy`.
  Wedges are solid below a plane (`ShipGrid.wedge_contains`, normal
  `wedge_normal`); `Penetration._solid_span` finds where a ray actually
  enters a cell's solid part, so a slope is met at its own incidence.
  `PlacedModule.flip` turns a wedge upside down.
- **Plates**: `ShipBlueprint.armor` (plate key → mm) on exterior faces; a
  wedge's slope plate is stored under its top / bottom face
  (`ShipGrid.plate_face`). Penetration adds plate to skin; wear comes off
  the plate first (`ShipSystems.plates`, persisted as fractions).
- **Power bus**: `ShipBlueprint.bus` (cells). `ShipSystems._solve_bus_power`
  floods conduit networks (6-neighbour, skipping cut cells and wrecked
  modules); a network's reactors feed it only through a working
  POWER_DISTRIBUTION unit. Passive systems need no conduit. Penetrating
  rounds cut a conduit cell with 25 % chance from the ship's seeded
  generator. No conduit at all = the old module-junction networks.
- **Economy**: `Salvage.scrap_value` (build cost × condition × 2.5 cr),
  beacon / takeover rates, `PlayerProfile.open_crates` (chance per crate),
  cargo volumes (`ShipInstance.cargo_volume_m3`, `vent_excess`), hangar of
  vessels (`vessels`, `active_vessel`, `commission`).
- **Jump drive** (`Main._update_jump`): hold `open_shipyard` 5 s; blocked by
  `in_combat()`, waits on `jump_waiting()`.
- **Isometric view** (`ShipPreview3D`, `isometric` + `editable`): picks on the
  edited deck's plane and emits the deck editor's signals.

## Play-test feedback pass (2026-10-20)

- **Controls**: `PlayerInput.build_input` maps strafe J/L, I/K and R/F
  (forward / reverse) to translation, W/S A/D Q/E to rotation.
  `VelocityHold` has a third value, TARGET_MARKERS (coast; markers relative
  to the target, `target_relative()`). `ZOOM_LEVELS` sets the zoomed FOV.
  `RelativeMotion.closest_approach` feeds the CPA line.
- **Config recompute**: `ShipSystems.effective_config` duplicates the base
  config shallowly, so `ShipConfig.scale_rate_of_fire` must replace
  `mount_cannons` (a fresh array), never write into it — writing compounded
  the scaling on every recompute.
- **Guns and magazines**: `KineticCannonConfig.penetration_at` is the rated
  value, plus up to `HEAD_ON_BONUS_MAX` for a fast closing impact.
  `RoomDefinition.ammo_kg_per_cell` → `ShipStats.magazine_kg`;
  `ShipStats.rounds_from_mass` shares the mass by mount count and divides by
  round mass; `ShipState` shares rounds between calibres the same way.
- **Engines on any face**: `ShipConfig.engine_thrust_n` (six directions,
  `ShipStats.engine_slot`) adds to `max_thrust`; non-aft engines need an
  `engine_room` under the mount (validator `engine_needs_engine_room`).
- **Grapple** (`Grapple`, `WorldSimulation.grapples`, `grab`): an
  EquipmentDefinition.Kind.GRAPPLE mount; stepped with the links each tick;
  grappled ships don't collide (`_linked`).
- **Coolant** (`CoolantLoop`, `ShipBlueprint.coolant`): optional cells like
  the bus. `cooled_radiators` floods pipes from reactor cells; stats,
  validator (`radiator_uncooled`) and `ShipSystems.radiator_cooled` use it;
  hits cut pipes (`coolant_cut`, persisted, re-run by the yard's bus job).
- **Rooms**: `ShipGrid.open_rooms` joins same-type rooms side by side on a
  deck (crew routes, reachability, venting, validator access).
  `ShipSystems.room_bonus(role)` (1 + 25 % per extra cell, ≤ 2×) speeds
  scans (bridge), repairs and sealing (workshop) and treatment (life
  support). `suited` (general quarters) lets the crew route through vacuum
  and survive venting. `_advance_hull_sealing` clears breaches.
- **Fire** (`ShipSystems.fires`, `foam_used`): started from
  `damage_equipment` with the ship's seeded generator; burns only in
  pressurised rooms; foam charges persist in the condition.
- **Crew and station** (`ShipInstance.crew`, `CrewRoster.from_plan`,
  `PlayerProfile.hire_pool / vendor_stock / tech`, `TechTree`): an empty
  crew list means the standard complement; `ensure_crew` names it once.
  Docking removes the dead from the list (`bury_dead`). Upgrades reach the
  player's ShipSystems as `tech` (`tech_factor`).
- **Jump drive**: `in_combat()` = a hostile fired within `UNDER_FIRE_S`
  (`_note_enemy_fire`); at full charge it always jumps, leaving
  `jump_waiting()` behind.
- **Profile v4**: `NO_LONGER_COMMON_V4` grants units of parts that stopped
  being common to saves whose designs use them (`grant_used`).
  `Main.get_profile` honours `-- --profile=PATH` (the checks' throwaway).

## Missions, tutorial and saves (Milestone 8)

- **`MissionChain`** (`scripts/progression/`): the goal list and its
  rewards; `PlayerProfile.campaign = {step}`. Main reports events —
  `contact_beaten()` (first disable, or a capture of a ship not yet
  disabled), `contact_captured()`, `escort_lost()` — and calls
  `_complete_mission()` when one returns true. The escort's courier is a
  craft-like `ShipState` (no systems, hull points) that the engaging enemy
  targets instead of the player while it lives.
- **`Tutorial`**: `{state, step}` in `PlayerProfile.tutorial`; `observe(facts)`
  advances past every step whose fact holds, in order. Main feeds facts each
  frame (Δv spent, lock, hits scored, contact beaten, salvaged) and on the
  jump; the shipyard feeds "no repairs needed" for the last step.
- **HUD guide**: `Hud.guide_lines` (goal, tutorial prompt) in a panel under
  the alert banner.
- **Saves**: `PlayerProfile.save()` writes `.tmp`, reads it back, renames the
  current file to `.bak`, then `.tmp` into place. `load_or_new()`: damaged →
  `.unreadable` + load `.bak`; missing with a whole `.tmp` → finish that
  save; older schema → copy to `.v<n>` first. `load_notice` carries what
  happened to the HUD and the shipyard. Schema 5 adds `tutorial` and
  `campaign` (a pilot with history is not offered the tutorial).

## Encounters, policies and point defence (Milestone 10)

- **`Encounter`** (`scripts/simulation/encounter.gd`) is the contact
  registry: `Contact`s by stable id (slots `target_01…`; the lead keeps
  `Main.TARGET_ID`, a slot is reused once its ship is retired) and the
  selected one (`cycle`, `select`, `ensure_selection`, `live`). A
  **`Contact`** holds what the fight keeps per enemy ship: our track of it
  and its of us, hostility, air wing, `ShipPolicy`, salvo in flight,
  arriving / beaten / prize state, re-board timer.
- **`Main`** drives every live contact each frame (`_drive_contact`):
  captured → hold, break free from our gangway, board a beaten player (one
  contact at a time), arrive to its role's standoff, else fight its role.
  Selection-based actions (salvage, gangway, grapple, boarding, missiles,
  lead) use `encounter.selected`; the single-target names the HUD and tests
  use (`target_hostile`, `track`, `_target_arriving`, `target_wing`) are
  properties of the selected contact. The next encounter
  (`EnemyFactory.encounter_size`) arrives when no contact is left alive.
- **`ShipPolicy`** (Resource, `data/policies/*.tres`): discipline, PD (order,
  range, reserve), auto-salvo, auto-fire, role and focus fire. The player's
  is `ShipInstance.policy` (schema 6); `trigger(manual, …)` = manual OR
  auto-fire, so automation never blocks the player. `_apply_automation`
  feeds the aim error against the lead (`aim_error_deg`) and starts
  auto-salvos. Enemies: `EnemyFactory.policy(mission, index)` — the
  Standard preset with a role by place; `GunneryAI.combat(…, policy)` uses
  its keep range, flank bias and discipline; `GunneryAI.choose_prey` skips
  derelicts and focuses fire.
- **Point defence** (`WorldSimulation.pd_candidates`, `_update_point_defence`):
  hostile missiles, craft and threatening rounds sorted by the policy's
  rank then distance; each mount takes the first allowed (range, reserve)
  in its arc. Flak (`ProjectileState.pd_target_round`) kills the round it
  was fired at when it passes within 1.5 m during a tick
  (`_intercept_rounds`). `ShipState.side` keeps PD off its own side.
- **Numbers** (`tools/bench_sim.gd`, `tools/bench_hull.gd`): a 3-hostile
  encounter with wings and salvos runs 3.7 ms mean per tick, 17.6 ms worst
  (1 tick in 3,600 over 8 ms — a warhead strike: penetration walk, blast and
  a flight-config recompute). A 300-module hull: grid 3 ms, stats 6 ms,
  validation 8 ms, systems 91 ms (crew roster 115 ms of O(berths × rooms)),
  recompute 0.2 ms, power 1 ms, hit test 0.16 ms per round, full-length
  penetration 7 ms.

## Salvos, wrecks and crew views (Milestone 9)

- **`MissileSalvo`**: one press of M = warhead groups (`groups_for(mode,
  order)`); `step(world)` fires every ready launcher of the current group
  via `launch_missile(…, warhead)` and moves on when the group has nothing
  left in working launchers (`ShipSystems.missiles_of`). Mode and order live
  in `PlayerProfile.missile_mode / missile_order` (additive keys, schema 5).
- **Launchers** cycle in `LAUNCHER_CYCLE_S` (0.4 s); `missile_salvo` > 1
  launches a fanned-out swarm per launch (the saturation pod).
- **Break-ups**: `_burst_in_space` adds a `shot_down` burst carried by the
  nearer of the missile's target and launcher; blasts under
  `ShipSystems.SMALL_BLAST_M` are bursts (fireballs), not explosions.
- **Wrecks**: `WorldSimulation.retire_ship(id, new_id)` re-keys a ship and
  its craft (same prefix), releases gangways/grapples/boardings, drops its
  wing from the world and marks them `derelict` (neutral input, no point
  defence). Main keeps up to `MAX_WRECKS`, nudges each clear at 4 m/s, and
  keeps their craft views via `_derelict_wings`.
- **Crew views**: `CrewRoster.ROLE_COLORS`; `ShipSchematic` draws a dot per
  person by post (`hostile_crew` → red, `boarders` overlay, `highlight_member`);
  the CREW tab is a schematic + `Tree` roster; `BoardingAction.candidates()`
  says who a party would take.

## Missiles and EMP (Milestone 7)

- **Launchers** (`EquipmentDefinition.Kind.MISSILE_LAUNCHER`, appended so
  older `.tres` kind numbers hold) carry `missile_capacity` of a
  `MissileConfig` (`data/missiles/`). `ShipSystems.missiles_used` (in the
  vessel condition) and `launcher_cooldown` (4 s) track stock and reload.
- **Missiles are `ShipState`s** in the world's ship table
  (`WorldSimulation.missiles`, `ShipState.missile*`), flown by
  `_guide_missiles()`: zero-effort-miss proportional navigation (gain 3)
  within the missile's acceleration, the nose swung at its turn rate,
  spare acceleration spent closing. `_step_missiles()` runs after the ship
  loop: arming, a fuse swept along the tick's relative path, shoot-downs
  (rounds and point defence treat them like craft, never their own side's),
  self-destruct. Missiles skip collisions.
- **Warheads** (`_detonate`): anti-ship = `Penetration.apply` along the
  line of flight plus `ShipSystems.blast_at`; EMP and nuclear = exposure
  (effect radius / distance)² on every ship in reach → `ShipSystems.emp()` /
  `nuclear()`. `take_bursts()` feeds the views.
- **EMP**: reset = 20 s × exposure × (1 − hardening) × (½ if internal), ≤ 90
  s, ignored under 2 s; only `EquipmentDefinition.ELECTRONIC` kinds;
  `EquipmentState.disrupted_s` makes `working()` false until it runs out.
- **Nuclear**: dose = exposure ÷ (1 + facing armour / 60 mm); wounds above
  0.4, deaths above 1.5 (rising chance, seeded); +120 K × dose (≤ 400 K);
  facing hull ablated above exposure 3; then an EMP at 1.5 × exposure.

## Autonomous craft (Milestone 6)

- **Craft** are `ShipState`s with their own `ShipConfig` (`data/craft/`):
  same `ShipDynamics`, same rounds and hit tests. Without a systems model
  they have `hull_hp`: a round's penetration is taken off it; at 0 the craft
  is `DESTROYED`.
- **Racks** (`EquipmentDefinition.Kind.CRAFT_MOUNT`, `craft` config) carry
  one craft each; the craft's mass is in the rack's.
- **`AirWing`** (one per ship with racks; `WorldSimulation.wings`, updated at
  the start of each tick): launch (working rack, carrier |ω| < 0.15 rad/s;
  spawned 8 m off the rack at +3 m/s), recovery (< 10 m, < 2 m/s), 40 s
  servicing, comms (30 km; jammed → fallback RETURN after 10 s), loss, and
  persistence (`ShipInstance.wing`).
- **Fire rate (play-test batch 6)**: `ShipControlInput.fire_rate` (0.1–1)
  stretches each gun's cooldown. `ShipPolicy.autofire_rate` with
  `trigger_rate(manual)`: 1 for the player's hand, the policy's rate for
  automation (Main `_apply_automation`; enemies through `GunneryAI.combat`,
  `EnemyFactory` leads 0.7, wingmen 0.45). `EnemyFactory.kit_mission`
  fits wingmen as for earlier missions; `Main._spawn_encounter` spawns them
  arriving. `ShipSystems.reachable_rooms` starts from a vented bridge when
  the crew are suited.
- **Targets and rearming (play-test batch 6)**: `AirWing.strike_target`
  is `target_id` while `combat_ready` (active, not a derelict, not
  disabled), else the nearest combat-ready of `candidate_ids` (Main: the
  encounter's contacts), else null (STRIKE then returns home).
  `CraftAI.disengage_reason` adds "out of ammunition" at every risk. A craft
  that returns on its own sets `came_back_itself`; docked, serviced and with
  a strike target it relaunches (`auto_relaunch`, the WING tab's toggle);
  `recall` / `recall_all` clear it. Overview commands `wing_launch`,
  `wing_recall`, `wing_directive`, `wing_risk`, `wing_auto`.
- **`CraftAI`**: directive → `ShipControlInput`. Position control: desired
  velocity = target velocity + 0.12 × error (≤ 80 m/s), reached in ~1.5 s
  with the per-axis thrust available; attitude by proportional rate
  request; gunnery by lead point with a 2 × enemy-gunner fire cone.
  Disengage thresholds by risk ([hull, propellant, ammunition]):
  conservative 0.6/0.4/0.3, balanced 0.35/0.25/0.1, aggressive 0.15/0.1/0.
- **Inspection**: the target's systems show only within 3 km of the player
  or of a recon craft.
- **Roles and pathing (play-test batch 5)**: `ShipConfig.craft_role`
  (fighter / interceptor / bomber / recon / ew) picks the behaviour inside
  `CraftAI.command`; `AirWing` passes the craft's friends (same side, or
  its own carrier and wing when unaligned) and the enemy missiles.
  Avoidance is a velocity term added to the steering goal (separation
  70 m from craft, 120 m from hulls, gain 0.5, ≤ 60 m/s). Fire needs
  `clear_shot` (no friend within 25 m of the line to the target's range);
  craft rounds carry `ProjectileState.iff_side` and skip every ship of that
  side, hulls included (missiles are not skipped). Gun runs keep their
  phase in `ShipState.ai_state`. `CraftAI.ROLE_HELP`, `DIRECTIVE_HELP` and
  `RISK_HELP` are the in-game text.

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
- **Boarding** (`BoardingAction`): up to 24 security/general crew (the
  party size chosen in Tab › CREW; enemy parties at most 8;
  `BoardingAction.candidates()` says who would go) muster at our
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
900 s — the RCS shares the mains' propellant feed, so manoeuvring costs no
more per m/s than the main engines). Mass flow = F / (Isp · g₀); RCS rotation uses the thrust the torque
needs at the RCS's effective lever arm. Mass and inertia fall as propellant
burns; nothing fires with empty tanks. Δv left = Isp_main · g₀ · ln(m / m_dry).

## Simplifications in force (and their gameplay consequence)

| Simplification | Consequence | Revisit |
|---|---|---|
| Spherical central body for gravity; no J2, no third bodies (no Earth pull in lunar orbit) | Orbits never precess | If missions need ground tracks or long-duration accuracy |
| Airless bodies: the floor is a sphere at the highest terrain (11 km on the Moon), no terrain model | Flying low over a lunar plain is as fatal as hitting a summit | If low passes or landings are wanted |
| Jump distances are the real separations on the fixed scenario date; travel is instant | Each jump always costs the same | If the calendar advances between sorties |
| Artifacts sit at their real state at the fixed scenario epoch; an artifact never manoeuvres or reboosts; JWST and other Lagrange-point objects are left out (no rotating frame) | Each object is always found in the same place | If the calendar advances |
| About the Sun, the Sun's direction is fixed for the sortie (from the start point) and nothing near is drawn (the planets are points of light) | Off by 2e-6 rad an hour at Voyager 1, 0.02° at the Roadster | Not needed |
| A deep-space survey pays its round trip at launch, from the home location's body | No stranding far out; the trip home is free once paid | If deep-space stations arrive |
| Real objects take no damage and can't be grappled (heritage) | Surveys are about flying, not salvage | Not planned |
| A derelict is rebuilt from its design and worn to a single "intact" figure (not its exact damage); it decays per sortie, not with time | Wrecks look plausibly wrecked, not as they were left | If wrecks should keep their exact damage |
| Mars has no moons in its sky and no far body; sunlight is not dimmed with distance from the Sun (43 % at Mars) | Mars looks as bright as Earth; Phobos is never seen | If outer locations arrive |
| Planet positions from Keplerian elements (arcminutes), precession ignored between the Almanac Sun (of date) and the J2000 stars and elements (0.37° by 2026) | Mars's Sun is placed to ~0.1°; Earth's Sun to ~0.4° against the stars | If an eclipse or occultation must be exact |
| The jump reserve has no mass and no part of its own (a quarter of the tankage, beside it) | Bigger tanks mean a bigger reserve; the reserve never slows the ship | If tank design should trade reserve for range |
| Reflected light is shown through a night-adaptation mapping (full Moon = 5 % of the Sun), not at its physical 2.4e-6; it isn't occluded by the near body's terrain or shadowed on hulls | Night is visible and readable | If an exposure/eye-adaptation model is wanted |
| One far body per sky (the Moon from Earth, Earth from the Moon), placed by a low-precision lunar series (~0.3°); eclipses of the Sun by it are all-or-nothing; the Sun's direction is Earth's (≤ 0.15° off at the Moon) | Close enough to look right; no eclipse gameplay | If eclipses or more bodies matter |
| Lunar rotation uses the IAU pole and W with only the largest periodic term (others ~0.3°) | Lunar geography is ~0.3° off | Not needed |
| No atmosphere/drag: crossing 100 km = entry, vessel removed (design decision) | Skimming 100–120 km has no cost; dipping to 99 km is fatal | If aerobraking or reentry gameplay is wanted |
| Rounds inherit the ship's CoM velocity; muzzle velocity from rotation (ω × r) ignored | Firing while turning hard is slightly more accurate than reality | When weapon mounts gain turrets |
| Fire control assumes straight-line relative motion, no target acceleration | A manoeuvring target defeats the lead | Missiles / AI (M6–M7) |
| Diagonal inertia (principal axes = body axes) | Designs with skewed mass don't tumble off-axis | If asymmetric hull modules arrive |
| RCS blocks thrust equally in all six directions; torque = thrust × perpendicular lever arm | Block orientation doesn't matter | When RCS needs real quads |
| Centre of mass fixed at the full-tanks position | Burning propellant doesn't shift the CoM | If tank placement should matter in flight |
| Ammunition mass not counted in the ship's mass (magazines are sized by mass) | A full magazine weighs nothing in flight | Logistics |
| Penetration is a millimetre budget, not ballistics: no spall cone, ricochet or fragmentation; armour per module, not per face | Damage is predictable and explainable, never surprising | M7 (fragmentation, nukes) |
| Overpenetrating rounds fly on slower but in a straight continuation; no deflection | Exit direction is always the entry direction | M7 (fragmentation) |
| Docking is abstract: B docks from anywhere; no station or transfer orbit | Returning costs nothing | When stations / logistics arrive |
| Propellant and ammunition are refilled free at every launch | Only damage and parts carry over | Logistics |
| Crew move abstractly (5 s per room); skill is one number (repairs, treatment); no morale | Who is where matters most | Later |
| One fire per room, no spread between rooms | Fires stay where they start | If fire should spread |
| The grapple adjusts the target's velocity and attitude directly (shared momentum, no arm dynamics) | It always wins against a hulk | If grappling live ships matters |
| The grappled gangway forces equal velocities and turn rates (no compound-body dynamics) | Turning hard while docked can tear the gangway | If docked manoeuvring matters |
| Boarding fights are Lanchester attrition per room; fixed defender policy | Predictable, explainable outcomes | M6 (directives) |
| All gun mounts on a ship must be one type (one fire-control solution) | No mixed batteries | Turrets / per-mount fire control |
| Every enemy is the common-parts Kestrel; loot comes from crates, not the wreck's own parts | Salvage never returns a specific fitted part | When enemy loadouts vary |
| Wrecked modules stay attached; no debris | Ships never break apart | Later (structural detachment) |
| One power junction per module; no batteries, breakers or cabling; fixed shedding order | Redundancy comes from reactors and module layout only | M4/M5 (repairs, rerouting) |
| One thermal mass per ship; radiators can't retract | An idle ship settles at ~258 K; heat can't be stored locally | When heat sinks / radiator control arrive |
| Missiles are small `ShipState`s with a hit box and hull points; guidance turns the nose directly at its turn rate (no airframe or torque model) | They fly and die like craft; their path is predictable | If missile manoeuvre detail matters |
| Flares are points with a scalar signature (no IR spectrum, no chaff/radar distinction); a seeker weighs each flare once, by a seeded roll | Countermeasures are predictable and testable; timing matters, spectrum doesn't | If seeker types multiply |
| Jamming is one noise number per side (own jammers + EW drones within 3 km), linear from burn-through (3 km) to full (6 km); no frequency agility or home-on-jam | Jamming is a range game | If EW grows into a minigame |
| Nuclear effects simplified: one dose number, armour as a divisor, ship-wide heat, no blast wave, no fallout or lasting radiation | A burst is a sharp, explainable event | If a strategic weapon needs more depth |
| EMP exposure falls with the square of the distance; no line-of-sight shielding by other ships | A ship cannot hide behind another | Later |
| Missions are a fixed chain of four goals, then patrols | Little variety after the chain | Campaign content (M13) |
| An encounter turns hostile together, and a contact engages only after the player has detected it | Ships can't be picked off one by one while the rest stay passive | If stealth or diplomacy arrive |
| Enemy roles are fixed by place in the encounter (closer, standoff, flanker); no coordinated manoeuvres | Encounters feel the same shape each time | Later AI work |
| Point-defence flak: a round within 2.6 m of a heavy slug (≥ 2 kg, < 1.5 km/s closing) destroys it; small and fast rounds can't be tracked | Heavy-cannon fire can be thinned by PD; autocannon and railgun fire can't | If PD lasers or interceptors arrive |
| A round far from every ship coasts in a straight line between checks (up to 1 s), its tidal pull applied on waking | Paths agree with step-by-step integration to well under a metre over a sleep | Not needed |
| Craft controls are updated at 30 Hz (avoidance at 15 Hz), held in between | Craft react a tick later | If dogfights need finer control |
| At most 3 ticks per frame | Below 20 fps the fight runs slower than real time | If a faster simulation arrives |
| Auto-fire judges the aim against the primary gun's lead only | Mixed batteries auto-fire on the primary gun's solution | Per-mount fire control |
| A beam is a single instant ray to the first hull (no dwell, no spot size, no blooming); its falloff is linear with range; a steering mirror lays it within 2° on small targets | Lasers are a clean trade: certain hits for power and heat | If lasers need dwell time or thermal blooming |
| Craft IFF is perfect: a craft's round never hits a ship of its own side, hulls included (the clear-shot check still holds fire so rounds aren't wasted on friends) | Craft can't hurt you or each other | If IFF failure is wanted as a mechanic |
| Craft avoidance is a local velocity nudge (no path planning around hulls) | Craft can get pinned against a large hull for a moment | If carriers get very large |
| The escort's courier is a craft-like hull (hull points, no systems) on a fixed drift | It can't evade or be repaired | If escorts become a mainstay |

## Testing

- `tests/run_tests.gd` — headless runner; methods named `test_*` in
  `tests/unit/test_*.gd` (subclasses of `TestCase`). Failure messages state
  measured quantity, expected and actual.
- `tests/smoke/smoke_main.gd` — boots the real main scene and drives it via
  InputMap actions, including the hostile target hitting the player.
- `tests/smoke/smoke_shipyard.gd` — shipyard end to end: real mouse click on
  the deck editor, undo/redo by key, validation, save/reload, the map (click
  the Moon, pick two ships), launch into lunar orbit, B back to the Lunar
  Shipyard.
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
- `tests/smoke/smoke_wing.gd` — the Milestone 6 exit test: launch, command
  and recover a fighter, then lose one persistently.
- `tools/bench_sim.gd` — simulation frame-time profile under load; the same
  run backs `test_the_simulation_keeps_a_60_hz_budget_under_load`.
- `tools/capture_screens.gd` — renders scripted moments to PNG for visual
  review (on the real profile: back it up, or use a scratch profile path).
- Mutation checks: each core rule (tidal gravity, recoil, connector matching,
  parallel axis, exterior faces, armour obliquity, junction isolation, hatch
  destruction, AI feed-forward, self-hit arming, loot pity, loot RNG
  persistence, rare-replacement availability) was deliberately broken once;
  each time the matching test failed.
