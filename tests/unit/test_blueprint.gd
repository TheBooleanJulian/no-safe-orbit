extends TestCase
## Measures: ship construction (spec §16 "Ship construction") — catalog,
## blueprint save/load, structural attachment, room/access, equipment
## placement, derived mass/CoM/inertia/thrust/torque, power, weapon arcs,
## and that a validated design flies.

const TEMPLATE := BlueprintIO.DEFAULT_TEMPLATE
const TMP_DIR := "user://test_blueprints"


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(TEMPLATE, errors)
	assert_true(errors.is_empty(), "template loads without errors: %s" % ", ".join(errors))
	return bp


func _report(bp: ShipBlueprint) -> ShipValidator.Report:
	return ShipValidator.validate(bp, _catalog())


func _expect(bp: ShipBlueprint, code: StringName, severity: ShipValidator.Severity, what: String) -> void:
	var report := _report(bp)
	var found := report.issues.any(func(i: ShipValidator.Issue) -> bool: return i.code == code and i.severity == severity)
	assert_true(found, "%s → expected %s '%s'; got:\n%s" % [what,
		"ERROR" if severity == ShipValidator.Severity.ERROR else "WARNING", code, report.summary()])


func _stats(bp: ShipBlueprint) -> ShipStats:
	return ShipStats.compute(bp, ShipGrid.build(bp, _catalog()))


# --- Catalog and template -------------------------------------------------

func test_catalog_definitions_are_valid() -> void:
	var cat := _catalog()
	assert_true(cat.validate().is_empty(), "catalog problems: %s" % ", ".join(cat.validate()))
	assert_true(cat.hull.size() >= 5 and cat.rooms.size() >= 8 and cat.equipment.size() >= 5,
		"catalog sizes hull %d rooms %d equipment %d" % [cat.hull.size(), cat.rooms.size(), cat.equipment.size()])


func test_frigate_template_validates_clean_and_compiles() -> void:
	var bp := _template()
	var report := _report(bp)
	assert_true(report.issues.is_empty(), "template has no errors or warnings:\n%s" % report.summary())
	var stats := _stats(bp)
	var cfg := stats.to_ship_config(bp.name)
	assert_true(cfg.validate().is_empty(), "compiled ShipConfig problems: %s" % ", ".join(cfg.validate()))
	assert_true(stats.mass_kg > 300_000.0 and stats.mass_kg < 550_000.0, "frigate mass %.0f kg in 300–550 t" % stats.mass_kg)
	var accel := stats.thrust_forward_n / stats.mass_kg
	assert_true(accel > 5.0 and accel < 12.0, "main-engine acceleration %.2f m/s² in 5–12" % accel)
	assert_near(stats.center_of_mass_m.x, 12.0, 0.25, "CoM on the centreline (x, m)")
	assert_true(cfg.cannon != null and cfg.cannon.magazine_rounds == stats.rounds_capacity and stats.rounds_capacity > 0,
		"cannon fed from the magazine (%d rounds)" % stats.rounds_capacity)


# --- Save / load ----------------------------------------------------------

func test_blueprint_round_trip_has_no_data_loss() -> void:
	var bp := _template()
	var json := BlueprintIO.to_json(bp)
	var errors := PackedStringArray()
	var again := BlueprintIO.from_json(json, errors)
	assert_true(errors.is_empty() and again != null, "re-parse errors: %s" % ", ".join(errors))
	assert_true(BlueprintIO.to_json(again) == json, "JSON identical after a round trip")
	# Through the filesystem as well.
	var path := TMP_DIR.path_join("round_trip.json")
	assert_true(BlueprintIO.save(bp, path) == OK, "save to %s" % path)
	var loaded := BlueprintIO.load_file(path, errors)
	assert_true(loaded != null and BlueprintIO.to_json(loaded) == json, "file round trip identical")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# New ids continue after loaded ones (no id reuse).
	var added := loaded.add_room(&"corridor", 2, Rect2i(3, 4, 1, 1))
	assert_true(added.id == "r122", "next id after a loaded design continues numbering (got %s)" % added.id)


