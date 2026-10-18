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

## Milestone 2 — Ship blueprint and builder ✅ (2026-10-19)

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

### 2b — shipyard UI ✅ (2026-10-19)

| Acceptance criterion | Verified by | Result |
|---|---|---|
| Deck grid editor with palette and tools — place, select/move, rotate, remove — for modules, rooms, equipment, hatches | `test_ship_editor.gd` (5 tests); `smoke_shipyard` places a radiator with a real mouse click | pass |
| Side and front orthographic views, 3D preview of the flight model | visual review (Forward+) | pass |
| Live stats and validation panel; clicking an issue highlights the part | `smoke_shipyard`; visual review | pass |
| Save / load player designs; load a prebuilt template | `smoke_shipyard` (save → reload identical) | pass |
| Launch a test flight (blocked while errors exist); B returns to the shipyard | `smoke_shipyard` | pass; flight uses the design's mass and name |
| Placement preview: ghost turns red and names the error before you click | `test_preview_reports_new_errors_without_editing`; visual review | pass |

Exit criteria met: the player can modify a ship, validate it, save it and
launch it — verified end to end by `smoke_shipyard` (15 checks).
Human usability testing of the editor has not happened yet (KNOWN_ISSUES.md).

## Milestone 3 — Physical damage and ship systems ✅ (2026-10-19)

Spec exit criteria: two different layouts react differently to identical
attacks for explainable reasons.

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Armour stops a round whose penetration is insufficient; obliquity thickens armour | `test_armour_stops_insufficient_penetration`, `test_oblique_hit_meets_thicker_armour` | 20 mm vs 30 mm stopped; 50 mm passes head-on, stopped at 60° |
| 2 | A penetrating round damages components along its path | `test_penetrating_round_damages_systems_along_its_path` | corridor + reactor room breached, hatch h25 destroyed, reactor takes its 35 mm shielding |
| 3 | Hits use the real hull, not a bounding box | `test_hits_use_hull_cells_not_the_bounding_box` | round over the nose flies on; fuselage face hit at the right point |
| 4 | Destroying a power junction affects connected loads but not independent networks | `test_wrecked_module_cuts_its_network_but_not_an_independent_one` | 1 reactor: engines dead; 2 reactors: engines and tail RCS stay up |
| 5 | A breach changes pressure/access by adjacent boundaries | `test_breach_seals_hatches_and_cuts_crew_access` | corridor vents, neighbours sealed but cut off; destroyed hatch vents the bridge |
| 6 | Heat accumulation throttles / shuts down a system | `test_heat_throttles_then_scrams_the_reactor` | no radiators at full thrust: throttle ~3 min, scram ~11 min; intact radiators stay normal |
| 7 | Damage changes flight | `test_damage_reduces_thrust_torque_and_guns`, `test_destroyed_tank_spills_its_share_of_propellant` | half thrust + yaw torque from one-sided engine loss; dead cannon silent; ¼ propellant lost with a tank |
| — | **Exit:** two layouts, identical attack, different explainable outcomes | `test_two_layouts_react_differently_to_the_same_attack` | template keeps power (rounds spent in nose/corridor bulkheads); nose-reactor layout loses reactor and all thrust, report says why |
| — | Enemy gunner tracks and hits a crossing target | `test_gunnery_ai_turns_onto_target_and_hits`, smoke | ≥ 20 hits in 30 s at > 60 % accuracy; hits the player in-game |

Mutation-checked: removing armour obliquity, letting wrecked junctions conduct,
never destroying hatches, or removing the AI's line-of-sight feed-forward each
fails exactly the matching test.

### Between M3 and M4 — persistent rounds, impact physics, hit cam (2026-10-19)

