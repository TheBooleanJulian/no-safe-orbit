extends TestCase
## Measures: play-test batch 10 — models. A radiator fin folds along its
## length like the flat panel; engine bells grow with thrust (and their
## plumes with them); the docking collar and gangway are hexagonal; the
## berth's gantries are red truss with rotating beacons; craft and missiles
## carry more detail.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func test_a_fin_folds_along_its_length() -> void:
	var normal := Vector3.UP
	var along := Vector3(1, 0, 0)
	var side := along.cross(normal).normalized()
	var fin := ShipModelBuilder.radiator_panels(Vector3.ZERO, normal, along, side, 2.8, 8.8, 1, 3)
	var flat := ShipModelBuilder.radiator_panels(Vector3.ZERO, normal, Vector3(0, 0, 1), Vector3(0, 0, 1).cross(normal).normalized(), 8.8, 3.0, 3, 0)
	var fin_heights := fin.map(func(p: Array) -> float: return (p[0] as Vector3).dot(normal))
	var flat_spans := flat.map(func(p: Array) -> float: return (p[0] as Vector3).z)
	print("    measured: fin — %d panels, centres %.1f → %.1f m off the hull, fold lines along %s; flat — %d panels %.1f → %.1f m along the span" % [
		fin.size(), fin_heights.min(), fin_heights.max(), (fin[0][2] as Basis).y.round(), flat.size(), flat_spans.min(), flat_spans.max()])
	assert_true(fin.size() == 12 and fin_heights.max() - fin_heights.min() > 7.0, "the fin's zigzag runs out from the hull")
	for p: Array in fin:
		assert_true((p[2] as Basis).y.is_equal_approx(along), "each fold line across the fin's width")
	assert_true(flat.size() == 12 and flat_spans.max() - flat_spans.min() > 7.0, "the flat panel's runs along its span, as before")


func test_engine_bells_grow_with_thrust() -> void:
	var sizes := []
	for id: StringName in [&"main_engine_high_isp", &"main_engine", &"torch_drive", &"main_engine_high_thrust"]:
		var def: EquipmentDefinition = _catalog().equipment[id]
		sizes.append([def.thrust_n, ShipModelBuilder.engine_bell(def.thrust_n)])
	var line := ", ".join(sizes.map(func(s: Array) -> String: return "%.0f kN %.2f × %.2f m" % [s[0] / 1000.0, s[1].x, s[1].y]))
	print("    measured: mouth × length — %s" % line)
	for k in range(1, sizes.size()):
		assert_true(sizes[k][1].y > sizes[k - 1][1].y and sizes[k][1].x >= sizes[k - 1][1].x, "more thrust, a bigger bell")
	assert_true(sizes[-1][1].x <= 1.5, "the mouth stays within a cell")
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var model := ShipModelBuilder.build(bp, grid, Vector3.ZERO)
	var engines := bp.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool:
		return _catalog().equipment[e.def_id].kind == EquipmentDefinition.Kind.MAIN_ENGINE).size()
	assert_true(model.engine_widths.size() == engines and model.engine_nozzles.size() == engines, "a plume width per engine")
	model.root.free()


func test_hexagonal_collar_and_gangway() -> void:
	var part := Node3D.new()
	ShipModelBuilder._collar(part, Vector3.ZERO, Vector3.UP)
	var edges := 0
	var hatch_sides := 0
	for c in part.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh:
			edges += 1
		elif c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh:
			hatch_sides = ((c as MeshInstance3D).mesh as CylinderMesh).radial_segments
	var gv := GangwayView.new()
	var tube := gv._make_tube()
	var sides := (tube.mesh as CylinderMesh).radial_segments
	print("    measured: collar %d edges, hatch %d sides; gangway %d sides, ribbed %s" % [edges, hatch_sides, sides,
		(tube.material_override as StandardMaterial3D).albedo_texture != null])
	assert_true(edges == 6 and hatch_sides == 6 and sides == 6, "hexagonal")
	assert_true((tube.material_override as StandardMaterial3D).albedo_texture != null, "ribbed")
	tube.free()
	gv.free()
	part.free()


func test_berth_gantries_are_red_truss_with_turning_beacons() -> void:
	var p := ShipPreview3D.new()
	p.berth = true
	p._ready()
	p._build_berth(Vector3(10, 5, 30))
	var beacons := p._beacon_pivots.size()
	var before := p._beacon_pivots[0].rotation.y
	p._beacon_pivots[0].rotate_y(0.0)
	for pivot in p._beacon_pivots:
		pivot.rotate_y(ShipPreview3D.BEACON_TURN_RAD_S * 0.1)
	var reds := 0
	for c in p._berth.get_children():
		var m := (c as MeshInstance3D).material_override as StandardMaterial3D if c is MeshInstance3D else null
		if m != null and m.albedo_color.r > 0.5 and m.albedo_color.g < 0.15:
			reds += 1
	print("    measured: %d beacons, %d red truss bays; a beacon turned %.2f rad in 0.1 s" % [beacons, reds, wrapf(p._beacon_pivots[0].rotation.y - before, -PI, PI)])
	assert_true(beacons == 4 and reds >= 8, "a beacon atop each of four towers; truss towers and arms")
	assert_near(wrapf(p._beacon_pivots[0].rotation.y - before, -PI, PI), ShipPreview3D.BEACON_TURN_RAD_S * 0.1, 1e-4, "turning (rad)")
	p.free()


func test_craft_and_missiles_carry_more_detail() -> void:
	var fighter := Node3D.new()
	CraftView.build_model(fighter, load("res://data/craft/wasp_fighter.tres"), true, false)
	var drone := Node3D.new()
	CraftView.build_model(drone, load("res://data/craft/recon_drone.tres"), false, false)
	var missile := MissileView._body_mesh(false)
	print("    measured: fighter %d parts, drone %d parts; missile mesh %d surfaces" % [fighter.get_child_count(), drone.get_child_count(),
		missile.get_surface_count()])
	assert_true(fighter.get_child_count() > 15 and drone.get_child_count() > 22, "more detail than before (10 and 16 parts)")
	assert_true(missile.get_surface_count() == 2, "still two surfaces (one draw call each)")
	fighter.free()
	drone.free()
