# Roadmap

Full milestone definitions: [`GAME_DESIGN.md` §17](GAME_DESIGN.md#17-milestone-roadmap).
A milestone is not done until its acceptance results are verified by tests that
were actually run.

## Milestone 0 — Repository and project health ✅ (2026-10-19)

- [x] Repository inspected (empty — only the spec existed)
- [x] Godot project, folder layout, `.gitignore`, git repo (now Godot 4.7.2)
- [x] Docs: README, GAME_DESIGN (spec), ARCHITECTURE, ROADMAP, CHANGELOG, KNOWN_ISSUES
- [x] Bootable main scene
- [x] Headless test harness + smoke test + log-error gate (`tools/run_checks.sh`)
- [x] Logging (`GameLog`, file logging enabled)

Exit criteria met: project imports and boots headlessly with zero engine
errors; 20 unit tests + 7 smoke checks pass.

## Milestone 1 — Flight sandbox ✅ (2026-10-19)

### 1a — 6DoF flight
- [x] Simulation state separated from rendering (`scripts/simulation/`)
- [x] Fixed-timestep world clock with render interpolation
- [x] 6DoF translation and rotation with per-direction thrust limits
- [x] Flight assist (translation + rotation) and manual mode
- [x] Controllable placeholder frigate, passive target ship
- [x] HUD: speed and body-axis velocity, angular rates, Δv spent, target
      range / range rate / relative speed; heading reticle; prograde/retrograde;
      target bracket and off-screen arrow
- [x] Floating render origin, dust field motion cue

### 1b — Earth orbit, cannon, fire control, radar

Decisions: real-scale Earth; 100 km Kármán line as the entry interface
(GAME_DESIGN §5 → Decisions).

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | No-thrust circular orbit: \|r\| within ±0.1 %, energy drift < 10⁻⁴ over 10 orbits | `test_circular_orbit_bounded_over_ten_orbits` (dt 1 s, with 486 frame rebases), `test_one_orbit_at_game_timestep` (60 Hz) | measured 6.8×10⁻⁷ radius, 1.7×10⁻⁷ energy; 6.4×10⁻⁸ energy at 60 Hz |
| 1 | Prograde burn raises the opposite apsis; retrograde lowers it | `test_prograde_burn_raises_opposite_apsis`, `test_retrograde_burn_lowers_opposite_apsis` | pass; radius half an orbit later = predicted apoapsis to 10⁻⁴ |
| 1 | Below circular speed → ellipse, not impact, unless periapsis < entry interface | `test_below_circular_speed_is_an_ellipse_not_an_entry` | pass; lowest altitude = predicted periapsis ± 0.5 km |
| 1 | Trajectory crossing 100 km is detected as atmospheric entry | `test_trajectory_crossing_the_entry_interface_is_detected_and_timed` | predicted 1761.44 s, simulated 1761.50 s |
| 2 | Assist does not burn continuously against gravity | `test_assist_orbit_hold_spends_no_delta_v`, `test_assist_target_hold_matches_velocity_without_fighting_gravity`, smoke | 0 m/s over 10 min holding orbit; < 10 m/s matching a target (vs ~5,200 m/s hovering) |
| 3 | Round velocity = ship velocity + muzzle velocity × nose (exact) | `test_round_inherits_ship_velocity_plus_muzzle_velocity` | pass |
| 3 | Finite flight time = range / speed in a straight-line case | `test_flight_time_matches_straight_line_range` | 0.96 s ± 1 tick |
| 3 | Gravity acts on rounds | `test_gravity_acts_on_rounds` | matches independent two-body integration to < 1 m over 20 s; ~1.7 km off a straight line |
| 3 | Swept hits: no tunnelling at the fixed timestep | `test_fast_round_does_not_tunnel_through_target`, `test_segment_box_cases` | 6 km/s round, 100 m per tick, 20 m box: hit |
| 3 | Rate of fire, magazine, recoil (momentum) | `test_rate_of_fire_and_magazine_limit`, `test_recoil_conserves_momentum` | pass |
| 4 | Lead indicator / TOF within 1 m / 0.01 s on known geometry | `test_intercept_time_known_geometry`, `test_lead_solution_produces_a_hit_in_orbit` | pass; lead-aimed round hits a 40 m/s crossing target in orbit |
| 5 | Flat radar: bearing, range, elevation, approach/recede | `test_radar.gd`; visual review | pass |
| 6 | Orbital HUD: Ap/Pe, projected path | `test_orbit_elements_known_values`; smoke; visual review | pass |

Exit criteria (from spec): ship movement is understandable; trajectories and
projectile timing pass tests. Automated part met: 46 unit tests + 14 smoke
checks pass, zero engine errors. Frames reviewed under Forward+ on a real GPU.
"Understandable" still needs a human play-test (KNOWN_ISSUES.md).

## Milestone 2 — Ship blueprint and builder 🟡 in progress

Spec exit criteria: the player can modify a ship, validate it, save it and
launch it.

### 2a — blueprint model, validation, derived stats ✅ (2026-10-19)

| Acceptance criterion | Verified by | Result |
|---|---|---|
| Valid blueprint saves and loads without data loss (versioned JSON) | `test_blueprint_round_trip_has_no_data_loss` | identical JSON in memory and via file |
| Unsupported / malformed files rejected safely | `test_unsupported_or_malformed_files_are_rejected_safely` | newer schema, bad JSON, missing version, bad field |
| Invalid module attachment detected (overlap, floating, mismatched connectors) | `test_overlapping_modules_detected`, `test_detached_module_detected`, `test_incompatible_connectors_do_not_attach` | pass |
| Room / access connections valid (inside pressurised hull, no overlap, hatches join neighbouring rooms, every room reachable from the bridge) | `test_rooms_must_be_inside_pressurised_hull`, `test_overlapping_rooms_detected`, `test_hatches_must_join_neighbouring_rooms`, `test_room_without_access_route_is_reported`, `test_missing_bridge_is_an_error` | pass |
| Equipment fits its mounting volume (room role, exterior face, allowed face) | `test_internal_equipment_needs_a_suitable_room`, `test_external_equipment_needs_an_exterior_face` | pass |
| Mass and centre of mass calculated consistently | `test_mass_and_center_of_mass_hand_computed`, `test_inertia_uses_parallel_axis` | exact to 10⁻⁴ m / 1 kg·m² |
| Propulsion/torque from placed thrusters; off-axis thrust reported | `test_thrust_and_torque_come_from_placed_thrusters`, `test_off_axis_thrust_reported` | pass |
| Missing power reported; obstructed weapon arcs reported; unfed cannon reported | `test_power_deficit_and_missing_magazine_reported`, `test_obstructed_weapon_arc_reported` | pass |
| Prebuilt frigate template validates clean and flies with its own numbers | `test_frigate_template_validates_clean_and_compiles`, `test_compiled_design_flies_with_its_own_numbers`, smoke | 392 t, 0 errors, 0 warnings; F/m exact in flight |

Mutation-checked: breaking connector matching, the parallel-axis term or the
exterior-face test each fails exactly the matching test.

### 2b — shipyard UI (next)

1. Shipyard scene: deck grid editor (top view per deck) with palette and
   tools — place, select/move (arrow keys), rotate, remove — for hull
   modules, rooms, equipment and hatches.
2. Side and front orthographic views and a 3D preview of the same model the
   flight view uses.
3. Mass / thrust / power / heat / storage summary and a validation panel,
   updated on every edit; selecting an issue highlights its part.
4. Save / load player designs (user://blueprints), load a prebuilt template.
5. Launch a test flight with the current design (blocked while errors
   exist); return to the shipyard from flight.
6. Smoke test: load template → edit through the editor → validation reacts →
   save → reload identical → launch → flight uses the design's numbers.

## Milestones 3–8

Not started. See GAME_DESIGN.md §17.