| Acceptance criterion | Verified by | Result |
|---|---|---|
| Two-body propagation is exact (circular, elliptic, hyperbolic) | `test_rounds.gd` (propagation vs geometry and vs leapfrog) | pass |
| Rounds never expire; far rounds coast analytically and come back | `test_rounds_never_expire`, `test_round_coasts_far_and_reenters_on_time` | pass |
| A miss returns half an orbit later and can hit its own ship | `test_round_returns_on_its_orbit_and_hits_half_an_orbit_later` | pass; fails if self-hit arming is removed |
| Recoil pushes and spins the firing ship; impacts push and spin the target; overpenetration continues slower | `test_rounds.gd` | pass |
| Incoming-round warning | `test_rounds.gd`, HUD | pass |
| Hit cam replays our hits and the modules damaged | `test_hit_cam_replay_policy`, `smoke_main`, render review | pass |

## Milestone 4 — Persistence and recovery ✅ (2026-10-19)

Spec exit criteria: complete a combat mission, return damaged,
repair/reconfigure and relaunch. Plus the requested gacha loot: equipment and
hull/room blueprints with cascading weighted rarity.

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Ship instance separate from blueprint; damage persists (all kinds) | `test_damage_round_trips_through_the_condition` | hit points, armour, structure, breaches, hatches, thrust, power identical after round trip |
| 2 | Blueprint and damaged vessel survive save/load; unsupported/corrupt saves handled safely | `test_profile_and_damaged_vessel_survive_save_and_load`, `test_unsupported_or_corrupt_profiles_are_rejected_safely` | identical JSON; newer schema / no version / bad JSON refused; unreadable file kept aside |
| 3 | Loot: cascading rarity at the stated odds; weighted pick; cascade down past empty tiers | `test_tier_probabilities_follow_the_cascade`, `test_cascade_roll_matches_the_stated_odds` (200,000 rolls, 4σ), `test_weighted_pick_within_a_tier`, `test_empty_tier_cascades_down` | 70 / 21 / 6.75 / 1.8 / 0.45 % |
| 4 | Hard pity; no re-rolls by reloading | `test_hard_pity_caps_the_dry_streaks` (8,000 pulls), `test_pulls_are_deterministic_and_survive_save_and_load` | streaks ≤ 9 / ≤ 79; same sequence across save/load |
| 5 | Found parts gate the design; duplicates scrap for parts | `test_locked_blueprints_and_unowned_parts_are_errors`, `test_duplicate_blueprints_scrap_for_spare_parts`, `test_mixed_gun_types_are_an_error`, `test_rare_parts_change_the_numbers` | pass |
| 6 | Salvage needs a disabled wreck, proximity and matched velocity; yield follows wreck condition | `test_disabled_means_it_cannot_fight`, `test_salvage_needs_a_disabled_wreck_close_and_slow`, `test_salvage_pays_more_for_a_cleaner_kill` | pass |
| 7 | Spare parts and repair costs; priorities; destroyed parts need replacement; no repair exploit by swapping parts | `test_repair_costs_scale_with_damage_and_never_beat_a_rebuild`, `test_priorities_choose_what_gets_fixed_with_few_parts`, `test_repairs_restore_the_vessel_and_charge_parts`, `test_refit_is_paid_up_front_and_keeps_wear_on_kept_parts` | pass |
| 8 | Rarer losses: written off once on docking, on vessel loss; blueprint survives | `test_destroyed_rare_unit_is_written_off_and_needs_a_replacement`, `test_losing_the_vessel_writes_off_rare_units_but_keeps_the_design` | pass |
| 9 | Workshop field repair: needs a powered, pressurised, reachable workshop; takes time; interrupted by lost access | `test_field_repair_needs_a_working_workshop_and_patches_over_time`, `test_field_repair_is_interrupted_when_the_workshop_vents` | 25 s for 15 hp; reactor to 75 % |
| — | **Exit:** fight → disable → salvage → return damaged → repair/refit → relaunch | `smoke_campaign.gd` (20 checks, real scenes and input actions) | pass; profile on disk matches |

Mutation-checked: removing pity, not restoring the loot RNG state on load, or
allowing a rare replacement without a spare unit each fails exactly the
matching test. Loot panel, HUD salvage lines and the hangar panel reviewed in
renders. Scaffolding in the exit test: after a real exchange of fire, the
target's gun is destroyed directly and it is placed alongside.

## Milestones 5–8

Not started. See GAME_DESIGN.md §17.