func test_unsupported_or_malformed_files_are_rejected_safely() -> void:
	var errors := PackedStringArray()
	var newer := BlueprintIO.from_json('{"schema_version": 99, "modules": []}', errors)
	assert_true(newer == null and errors.size() == 1 and errors[0].contains("v99"), "newer schema rejected: %s" % ", ".join(errors))
	errors.clear()
	assert_true(BlueprintIO.from_json("{not json", errors) == null and not errors.is_empty(), "malformed JSON rejected")
	errors.clear()
	assert_true(BlueprintIO.from_json('{"name": "x"}', errors) == null and not errors.is_empty(), "missing schema_version rejected")
	errors.clear()
	var partial := BlueprintIO.from_json('{"schema_version": 1, "modules": [{"id": "m1", "def": "nose_section", "pos": [1]}]}', errors)
	assert_true(partial != null and not errors.is_empty(), "bad field reported, rest kept: %s" % ", ".join(errors))


# --- Structure ------------------------------------------------------------

func test_overlapping_modules_detected() -> void:
	var bp := _template()
	bp.add_module(&"nose_section", Vector3i(2, 0, 0))
	_expect(bp, &"module_overlap", ShipValidator.Severity.ERROR, "second nose on top of the first")


func test_detached_module_detected() -> void:
	var bp := _template()
	bp.add_module(&"side_pod", Vector3i(20, 0, 0))
	_expect(bp, &"module_detached", ShipValidator.Severity.ERROR, "pod floating in space")


func test_any_common_face_attaches() -> void:
	# The pod's bare port side against the engine section's bare face: one
	# common face is enough (connector types no longer gate attachment).
	var bp := _template()
	var pod := bp.add_module(&"side_pod", Vector3i(0, 0, 12))
	var report := _report(bp)
	assert_true(not report.issues.any(func(i: ShipValidator.Issue) -> bool: return i.code == &"module_detached" and i.subject == pod.id),
		"a module sharing a face is attached:\n%s" % report.summary())


func test_rotation_maps_faces() -> void:
	assert_true(ShipGrid.rotate_dir(Vector3i(0, 0, -1), 1) == Vector3i(-1, 0, 0), "fore turned 90° CCW faces port")
	assert_true(ShipGrid.rotate_dir(Vector3i(1, 0, 0), 2) == Vector3i(-1, 0, 0), "starboard turned 180° faces port")
	assert_true(ShipGrid.rotated_size(Vector3i(2, 2, 6), 1) == Vector3i(6, 2, 2), "odd rotation swaps width and length")


# --- Rooms, hatches and access --------------------------------------------

func test_rooms_must_be_inside_pressurised_hull() -> void:
	var bp := _template()
	bp.add_room(&"corridor", 2, Rect2i(2, 0, 2, 2))  # nose has decks 0–1 only
	_expect(bp, &"room_outside_hull", ShipValidator.Severity.ERROR, "room above the nose")
	var truss := ShipBlueprint.new()
	truss.add_module(&"fuselage_section", Vector3i(0, 0, 0))
	truss.add_module(&"spine_truss", Vector3i(1, 0, 4))
	truss.add_room(&"cargo_hold", 0, Rect2i(1, 4, 2, 2))
	var report := _report(truss)
	assert_true(report.issues.any(func(i: ShipValidator.Issue) -> bool: return i.code == &"room_outside_hull" and i.message.contains("unpressurised")),
		"room inside an unpressurised truss rejected:\n%s" % report.summary())


func test_overlapping_rooms_detected() -> void:
	var bp := _template()
	bp.add_room(&"corridor", 1, Rect2i(2, 0, 1, 1))  # inside the bridge
	_expect(bp, &"room_overlap", ShipValidator.Severity.ERROR, "corridor inside the bridge")


func test_hatches_must_join_neighbouring_rooms() -> void:
	var bp := _template()
	bp.add_hatch(Vector3i(3, 1, 2), Vector3i(3, 1, 4))
	_expect(bp, &"hatch_not_adjacent", ShipValidator.Severity.ERROR, "hatch spanning two cells")
	var bp2 := _template()
	bp2.add_hatch(Vector3i(2, 0, 0), Vector3i(2, 0, 1))  # empty nose lower deck
	_expect(bp2, &"hatch_not_between_rooms", ShipValidator.Severity.ERROR, "hatch into an empty space")


func test_room_without_access_route_is_reported() -> void:
	var bp := _template()
	bp.remove("h27")  # the only hatch into the starboard cargo hold
	var report := _report(bp)
	var unreachable := report.issues.filter(func(i: ShipValidator.Issue) -> bool: return i.code == &"room_unreachable")
	assert_true(unreachable.size() == 1 and unreachable[0].subject == "r17" and not report.has_errors(),
		"only r17 reported unreachable, as a warning:\n%s" % report.summary())


