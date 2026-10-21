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

### Known issue fixed (2026-10-19)

Earth's texture: 2048 × 1024 → 5400 × 2700, NASA Blue Marble NG, October
composite (the scenario's season). Render review.

## Milestone 5 — Crew and boarding ✅ (2026-10-19)

Spec exit criteria: boarding is physical, counterable and influenced by
layout. Spec tests (§16 "Crew/boarding") mapped below.

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Abstract crew roles fill the berths at stations | `test_default_crew_fills_the_berths_by_role` | 2 cmd, 2 eng, 2 DC, 1 weapons, 4 security, 1 medical, 4 general |
| 2 | Crew cannot pass a sealed or vented connection (suits can) | `test_crew_cannot_pass_sealed_or_vented_connections` | pass |
| 3 | Venting hurts the people in the room; losing command / gun crew degrades the ship | `test_venting_a_room_hurts_its_occupants_and_command`, `test_without_gun_crew_the_guns_fire_at_half_rate` | turn rates × 0.5; rate of fire × 0.5 |
| 4 | A repair cannot begin without crew who can get there; repairers walk first | `test_field_repair_needs_crew_who_can_get_there`, `test_field_repair_needs_a_working_workshop_and_patches_over_time` | 15 s walk + 25 s work |
| 5 | Casualties persist; wounded recover; dead are replaced at the yard | `test_casualties_persist_and_the_wounded_recover`, `test_repairs_restore_the_vessel_and_charge_parts` | pass |
| 6 | Docking fails outside position / velocity / turn-rate / orientation tolerances | `test_docking_fails_outside_the_tolerances`, `smoke_boarding` | each refused, with the reason on the HUD |
| 7 | Boarding begins only over a physical, sealed connection | `test_boarding_begins_only_over_a_sealed_gangway`, `smoke_boarding` | collar seals in 10 s |
| 8 | A target that can still manoeuvre breaks contact | `test_a_target_that_can_still_manoeuvre_tears_free`, `smoke_boarding` | gangway torn; not once power is out |
| 9 | Disconnecting the gangway strands the team | `test_a_severed_gangway_strands_the_team` | STRANDED |
| 10 | No automatic kills; outcomes depend on defenders | `test_outcome_depends_on_who_is_defending_not_on_instant_kills` | full crew repels 8 boarders at the bridge (~90 s); without security: captured in ~77 s |
| — | **Exit:** layout changes boarding | `test_layout_decides_how_long_it_takes` | collar into the bridge vs two locked hatches away: > 40 s faster |
| — | **Exit (end to end):** dock, be torn free, disable, seal, board, capture, salvage | `smoke_boarding.gd` (10 checks, real scene and input actions) | pass |

Mutation-checked: letting boarders walk through locked doors, never tearing
the gangway, or letting unsuited crew through vacuum each fails exactly the
matching test. Docking and boarding HUD lines and the gangway tube reviewed in
renders. Scaffolding in the end-to-end test: the target is placed alongside
and its security team and reactor are removed directly.

## Between M5 and M6 — ship control, station economy, UI (2026-10-19)

| Request | Verified by | Result |
|---|---|---|
| Default gun nerfed (rate of fire, muzzle velocity) | `test_weapons.gd` (derived from the weapon) | 1000 m/s, 120 rpm (was 1500, 240) |
| Ship AI flies with limited mobility when the bridge crew is lost | `test_ship_ai_flies_with_assist_when_the_bridge_is_lost`, `test_venting_a_room_hurts_its_occupants_and_command` | assist forced on; thrust and turn rates × 0.5 |
| Reactor explodes at 0 % | `test_reactor_at_zero_explodes_and_wrecks_its_surroundings`, `test_a_round_that_kills_the_reactor_reports_the_explosion` | blast falls off over 15 m; in the hit report |
| Power management (divert to engines, weapons, systems) | `test_ship_control.gd` (3 tests) | zero-sum pips; 150 % thrust / rate of fire / repair speed at 4 pips |
| Crew management | `test_a_general_crew_member_can_take_over_the_bridge`, `test_cover_needs_…`, `test_player_chooses_…`, `test_boarding_party_size_…` | pass |
| Bank at the station; death loses only the cargo; respawn fee, same design | `test_salvage_goes_into_the_hold_until_banked`, `test_losing_the_vessel_loses_only_the_cargo_and_a_fee`, `test_cargo_and_credits_survive_…`, `test_station_sells_spare_parts_for_credits`, `smoke_campaign` | pass; v1 profiles migrate |
| Post-combat debrief from a saved combat log | `test_debrief_says_where_the_hits_came_from`, `smoke_campaign` | saved to `user://debriefs/`; shown at the station and on loss |
| Always-visible module / damage map; tactical overview; crew and power UI; boarding room overlay in the hit cam; docking cam; cyberpunk cyan/magenta UI | render review (`build/screens/ui_*.png`) | pass |
| Military hull plating, ship name on the hull, prominent hatches (collars), white RCS jets | render review (`build/screens/model_*.png`) | pass |
| Known issues: enemy variety, salvage of fitted parts | `test_enemies_get_tougher_and_stay_valid`, `test_salvage_strips_the_best_intact_rare_part` | pass |

## Milestone 6 — Drones, fighters and directives ✅ (2026-10-19)

Spec exit criteria: the player can command an NPC fighter and recover or
lose it persistently. Spec tests (§16 "Autonomous units") mapped below.

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Autonomous craft share physics | craft are `ShipState`s in the same world; `test_rounds_wreck_a_craft_and_it_stays_lost` | a 60 mm round kills a 40 hp fighter |
| 2 | Launch needs clear space and valid relative motion | `test_launch_needs_a_working_rack_and_a_steady_carrier` | refused while spinning or with a dead rack; 8 m clear, +3 m/s |
| 3 | Fighter follows strike / intercept / recon / escort / return | `test_strike_closes_and_hits_the_target`, `test_intercept_goes_after_hostile_craft`, `test_recon_keeps_its_distance_and_gives_a_close_look`, `test_escort_stays_with_the_carrier`, `test_return_recovers_and_services_the_craft` | ≥ 5 hits from ~600 m; recon at 1.5 km, never fires; escort within 250 m |
| 4 | Target priorities | `test_strike_aims_at_the_chosen_subsystem` | aims at a working engine; at the hull once all are gone |
| 5 | Damaged or low-resource craft disengage under conservative rules | `test_risk_tolerance_decides_when_to_break_off`, strike test (out of ammunition) | conservative breaks off at half hull; aggressive fights on |
| 6 | Communications disruption → defined fallback | `test_lost_comms_fall_back_to_return` | RETURN after 10 s; resumes on contact |
| 7 | Drone reconnaissance / inspection | recon test; HUD sensor gating | systems visible only within 3 km or with a recon craft there |
| 8 | Lost or damaged craft persist; repaired / replaced at the station | `test_rounds_wreck_a_craft_and_it_stays_lost`, `smoke_wing` | replacement 10 spare parts |
| — | **Exit:** command a fighter, recover it, lose it persistently | `smoke_wing.gd` (15 checks, real scenes and input actions) | pass |

Scaffolding in the exit test: the fighter is "shot down" by setting its
status. Renders reviewed (craft in flight, overview air-wing controls).

## UI simplification and polish (2026-10-19)

| Request | Verified by | Result |
|---|---|---|
| Shared design tokens; sans headings / mono telemetry; semantic colours with shapes | `CyberTheme`; renders | applied to HUD, drawer, station, overlays |
| Combat HUD consolidated: own-ship card, target card, weapon strip; detail panels on demand | `smoke_main` (J/O panels, strings), renders at 1280×720 / 1600×900 / 2560×1080 | no overlaps after layout fixes |
| Measured vs estimated vs stale sensor data; lock status | `test_sensor_track_detects_estimates_and_goes_stale`; target card | MEAS / EST / STALE, confidence, lock |
| Actionable alerts linked to the affected system | `smoke_main` (critical reactor → alert names it; Tab opens on it) | pass |
| Damage control: less obstruction, selection details, contextual actions | `test_switching_a_load_off_reroutes_its_power`, `test_isolating_a_compartment_blocks_crew_routes`, `test_schematic_picks_the_system_under_the_cursor`, `smoke_main` (drawer button switches the gun off) | right-side drawer, tabs |
| Shipyard: searchable categories, stats hierarchy, expandable views, tabbed hangar, primary launch | `smoke_shipyard` (search, category, pick, expand/restore), renders | pass |
| Shift zoom for gunnery | manual (camera); input action test | eases FOV 70° → 22° |
| RCS Δv no worse than main engines | `test_rcs_costs_no_more_per_metre_per_second_than_the_mains` | Isp 900 s |
| Next enemy detected before it engages | `smoke_campaign` (arrives ~30 km out, holds fire undetected) | pass |
| Ricochet trajectories; black entry / exit holes | `test_steep_hits_ricochet_and_head_on_ones_shatter`, `test_hole_normals_point_out_of_the_hull` | pass |
| Yellow target-relative prograde/retrograde in match mode | HUD overlay | relative velocity and speed label |

## Operations pass (2026-10-20)

| Request | Verified by | Result |
|---|---|---|
| Hold B 5 s out of combat: "dimensional jump drive" to "Earth Shipyard"; amber alerts to recall craft / withdraw boarders first | `smoke_campaign`, `smoke_wing`, `smoke_shipyard` (hold B), render | waits at full charge for craft, boarders and cargo |
| G drops a salvage beacon: 50 % scrap credit, lower-odds crates | `test_takeover_pays_more_than_a_beacon`, `smoke_campaign` (credits exact) | 40 % loot per crate, banked |
| Boarding takeover: 80 % scrap, better crates into the hold; auto-withdraw | `test_boarding` (prize, RETURNED), `smoke_boarding` | 85 % loot per crate, +2 crates |
| Loot tables in the shipyard | `smoke_campaign` | HANGAR → LOOT TABLES |
| Cargo capacity, vent excess | `test_cargo_hold_capacity_and_venting_the_excess`, render | drawer CARGO tab |
| Amber alert to withdraw boarders with N | HUD alert | while a party is across |
| Primary weapons locked during boarding | `test_a_gangway_locks_the_primary_weapons` | both ships; craft still fight |
| Shift zoom toggles; right-drag orbits the camera; R/F up/down only; A/D yaw (strafe on the docking cam); docking cam in a corner | `test_input_bindings`, renders | zoom centres on the aim |
| Reactor failure explosion graphics | `test_a_reactor_explosion_plays_out_and_its_debris_flies_free`, renders | flash, fireball, rings, debris, glow, camera shake |
| Angled hull / armour plates; hull consolidated into four blocks | `test_hull_blocks.gd` (wedge geometry, √2 at 45°, ricochet off the long slope) | template rebuilt from blocks |
| Build new ship | `test_a_new_hull_is_commissioned_into_the_hangar`, render | hangar of vessels |
| Ship AI gunnery at 50 % rate, reduced accuracy | `test_ship_ai_lays_the_guns_at_half_rate_with_extra_spread` | +0.4° spread |
| Kinetic cannon nerfed | data | 50 rpm, 48 mm |
| Top-down / isometric shipyard views | `smoke_shipyard` (iso pick and drag edit), render | iso edits too |
| Underside RCS placement / removal bug | `test_middle_of_a_bottom_cell_picks_the_underside` | fixed |
| Richer part details; no connector text | `test_every_part_has_an_engineering_card` | engineering cards |
| "Not structurally attached" connector mismatch | `test_any_common_face_attaches` | any common face |
| Dev +100 credits | `smoke_campaign` | CARGO & BANK |
| Turrets aimed at the mouse, one reticle per gun, greyed when blocked | `test_turret_trains_at_its_traverse_rate_then_fires_on_the_aim`, `test_a_gun_holds_fire_when_its_own_hull_is_in_the_way`, renders | per-gun traverse |
| Radiators 2 cells long | `test_radiators_span_two_cells_and_fighters_launch_from_a_hangar` | ×2 rejection and mass |
| Player-drawn armour, 40 / 80 mm | `test_painted_plates_add_mass_cost_and_persist`, `test_worn_plates_are_remembered_and_replated_at_the_yard` | face filters |
| 3D models for external equipment; fighters from an internal hangar | renders | sensor mast, docked drone, hangar door, craft |
| Power distribution and player-routed bus | `test_power_bus.gd` | auto-route, cuts, yard re-run |
| Gacha carousel before the post-combat log, which lists the loot | `smoke_campaign`, renders | debrief LOOT GAINED |
| Scans show approximate cargo and bounty | `test_scans_need_a_held_lock_and_an_active_sensor_mast`, render | ±15 % |
| Enemy turns hostile when hit | `smoke_wing` (fighter hits) | |
| Ship-to-ship collisions and ramming damage | `test_ramming_pushes_apart_and_hurts_the_lighter_side_more` | |

## Play-test feedback pass (2026-10-20)

The user play-tested and sent 57 points; all addressed. Highlights and
where they are verified (`tests/unit/test_feedback_pass.gd` unless noted):

| Request | Verified by | Result |
|---|---|---|
| WASD pitch/yaw, QE roll, RF thrust, IJKL strafe; strafe hint on the docking cam | `test_input_bindings`, smoke | |
| Target markers without matching velocity; time to closest approach | `test_velocity_hold_cycles_three_modes`, `test_closest_approach` | X cycles 3 modes; CPA line |
| Bullets missing / sudden rapid fire | `test_rate_of_fire_does_not_compound_on_recompute` | fixed |
| Guns: tiers, equal DPS, railgun slower, no range fall-off, mass magazines, autocannon common | `test_each_gun_meets_its_armour`, `test_magazines_hold_mass_not_rounds`, `test_profiles_keep_the_parts_their_designs_use` | profile v4 keeps the user's cannons |
| Spinning wrecks can't be docked; grapple arm | `test_the_grapple_steadies_a_tumbling_hulk_and_siphons_it` | |
| Emergency jump; jump only blocked under fire | smoke (wing, campaign) | red countdown |
| Suits, hull sealing, bigger rooms, medbay, faster medic | `test_suited_crew_…`, `test_damage_control_seals_breaches`, `test_bigger_rooms_work_faster` | |
| Engines on any face; thrust × Isp balance | `test_engines_on_any_face_…`, `test_engines_trade_thrust_for_isp` | |
| Coolant loops; foam suppression | `test_coolant_loops_feed_radiators`, `test_foam_puts_out_fires_until_it_runs_out` | |
| Same-type rooms join | `test_same_type_rooms_side_by_side_need_no_hatch` | |
| Templates of several sizes | `test_templates_of_every_size_use_only_standard_parts` | Cutter, Corvette, Frigate |
| Named crew, hiring, reassignment; vendor; tech tree | `test_named_crew_…`, `test_crew_can_be_reassigned_mid_fight`, `test_the_quartermaster_and_the_upgrades`, `smoke_shipyard` | |
| Shipyard: zoom/pan, drag-move, CoM toggle, underside toggle, hatch fix, iso from front-left, thin grey armour | `smoke_shipyard`, renders | |
| Visuals: accordion radiators, triangular plates, truss lattice, char, radar, windows/lights, room colours, far tracers, centre alerts | manual | |

## Milestone 7 — EMP and advanced weapons ✅ (2026-10-20)

Spec exit criterion: weapons have distinct effects and viable counterplay.
Verified in `tests/unit/test_m7_weapons.gd` unless noted.

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Guided missile follows a manoeuvring target | `test_guidance_hits_a_manoeuvring_target` | hits a target strafing at full RCS from 3 km |
| 2 | Interception: point defence shoots missiles down | `test_point_defence_shoots_down_an_incoming_missile`, `test_own_point_defence_and_guns_ignore_our_missiles` | shot down before the hull; own PD holds fire |
| 3 | Anti-ship warhead: penetration and blast | `test_anti_ship_warhead_penetrates_and_blasts` | penetrates, blasts inside, credited to the shooter |
| 4 | EMP missile; electronics hardening and recovery | `test_emp_resets_exposed_electronics_and_spares_the_hardened`, `test_emp_warhead_in_flight` | 20 s reset external, half internal, none mechanical; hardened survives a pulse that resets the plain mast; no structural damage |
| 5 | Nuclear option: armour shields crew, heat, no momentum | `test_nuclear_armour_shields_the_crew_and_heat_spikes`, `test_nuclear_burst_imparts_no_momentum` | deaths behind bare hull, none behind 80 mm; heat = 120 K × dose; velocity unchanged |
| 6 | Launcher stock persists and is restocked for credits | `test_missiles_persist_and_restock_for_credits`, `test_launcher_reload_and_stock` | save round trip; 60 cr each, partial when short; 4 s reload (Milestone 9: 8 cr, 0.4 s cycle) |
| 7 | Enemies use missiles; designs stay valid | `test_templates_and_enemy_designs_validate` | rack from mission 4, EMP sometimes from 6; all valid |
| — | Player fires M at a locked target | `smoke_main.gd` | missile in flight, `MSL` on the strip |

Simplifications: see ARCHITECTURE.md "Missiles and EMP (Milestone 7)".

## Milestone 8 — Vertical-slice polish ✅ (2026-10-20)

Spec exit criterion: a new player can design or choose a ship, fight, take
damage, recover, repair and understand what happened. Verified in
`tests/unit/test_m8_polish.gd` unless noted.

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Mission objectives with rewards | `test_the_mission_chain_pays_and_moves_on`, `smoke_campaign` | disable → capture → escort → waves → patrol; rewards paid once; failed goals retried; saved |
| 2 | Tutorial flow, skippable, saved | `test_the_tutorial_follows_what_the_player_does`, `smoke_main` | F2 starts; steps advance on events in order; skip/restart; carries over to the station's repair step |
| 3 | Clear damage reports | `test_the_debrief_opens_with_a_sortie_summary`, `test_the_hit_cam_caption_says_how_the_round_got_in`, renders | goal, dealt, taken (side), lost, crew at the top |
| 4 | Performance under load | `test_the_simulation_keeps_a_60_hz_budget_under_load`, `tools/bench_sim.gd` | ~1 ms mean per tick with 200+ rounds and 12 missiles (budget 8 ms) |
| 5 | Design system and font fallbacks | `test_design_tokens_match_the_design_system` | #050508 / #0A0E14 / #00D4C8 / #F5C842; Space Grotesk and JetBrains Mono first, with fallbacks |
| 6 | Save/load hardening | `test_saves_keep_a_rolling_backup_and_never_leave_temp_files`, `test_a_damaged_profile_is_restored_from_its_backup`, `test_schema_5_migrates_a_v4_save_and_keeps_the_original`, compat check on a copy of the real profile | atomic + verified write, `.bak`, recovery with a message, schema 3/4 → 5 migration round-trips |
| — | **Exit:** choose a ship, fight, take damage, recover, repair, understand | `smoke_campaign` (fight, salvage, jump, repair, refit, relaunch) with the mission reward; `smoke_main` (tutorial) | pass |

## Milestone 9 — Play-test batch 2: salvos, wrecks, crew ✅ (2026-10-20)

GAME_DESIGN.md §17 ends at Milestone 8; this one is the user's second
play-test list. Verified in `tests/unit/test_m9_weapons_crew.gd` unless noted.

| Request | Verified by | Result |
|---|---|---|
| More missiles per launcher; cheap restock | `test_launchers_hold_more_and_restock_cheaply`, `test_missiles_persist_and_restock_for_credits` | 12 / 6 / 3 (+ 48 saturation); 8 / 20 / 150 / 2 cr |
| M fires everything; modes all / conventional / EMP / nuclear / sequence | `test_salvo_modes_pick_their_warheads`, `test_a_salvo_empties_the_chosen_launchers_and_nothing_else`, `test_a_sequence_salvo_fires_in_order`, `test_missile_mode_and_order_are_saved`, `smoke_main` | rack emptied in ~5 s; EMP ×6 then conventional ×12 |
| Missile explosions, also when shot down | `test_a_missile_shot_down_breaks_up_with_a_burst`, renders | fireball + sound on break-up and on small warheads |
| Beaten enemies stay, silent | `test_a_beaten_ship_stays_as_a_silent_derelict`, `smoke_campaign`, `smoke_boarding` | wreck + craft re-keyed, derelict; no rounds, no PD; drifts clear |
| Saturation missile | `test_the_saturation_pod_launches_a_swarm_of_weaker_missiles` | 8 a launch, fanned out; ~¼ of the penetration |
| Crew management UI; crew dots | `test_the_crew_roster_helpers`, `smoke_main` (CREW tab roster), renders | map dots by post, roster tree, send-to |
| Boarders before N; party beyond 8 | `test_boarding_parties_can_be_bigger_and_we_see_who_would_go` | limit 24; target card / CREW tab show who would go |

## Next — agreed roadmap (2026-10-20)

GAME_DESIGN.md §17 ends at Milestone 8; the user set the roadmap below. One
milestone per session, in this order: **M10 → Pass A → M11 → M12 → M13 → M14
→ M15** (Pass A may run before M10 on request; it is independent).

Decisions already made:

1. **Audio:** bundle CC0 samples, each verified individually and recorded in
   `data/ATTRIBUTION.md` (source URL, author, licence, date). Diegetic rule
   kept (your own ship through the hull; no sound in vacuum). Synthesis stays
   as the fallback for any missing slot. Small budget: OGG for loops and long
   sounds, WAV for short hits; report the total size.
2. **Jump drive costs propellant**: main tank first, then a jump-only
   reserve (thrusters and RCS can't use it). Cost scales with distance and
   ship mass (data-driven formula). Unaffordable jumps are refused with a
   reason; a stranded fallback (e.g. a paid rescue tow) prevents a
   soft-lock; the emergency jump keeps working.
3. **Jumps go to mapped, known locations**, unlocked by paid information
   brokers and stored in the profile. Earth and the Moon start known.
4. **Real solar-system bodies** at real scale and real orbital data, incl.
   real artifacts (M14). One central body per location; no n-body gravity.
5. **Ship policies:** player-customisable automation for the player's ship
   on top of manual gunnery (manual input always wins, never blocked); the
   same policy engine drives the enemy AI (enemies are policies built by
   the enemy factory).
6. **Alerts** are redesigned in Pass A.

### Milestone 10 — multi-contact encounters, ship policies, smarter AI ✅ (2026-10-20)

Verified in `tests/unit/test_m10_contacts.gd` and `smoke_encounter.gd`
unless noted; all existing smoke suites pass (changes to `smoke_main`
justified in the changelog).

| # | Acceptance criterion | Verified by | Result |
|---|---|---|---|
| 1 | Contact registry; ≥ 3 hostiles + craft, each with its own track, hostility, AI, wing, wreck state; key to cycle; full card + compact list; radar and overview show all | `test_the_encounter_registry_selects_cycles_and_reselects`, `test_each_contact_keeps_its_own_track_and_policy`, `smoke_encounter`, renders | 3 contacts at mission 7; U cycles 02 → 03 → 01; card lists the other two; radar 3; Tab › TARGET 3 buttons |
| 2 | Missions, capture/boarding, salvage, waves, escort, tutorial against the selected contact; existing smoke suites pass | `smoke_main`, `smoke_campaign`, `smoke_boarding`, `smoke_wing`, `smoke_shipyard`, `smoke_encounter` (salvages the selected, non-lead contact; the lead untouched) | all pass |
| 3 | Roles, focus fire, salvos by policy, player over a derelict | `test_roles_fight_at_their_own_ranges`, `test_focus_fire_and_never_a_derelict`, `test_enemy_salvos_launch_the_policy_count`, `smoke_encounter` | standoff backs off at 3 km and closes at 12 km; focus on the player over a nearer fighter; salvos of 2–4; 4 missiles inbound; standoff 4.2 km vs closer 2.4 km |
| 4 | PD priorities, range, reserve; missile + craft + round at once | `test_point_defence_engages_in_policy_order`, `test_point_defence_respects_range_and_ammo_reserve`, `test_flak_destroys_a_heavy_slug_but_not_small_or_fast_rounds`, `test_point_defence_never_engages_its_own_side` | missile, then craft, then round; reversed order → round first; nothing beyond 600 m; below reserve only missiles |
| 5 | Policy engine: presets, editable, saved per vessel (schema 6, migration, backup), manual override | `test_policy_presets_and_discipline`, `test_auto_fire_and_manual_override`, `test_auto_salvo_conditions`, `test_policy_round_trips_and_is_clamped`, `test_schema_6_gives_old_vessels_the_defensive_policy`, `smoke_encounter` | Tab › POLICY switches presets; manual fire under HOLD fires; v5 → v6 with `.v5` kept |
| 6 | Bench: 3 hostiles with wings and salvos inside 8 ms; ~300-module hull spike | `test_a_three_ship_encounter_stays_inside_the_tick_budget`, `tools/bench_sim.gd`, `tools/bench_hull.gd` | 3.7 ms mean, 17.6 ms worst (1 of 3,600 ticks over 8 ms: a warhead strike); hull: validation 8 ms, compile 10 ms, systems 91 ms (crew roster — must change before capital ships), hit test 0.16 ms/round |
| 7 | Mutation checks | see below | each fails exactly its test |

Mutation-checked (`--only=test_m10`, 15 tests): sorting point-defence
candidates by distance only fails `test_point_defence_engages_in_policy_order`;
ignoring the salvo count fails `test_enemy_salvos_launch_the_policy_count`;
dropping the manual trigger from `ShipPolicy.trigger` fails
`test_auto_fire_and_manual_override`; a `cycle` that doesn't advance fails
`test_the_encounter_registry_selects_cycles_and_reselects`. Restored: 15/15.

Brief vs repo: the brief assumed point defence could already engage
rounds — it couldn't (craft and missiles only); flak against heavy slugs was
added, limited to what PD can plausibly track.

1. A contact registry (stable ids) replaces the single hard-wired enemy. An
   encounter supports ≥ 3 hostile ships plus their craft; each contact has
   its own sensor track, hostility, gunnery AI, wing and wreck state. A key
   cycles / selects the target; the HUD shows a full card for the selected
   contact and a compact list for the others; radar and the tactical
   overview show all.
2. Missions, capture/boarding, salvage, waves, escort and the tutorial work
   against the selected contact; the existing smoke tests (campaign,
   boarding, wing, main, shipyard) pass, any change justified in the
   changelog.
3. Enemies engage in roles (one closes, one stands off) and can focus fire;
   they fire missile salvos (several per launch, by policy); they prefer the
   player over a derelict.
4. Point-defence priorities: policy-ordered (default missiles → craft →
   rounds), engagement range, ammunition reserve. Tested with a missile, a
   craft and a round incoming at once: PD engages in policy order.
5. Policy engine: a typed, data-driven `Policy` resource with presets (Hold,
   Defensive, Standard, Aggressive) and editable parameters. Player
   controls: auto point-defence (priorities, ranges, ammo reserve),
   auto-salvo (lock quality, range band, warhead mode, count), auto-fire
   (solution within tolerance and a lock held) and fire discipline (hold /
   tight / free). Editable in the Tab drawer or shipyard, saved per vessel
   (schema bump, migration, backup, tests). Manual input always overrides.
6. Performance: bench a 3-hostile encounter with wings and salvos inside the
   8 ms tick budget (report mean and worst). Spike a ~300-module hull:
   validation, compile and hit-test times; say whether anything must change
   before capital ships (don't build them yet).
7. Mutation checks: policy ordering, salvo count, manual override, contact
   selection.

### Play-test batch 3 — map, lunar orbit, big-fight performance ✅ (2026-10-20)

Requested after play: "1v3 is too hard", "it lags" with four ships' missiles,
three ships' fighters and everyone's rounds, and "a map so the player can
select where to launch from the shipyard (1/2/3 ship encounter), as well as
moon orbit (and its shipyard)". Part of Milestone 13 brought forward (the
`Location` resource, the Moon, a map and known locations); jump fuel,
brokers, contracts, Mars and per-station stock stay in Milestone 13.

| Requirement | Test | Measured |
|---|---|---|
| Lag in the big fight | `tools/profile_frames.gd` (manual, needs a GPU) | 23 → 75 fps mean; p95 157 → 20 ms; frames over 50 ms 170 → 1 in 40 s |
| Merged hull keeps every piece; redrawn on wear and wrecks | `test_render_batching` (4, wear mutation-checked) | 96 pieces → 1 mesh, 1104 / 1104 triangles |
| Pick the encounter size, 1–3 | `smoke_shipyard` (map buttons), `test_m10_contacts`, `smoke_encounter` | 2 picked → 2 contacts |
| Pick the station on a map; launch from its orbit; jump back to it | `smoke_shipyard` (mouse click on the Moon; location wiring mutation-checked) | 100.0 km, 1634 m/s about the Moon; Lunar Shipyard after B |
| Real Moon: μ, radius, orbit, pole, spin, shadow | `test_locations` | 1633.5 m/s, 117.8 min; pole 1.51° from the ecliptic pole; 27.32-day spin |
| Earth unchanged by the generalised frame | `test_locations` (old reference values), `test_celestial` | identical to 1e-6 |
| Save format: schema 7, migration, backup | `test_locations`, `build/compat_check.gd` | v6 → Earth, 1 ship, `.v6` kept; COMPAT: OK |

### Pass A — alerts and audio ✅ (2026-10-20)

| Requirement | Test | Measured |
|---|---|---|
| Fixed grammar: noun, one value, direction, key chip; length limit | `test_pass_a` (grammar; every HUD alert) | ≤ 26 characters, e.g. `MSL 2.4km 002`, `RND 0.4s 330 [R]` |
| ≤ 3 visible, deduplicated, priority | `test_pass_a` (priority, dedupe) | danger › caution › advisory, then threat › damage › systems › nav › info |
| Hysteresis, escalation, auto-clear, acknowledge | `test_pass_a` (hysteresis, acknowledge) | clears 0.8 s after its condition; up at once, down after 1 s; [.] hides a non-danger until it clears or escalates |
| Every alert has a clear condition | `test_pass_a` (prop, round, scram, fire, jump appear and clear) | all appear and clear |
| A sound per class; samples on buses with ducking | `test_pass_a` (sounds) | 5 alarm classes; 17 slots from samples; alarms duck effects and ambience by 9 dB |
| Screen-edge threat indicator; damage-map flash; persistent status | render review (`build/screens/alerts_*.png`), smoke_main | chevrons on/at the edge, `STATUS RCT ■ BRCH ■ FIRE ■ VENT ■` |
| CC0 audio, verified, budget | `data/ATTRIBUTION.md`, `test_pass_a` | Kenney CC0 packs (licence file in each), 21 files, 641 kB |

Original brief:

- Audit every HUD alert string; a fixed grammar replaces sentences: shape or
  icon, short noun, one value, direction where relevant, a key chip (e.g.
  `MSL 2.1s 040 up [S]`); at most ~four words plus a number.
- Priority queue: ≤ 3 visible, deduplicated, hysteresis (no flicker),
  escalation (caution → danger), auto-clear when resolved, acknowledge/mute
  for non-critical ones.
- Non-text cues: a sound per alert class, a screen-edge direction indicator
  for incoming threats, the affected system flashing on the damage map;
  persistent compact status for reactor, breach, fire, vent.
- CC0 samples (guns, impacts, missile launch/detonation through the hull,
  alarms, UI, hull and machinery ambience) on audio buses with ducking so
  critical alarms stay audible.
- Tests: length limit, priority order, dedupe, hysteresis, every alert has
  a sound and a clear condition.

### Milestone 11 — countermeasures and electronic warfare ✅ (2026-10-20)

Decoy launcher; missile seekers choose by signature and lose lock under
jamming; jamming degrades sensor-track confidence; hardened masts and
burn-through at close range as counterplay; an EW drone. Deterministic,
seeded tests for decoys and jamming. (Play-test: "on top of PD for missile
defence, implement flares".)

| Requirement | Test | Measured |
|---|---|---|
| Decoy (flare) launcher, flares that fan out and burn out | `test_m11_countermeasures` (launching) | 3 a launch, 1.5 s cycle, 6 s burn |
| Seekers choose by signature; discrimination; seeded | `test_m11` (odds, on-time, too early; seduction mutation-checked) | p = 0.71 fresh flare vs frigate; flares 3.5 s out: decoyed, unhurt; 14 s out: hit; same result twice |
| Jamming degrades tracks; burn-through; hardened mast | `test_m11` (tracks) | 8 km: confidence 0.81 → 0.20, lock lost; 2.5 km: no effect; hardened mast keeps the lock |
| Missiles lose lock under jamming | `test_m11` (locks) | 5/8 at 9 km against a jammer, 0/8 without |
| EW drone | `test_m11` (drone) | covers its carrier within 3 km, not at 5 km |
| Policy, AI, yard | `test_m11` (policy, restock) | auto-flares ≤ 4 s (Defensive/Standard/Aggressive), enemies from mission 3, 1 cr a flare |

### Milestone 12 — shipyard overhaul, ship dealer, economy ✅ (2026-10-20)

Shipyard submenus (Dealer, Hangar, Crew, Armoury for rearm and refuel,
Repairs, Tech, Loot tables). Every template, incl. Cutter, Corvette and
Frigate Mk I, purchasable for credits: price from parts plus hull with a
markup; no buy-then-scrap arbitrage (tested). Crew bought with credits.
Play-test: "the shipyard UI still is mainly the builder with the other
subparts as afterthought"; "add missions NPC in shipyard"; "add capital
class ships in ship dealership".

| Requirement | Test | Measured |
|---|---|---|
| Sections, the builder one of them; the station page first | `smoke_shipyard` (opens on STATION, 11 sections, REFIT shows the builder), render review | STATION · MISSIONS · DEALER · HANGAR · REFIT · CREW · ARMOURY · REPAIRS · UPGRADES · MAP · LOOT |
| Every template for credits, crew included | `test_m12_shipyard` (for sale, buying), `smoke_shipyard` (BUY button) | Cutter 947 · Corvette 1,621 · Frigate 2,482 · Destroyer 5,243 · Cruiser 11,847 · Carrier 11,959 cr |
| No buy-then-scrap (or scrap-and-recommission) arbitrage | `test_m12_shipyard` (every template) | scrap = 50 % of parts, worth < half the price |
| Rearm and refuel | `smoke_shipyard` (ARMOURY) | explicit button, or at launch as before |
| Mission givers (contracts; from M13) | `test_m12_shipyard` (board), `smoke_shipyard` (accept, abandon) | 4 seeded offers from 5 NPCs; accepting sets location, ships, threat; pays and leaves the chain alone |
| Capital templates (from M15), standard parts, no spawn hitch | `test_m12_shipyard` (capital), `tools/make_capital_templates.gd`, `tools/bench_hull.gd` | 960 / 2,169 / 1,954 t, validate clean, compile 6–14 ms (crew roster was ~90 ms on a 300-module hull, now 10.6 ms) |
| Save format | `test_m12_shipyard` (schema 8), `compat_check` | v7 → v8 keeps `.v7`; COMPAT: OK |

### Steam release preparation ✅ (2026-10-20)

Play-test request: "prepare game for publishing on steam, under
TheBooleanJulian". No Steamworks SDK (a separate decision); uploading
and the store page need the account and are listed in `docs/STEAM.md`.

| Requirement | Test | Measured |
|---|---|---|
| Version and publisher on the executables; Windows and Linux presets | `test_release` | 0.12.0 · TheBooleanJulian · both presets export a 16.9 MB pack |
| Credits and every licence, in game and beside the executable | `test_release` (every `data/ATTRIBUTION.md` row credited), render review | 90 kB of notices; 102 engine components |
| UI at Steam Deck and high resolutions | render review (1280 × 800, 2560 × 1440) | `canvas_items` stretch from 1600 × 900; markers aligned |
| Fullscreen, remembered | `test_release` | F11, `user://settings.cfg` |
| Depot build | `tools/steam_export.sh` (run: stops with a clear message without export templates) | release export not yet run — templates missing |

### Play-test batch 9 — part 6: cargo contracts, remote salvage ✅ (2026-10-21)

Parts 1–5 (fixes, builder, services, crew, economy) are in the CHANGELOG.

| Requirement | Test | Measured |
|---|---|---|
| Non-combat missions: cargo delivery | `test_batch9_cargo` (mutation-checked) | 40 of 120 offers cargo, 290–830 cr; 217 m³ refused by a 216 m³ hold; delivered at the Moon for 700 cr; fails when jettisoned or lost |
| Salvage drones: remote G salvage, no slow cutting | `test_m15_drones` (mutation-checked), `smoke_wing` | beacon reach 8 km with the drone, 2 km without; out 60 s: wreck 90 % → 90 % |

### Play-test batch 6 — auto-fire rate and multi-ship balance ✅ (2026-10-21)

| Requirement | Test | Measured |
|---|---|---|
| Guns auto-fire at a reduced rate | `test_balance_batch6` (rate rule, half rate = half the rounds) | 10 s on the trigger: 20 rounds at full rate, 10 at half |
| Enemies not too strong beyond 1v1 | `tools/balance_sim.gd` (manual), `test_balance_batch6`, `smoke_encounter` | 1v2/1v3 lost in 14–20 s before; now 1v2 survives 480 s at m3/m7, lost 327 s at m5; 1v3 lost 188–273 s |
| Suited crew keep a vented bridge | `test_balance_batch6` | disabled before, fighting now |

### Play-test batch 8 — rescue tow on call ✅ (2026-10-21)

| Requirement | Test | Measured |
|---|---|---|
| Never stranded: a tow for credits | `smoke_campaign` | under fire: blocked, held on → home for 904 cr (hazard pay); Tab button: quote, then home for 462 cr |

### Play-test batch 7 — Δv jumps, the nav chart's course ✅ (2026-10-21)

| Requirement | Test | Measured |
|---|---|---|
| Space travel in Δv, not tonnes | `test_m13_jumps`, `test_m14_artifacts` | Moon 487 m/s for the Frigate and the Cutter alike (33.2 t / 8.5 t); Voyager 1 2,512 m/s vs the Frigate's 1,557 m/s |
| Picking a launch point doesn't jump until LAUNCH | `test_m13_jumps` (course), `smoke_shipyard` | click the Moon: still docked at Earth, course Moon; LAUNCH: lunar orbit, 100.0 km |

### Play-test batch 6 — beam weapons ✅ (2026-10-21)

"Beam and laser weapons can be added (0 travel time but high energy and
heat) to main weapons, drones and fighters."

| Requirement | Test | Measured |
|---|---|---|
| No travel time | `test_beams` | struck in the tick it fired; no round in flight; 56.3 mm at 3 km (expected 56.0) |
| High energy and heat | `test_beams` | +1,440 kW demand over the autocannon; +180,000 kW on the pulse's tick (1,500 kW × 2 s) |
| On fighters and drones | `test_beams` (laser drone mutation-checked) | Lancer: a charge a pulse, IFF through a friend, recharged 40/40 aboard; laser drone shoots down a missile |
| Parts and palette | `test_beams` | turret under Weapons › Guns, Lancer bay under Fighters, laser rack under Drones |

### Play-test batch 6 — performance ✅ (2026-10-21)

"Lag issues are back when thousands of projectiles are fired by many
fighters."

| Requirement | Test | Measured |
|---|---|---|
| Many fighters, thousands of rounds | `tools/profile_frames.gd` (`--carrier`, `--carriers`; manual, needs a GPU) | 3-ship fight 77 → 139 fps; own Carrier vs 3 frigates ~34 → 50 fps; 4 carriers 7 → 20 fps |
| Simulation still correct | full suite (orbits, rounds, PD, craft) | 374/374 |

### Milestone 13 — world map, real bodies, jump fuel, brokers, contracts

Done early (play-test batch 3): `Location` resource, Earth and Moon with
per-body config and NASA textures, the shipyard map, known locations in the
profile. Done early (Milestone 12): the contract board.

Part 1 ✅ (2026-10-20) — jump fuel, per-station shelves and traffic:

| Requirement | Test | Measured |
|---|---|---|
| Jumps cost propellant by mass and distance (data-driven) | `test_m13_jumps` (cost) | Frigate 618 t: home 4.9 t, Earth→Moon 33.7 t |
| Main tank first, then a jump-only reserve | `test_m13_jumps` (pay, relocation; mutation-checked) | 20 t + 20 t → 0 t + 9.5 t after the Moon jump |
| Unaffordable jumps refused with a reason | `test_m13_jumps` (map, contract) | "burns 28.9 t; tanks 10.0 t, reserve 2.0 t — refuel (88 cr)" |
| Stranded fallback; emergency jump still works | `smoke_campaign` (dry tanks) | rescue tow 412 cr; jump home burned 4.9 t as quoted |
| Station stock, prices, encounter table | `test_m13_jumps` (shelves, traffic) | Moon: 4 items ≤ rare, ×1.2, crew fees 400 → 480 cr; corvettes and frigates, threat +1 |
| Save format | `test_m13_jumps` (schema 9), `compat_check` | v8 → full reserve, `.v8` kept; COMPAT: OK |

Part 2 ✅ (2026-10-20) — Mars, brokers, Sun-centred positions:

| Requirement | Test | Measured |
|---|---|---|
| Mars: per-body config, public-domain texture with its licence recorded, size controlled | `test_m13_mars` (place), render review, `data/ATTRIBUTION.md` | 3407 m/s, 113.4 min at 300 km; entry 125 km; USGS/NASA mosaic 4096 × 2048, 2.2 MB |
| Sun-centred positions, real orbital data | `test_m13_mars` (published approaches, perihelion/aphelion, Sun vs Almanac) | 57.58 / 62.07 / 96.09 Mkm (NASA 57.59 / 62.07 / 96.08); 1.381–1.666 AU; Sun differs by precession only |
| `Vec3d` precision proven | `test_m13_mars` (doubles) | ship at Mars: 0 m with doubles, 1,868 m with Vector3 |
| Mars has its own Sun | `test_m13_mars` (mutation-checked) | 68.3° from Earth's on the scenario date |
| Brokers sell locations (decision 3) | `test_m13_mars` (brokers, mutation-checked), render review | Mars 1,500 cr; contracts follow; saved |
| Jumps pay the real distance | `test_m13_mars`, `test_m13_jumps` | Earth→Mars 229 Mkm: 64.6 t; Earth→Moon 400,985 km: 33.9 t |
| Local traffic and shelves | `test_m13_mars` | destroyers among frigates, threat +2; 5 items ≤ epic ×1.5 |

Not done: delivery and retrieve contracts (the board has bounty, capture,
escort, defend and salvage).

`Location` resource (body, start orbit, shipyard stock and prices,
encounter table, broker). Per-body config (μ, radius, entry interface:
atmosphere top / surface plus margin / a defined gas-giant level). Earth,
Moon, Mars first. Public-domain NASA textures (licences recorded, sizes
controlled). Map screen, jump costs (decision 2), broker unlocks, a
contract board (bounty, escort, delivery, defend, retrieve); the four-goal
chain becomes the tutorial thread. Sun-centred locations need `Vec3d`
precision, proven by a test.

### Milestone 14 — orbital artifacts and derelicts

Part 1 ✅ (2026-10-20) — real artifacts:

| Requirement | Test | Measured |
|---|---|---|
| `Artifact` resource (location, trajectory, kind, interaction, reward) | `test_m14_artifacts` (recorded) | 11 objects, each validated, source in ATTRIBUTION |
| Real orbital data from Horizons at a fixed, documented epoch; uncertainty flagged | `test_m14_artifacts` (orbits) | ISS 427 km, 51.8° (real 51.6°; precession ignored); Hubble 28.3°; MRO/Odyssey 92°; Roadster 0.986–1.664 AU; Voyager 1 172.1 AU, escaping |
| Interaction reuses rendezvous, docking tolerances and scans | `smoke_survey` (mutation-checked on range) | within 500 m, ≤ 2 m/s, 20 s with a mast; no start from 3 km |
| Lore-first rewards | `test_m14_artifacts` (once-only fee, codex), MAP render | fee once; record on the MAP |
| Deep space: the Roadster, Voyagers, Pioneers, New Horizons | `smoke_survey` (mutation-checked on the shadow), `test_m14_artifacts` (doubles) | Sun-centred; 3 km kept to 1 mm at 172 AU; 20 s flown, finite |
| JWST left out, and said so | `test_m14_artifacts` | not in the list; ATTRIBUTION, README |
| Save format | `test_m14_artifacts` (schema 10), `compat_check` | v9 → empty codex, `.v9` kept; COMPAT: OK |

Part 2 ✅ (2026-10-20) — derelicts:

| Requirement | Test | Measured |
|---|---|---|
| Wrecks stay | `test_m14_derelicts` (field), `smoke_campaign` (mutation-checked) | the first sortie's wreck lies 5.7 km out on the relaunch |
| Re-salvageable | `test_m14_derelicts` (yield), `smoke_campaign` | 1,000 → 500 → 250 cr scrap; +140 cr the second time; once per sortie |
| Break up over time | `test_m14_derelicts` (decay) | −15 % a sortie; gone below 10 % or after 8 sorties |
| Save format | `test_m14_derelicts` (schema 11), `compat_check` | v10 → empty fields, `.v10` kept; COMPAT: OK |

`Artifact` resource (location, trajectory data, kind, interaction,
reward); interaction reuses rendezvous, docking tolerances, the grapple and
scans. Real objects with orbital data from NASA/JPL Horizons at a fixed,
documented epoch (sources in `data/ATTRIBUTION.md`, uncertainty flagged):
the 2018 Tesla Roadster, Voyager 1 and 2, Pioneer 10 and 11, New Horizons,
the ISS, Hubble and similar. Lore-first rewards. Lagrange-point objects
(JWST) need a rotating frame we don't have: left out, and said so. Wrecks
become re-salvageable and break up over time.

### Milestone 15 — fleet depth ✅ (2026-10-21)

Done early (Milestone 12): the capital templates (Destroyer, Cruiser,
Carrier, generated by `tools/make_capital_templates.gd`) in the dealer; the
crew-roster spawn hitch fixed.

Done early (play-test batch 5, 2026-10-20): the interceptor and bomber as
data with their own racks and AI roles, the EW drone's station-keeping,
friendly-fire safety (clear shot + IFF) and craft separation.

| Requirement | Test | Measured |
|---|---|---|
| No friendly fire between craft | `test_combat_ai` (clear shot, IFF; both mutation-checked) | hold with a friend in line; moved 80 m aside: fire; IFF round passes a friend |
| Craft keep apart | `test_combat_ai` (escorts) | closest pair 73 m over 60 s |
| Interceptor vs missile | `test_combat_ai` | the Hornet shoots a missile aimed at its carrier down |
| Bomber from long range; EW station | `test_combat_ai` | bomber fires at 3.0 km; EW drone 1,212 m out, 0° off the threat line |
| Ramming worse for the lighter ship | `test_combat_ai` | 8 m/s: Cutter −35.5 % (2 modules), Destroyer −0.9 % |
| Auto flares only once armed | `test_combat_ai` (mutation-checked) | armed at 1.5 s; flares due at 4.0 s out |

Done in play-test batch 6 (2026-10-21): the capital templates rebuilt as
armoured battleships with a main battery (`test_m12_shipyard`), rarer parts
sold with them, a camera that sits back for big hulls.

Part 1 ✅ (2026-10-21) — repair and salvage drones:

| Requirement | Test | Measured |
|---|---|---|
| Repair drone | `test_m15_drones` (mutation-checked) | two systems 20 % → 75 % (the field limit) in 20 s; destroyed mast left; no crew repair |
| Salvage drone | `test_m15_drones`, `smoke_wing` | 6 systems cut, 30 parts home after 126 s, wreck 90 % → 58 %; parts into the hold (replaced in play-test batch 9: it carries G's beacon 8 km instead) |

Part 2 ✅ (2026-10-21) — hangar capacity, crew complement and PD that scale
with hull size:

| Requirement | Test | Measured |
|---|---|---|
| Crew complement scales | `test_m15_scaling` | specialists: frigate 12 (unchanged), destroyer 46, cruiser 68, carrier 77 |
| …and the extra crew matter | `test_m15_scaling` (DC mutation-checked) | destroyer: 3 DC teams patch 3 systems in 14 s together; 6 medics treat 3 wounded in 13 s (one treatment) |
| PD coverage scales | `test_m15_scaling` | wanted 1 / 2 / 6 / 8 / 10 (corvette → carrier); every template carries it, 100 % covered; one frigate mount 54 % |
| Hangar capacity | `test_m15_scaling` | carrier 16 craft vs 2 on frigate, destroyer and cruiser (bays need hangar area) |

Milestone 15 ✅.

More craft as data (interceptor, bomber, repair and salvage drones, EW
drone); capital templates (destroyer, cruiser, carrier) in the dealer, only
once the M10 hull spike shows it is safe; hangar capacity, crew complement
and PD coverage scale; templates validate clean with standard parts only.