func test_missing_bridge_is_an_error() -> void:
	var bp := _template()
	bp.remove("r7")
	bp.remove("h18")
	_expect(bp, &"no_command", ShipValidator.Severity.ERROR, "no bridge")


# --- Equipment ------------------------------------------------------------

func test_internal_equipment_needs_a_suitable_room() -> void:
	var bp := _template()
	bp.add_equipment(&"fusion_reactor", Vector3i(2, 0, 4))  # lower corridor (access role)
	_expect(bp, &"equipment_wrong_room", ShipValidator.Severity.ERROR, "reactor in a corridor")
	var bp2 := _template()
	bp2.add_equipment(&"fusion_reactor", Vector3i(2, 1, 4))  # 2×2 across quarters and corridor
	_expect(bp2, &"equipment_outside_room", ShipValidator.Severity.ERROR, "reactor straddling two rooms")


func test_external_equipment_needs_an_exterior_face() -> void:
	var bp := _template()
	bp.add_equipment(&"main_engine", Vector3i(3, 1, 12), &"aft")  # engine-section interior
	_expect(bp, &"equipment_not_exterior", ShipValidator.Severity.ERROR, "engine on an inner face")
	var bp2 := _template()
	bp2.add_equipment(&"main_engine", Vector3i(2, 1, 0), &"fore")
	_expect(bp2, &"engine_needs_engine_room", ShipValidator.Severity.ERROR, "main engine facing forward, no engine room behind it")


func test_obstructed_weapon_arc_reported() -> void:
	var bp := _template()
	bp.add_equipment(&"kinetic_cannon", Vector3i(4, 1, 13), &"dorsal")  # fuselage deck 2 is ahead
	_expect(bp, &"weapon_arc_obstructed", ShipValidator.Severity.WARNING, "cannon behind the fuselage")
	assert_true(not _report(_template()).has_code(&"weapon_arc_obstructed"), "template cannon (over the nose) is clear")


func test_power_deficit_and_missing_magazine_reported() -> void:
	var bp := _template()
	bp.remove("e28")
	_expect(bp, &"power_deficit", ShipValidator.Severity.WARNING, "reactor removed")
	var bp2 := _template()
	bp2.remove("r12")
	bp2.remove("h22")
	_expect(bp2, &"weapon_no_magazine", ShipValidator.Severity.WARNING, "magazine removed")


func test_off_axis_thrust_reported() -> void:
	# Only the two lower engines (thrust line ~2 m below the CoM) and only the
	# two tail RCS blocks: too little pitch authority to fly straight.
	var bp := _template()
	for id in ["e31", "e32", "e33", "e34", "e35", "e36", "e39", "e40"]:
		bp.remove(id)
	_expect(bp, &"thrust_misaligned", ShipValidator.Severity.WARNING, "weak RCS vs engine offset")


# --- Derived physics --------------------------------------------------------

func test_propellant_tanks_set_delta_v() -> void:
	var s := _stats(_template())
	var tank: EquipmentDefinition = _catalog().equipment[&"propellant_tank"]
	assert_near(s.propellant_capacity_kg, 4.0 * tank.propellant_capacity_kg, 1e-6, "four tanks of propellant (kg)")
	assert_near(s.delta_v_m_s(), s.main_isp_s * ShipDynamics.G0 * log(s.wet_mass_kg() / s.mass_kg), 1e-6, "Δv by the rocket equation (m/s)")
	assert_true(s.delta_v_m_s() > 1200.0 and s.delta_v_m_s() < 2200.0, "frigate main-engine Δv %.0f m/s in 1.2–2.2 km/s" % s.delta_v_m_s())
	var cfg := s.to_ship_config("x")
	assert_true(not cfg.unlimited_propellant and cfg.propellant_capacity_kg == s.propellant_capacity_kg, "compiled config models propellant")
	var dry := _template()
	for id in ["e46", "e47", "e48", "e49"]:
		dry.remove(id)
	_expect(dry, &"no_propellant", ShipValidator.Severity.WARNING, "all tanks removed")


func test_every_cannon_mount_compiles() -> void:
	var bp := _template()
	bp.add_equipment(&"kinetic_cannon", Vector3i(4, 2, 4), &"dorsal")
	var cfg := _stats(bp).to_ship_config("x")
	assert_true(cfg.cannon_muzzles_body.size() == 2 and cfg.cannon_mount_ids.size() == 2 and cfg.cannon_mount_ids[0] == "e41",
		"two cannon mounts compiled (%s)" % cfg.cannon_mount_ids)


func test_mass_and_center_of_mass_hand_computed() -> void:
	# Fuselage 12×9×12 m (52 t, centre 6, 4.5, 6), a 1-cell corridor (400 kg,
	# centre 1.5, 1.5, 1.5), a 2-cell radiator on top of cells (0, 2, 0–1)
	# (5 t at 1.5, 9, 3).
	var bp := ShipBlueprint.new()
	bp.add_module(&"fuselage_section", Vector3i.ZERO)
	bp.add_room(&"corridor", 0, Rect2i(0, 0, 1, 1))
	bp.add_equipment(&"radiator", Vector3i(0, 2, 0), &"dorsal")
	var s := _stats(bp)
	assert_near(s.mass_kg, 57_400.0, 1e-6, "total mass (kg)")
	assert_vec_near(s.center_of_mass_m, Vector3(320_100.0, 279_600.0, 327_600.0) / 57_400.0, 1e-4, "centre of mass (m)")


func test_inertia_uses_parallel_axis() -> void:
	# Two 52 t fuselage boxes 12×9×12 m end to end = one 104 t box 12×9×24 m.
	var bp := ShipBlueprint.new()
	bp.add_module(&"fuselage_section", Vector3i(0, 0, 0))
	bp.add_module(&"fuselage_section", Vector3i(0, 0, 4))
	var s := _stats(bp)
	var m := 104_000.0
	var expected := m / 12.0 * Vector3(9.0 * 9.0 + 24.0 * 24.0, 12.0 * 12.0 + 24.0 * 24.0, 12.0 * 12.0 + 9.0 * 9.0)
	assert_vec_near(s.inertia_kgm2, expected, 1.0, "inertia of two boxes = one long box (kg·m²)")


func test_thrust_and_torque_come_from_placed_thrusters() -> void:
	var bp := _template()
	var s := _stats(bp)
	var engine: EquipmentDefinition = _catalog().equipment[&"main_engine"]
	var rcs: EquipmentDefinition = _catalog().equipment[&"rcs_block"]
	assert_near(s.thrust_forward_n, 4.0 * engine.thrust_n, 1e-6, "forward thrust = 4 aft engines (N)")
	assert_near(s.thrust_rcs_n, 8.0 * rcs.thrust_n, 1e-6, "RCS thrust per direction = 8 blocks (N)")
	# Torque about each axis = Σ thrust × lever arm perpendicular to it.
	var grid := ShipGrid.build(bp, _catalog())
	var expected := Vector3.ZERO
	for i in bp.equipment.size():
		if bp.equipment[i].def_id == &"rcs_block":
			var r := grid.equipment_position_m(i) - s.center_of_mass_m
			expected += rcs.thrust_n * Vector3(Vector2(r.y, r.z).length(), Vector2(r.x, r.z).length(), Vector2(r.x, r.y).length())
	assert_vec_near(s.torque_nm, expected, 1.0, "RCS torque capacity (N·m)")
	var fewer := _template()
	fewer.remove("e29")
	assert_near(_stats(fewer).thrust_forward_n, 3.0 * engine.thrust_n, 1e-6, "removing an engine removes its thrust (N)")


func test_compiled_design_flies_with_its_own_numbers() -> void:
	var bp := _template()
	var s := _stats(bp)
	var cfg := s.to_ship_config(bp.name)
	var world := WorldSimulation.new()
	var ship := ShipState.create(&"s", "S", cfg)
	world.add_ship(ship)
	world.set_input(&"s", ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, false))
	for i in 60:
		world.step()
	# Rocket equation over 1 s of full main thrust, starting with full tanks.
	var flow := s.thrust_forward_n / (s.main_isp_s * ShipDynamics.G0)
	var expected := s.main_isp_s * ShipDynamics.G0 * log(s.wet_mass_kg() / (s.wet_mass_kg() - flow))
	assert_near(-ship.velocity.z, expected, 1e-3, "speed after 1 s of the design's own thrust (m/s)")
	assert_near(ship.propellant_kg, s.propellant_capacity_kg - flow, 1.0, "propellant burned in 1 s (kg)")
	assert_true(ship.cannon_rounds == s.rounds_capacity, "ship starts with the magazine's rounds")
