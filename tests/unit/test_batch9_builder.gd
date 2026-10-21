extends TestCase
## Measures: play-test batch 9, part 2 — the builder. A long radiator turned
## out as a fin takes one cell of the hull and stands its length straight
## out (refused where hull is in the way); bigger engine and reactor rooms
## add thrust and output, a roomier hangar turns craft round faster; point
## defence draws its rounds from the magazine (bigger magazine, more rounds;
## restocked at the yard; a warning without one); the grappling arm lies
## folded along four cells and unfolds to what it holds.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _frigate() -> ShipBlueprint:
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())


func test_a_radiator_turned_out_as_a_fin() -> void:
	var bp := _frigate()
	var grid := ShipGrid.build(bp, _catalog())
	var def: EquipmentDefinition = _catalog().equipment[&"radiator_long"]
	# A clear spot: a dorsal face with three empty cells above it, and one
	# that has hull above it within three cells (under an overhang), if any.
	var clear := Vector3i.MAX
	var blocked := Vector3i.MAX
	var cells: Array = grid.module_at.keys()
	cells.sort()
	var taken := {}
	for j in bp.equipment.size():
		var other := grid.equipment_def(j)
		if other != null and other.is_external():
			for c in grid.external_cells(j):
				taken["%s|%s" % [c, bp.equipment[j].face]] = true
	for face: StringName in [&"dorsal", &"port", &"starboard", &"ventral"]:
		for cell: Vector3i in cells:
			if not grid.is_exterior_face(cell, face) or grid.slope_faces(cell).has(face) or taken.has("%s|%s" % [cell, face]):
				continue
			var n: Vector3i = ShipGrid.FACE_NORMALS[face]
			var hit := false
			for k in range(1, 4):
				hit = hit or grid.is_hull(cell + n * k)
			if hit and blocked == Vector3i.MAX:
				blocked = cell
				bp.set_meta("blocked_face", face)
			elif not hit and clear == Vector3i.MAX and face == &"dorsal":
				clear = cell
	assert_true(clear != Vector3i.MAX, "a dorsal face with room for a fin")
	var fin := bp.add_equipment(&"radiator_long", clear, &"dorsal", ShipGrid.FIN_ROTATION)
	grid = ShipGrid.build(bp, _catalog())
	var i := bp.equipment.find(fin)
	var r := ShipValidator.validate(bp, _catalog())
	print("    measured: fin at %s — %d hull cell, stands in %s; issues: %s" % [clear, grid.external_cells(i).size(), grid.fin_cells(i), r.summary()])
	assert_true(grid.external_cells(i) == [clear] and grid.fin_cells(i).size() == def.length_cells, "one cell of the hull, %d cells out" % def.length_cells)
	assert_true(not r.has_errors(), "valid where nothing is in the way")
	var again := BlueprintIO.from_json(BlueprintIO.to_json(bp), PackedStringArray())
	assert_true(again != null and again.equipment[i].rotation == ShipGrid.FIN_ROTATION, "saved and loaded, still a fin")
	var stats := ShipStats.compute(bp, grid)
	var plain := ShipStats.compute(_frigate(), ShipGrid.build(_frigate(), _catalog()))
	assert_near(stats.heat_rejection_kw - plain.heat_rejection_kw, def.heat_rejection_kw, 1.0, "rejects as much as the panel lying flat (kW)")
	if blocked != Vector3i.MAX:
		bp.remove(fin.id)
		var face: StringName = bp.get_meta("blocked_face")
		var bad := bp.add_equipment(&"radiator_long", blocked, face, ShipGrid.FIN_ROTATION)
		var r2 := ShipValidator.validate(bp, _catalog())
		assert_true(r2.errors().any(func(x: ShipValidator.Issue) -> bool: return x.code == &"fin_blocked" and x.subject == bad.id),
			"refused where hull stands in its way: %s" % r2.summary())
	# Saved designs keep their radiators lying across the hull (rotation 1).
	var across := _frigate()
	var cross := across.add_equipment(&"radiator_long", clear, &"dorsal", 1)
	assert_true(ShipGrid.build(across, _catalog()).external_cells(across.equipment.find(cross)).size() == def.length_cells, "rotation 1 still lies across, 3 cells")


func test_bigger_rooms_do_more() -> void:
	var cat := _catalog()
	for name in ["frigate_mk1", "destroyer_mk1", "carrier_mk1"]:
		var bp := BlueprintIO.load_file("res://data/blueprints/%s.json" % name, PackedStringArray())
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		var raw := 0.0
		var extra := {}
		for r in bp.rooms:
			extra[r.def_id] = int(extra.get(r.def_id, 0)) + r.rect.size.x * r.rect.size.y - 1
		for k in bp.equipment.size():
			var d := grid.equipment_def(k)
			if d != null and d.kind == EquipmentDefinition.Kind.MAIN_ENGINE and bp.equipment[k].face == &"aft":
				raw += d.thrust_n
		var want := ShipStats.size_gain(int(extra.get(&"engine_room", 0)), ShipStats.ROOM_SIZE_GAIN, ShipStats.ROOM_SIZE_SCALE)
		var cfg := stats.to_ship_config(name)
		var sys := ShipSystems.create(bp, grid, stats, cfg)
		var flight := sys.effective_config()
		print("    measured: %s — engine rooms +%d cells → ×%.2f thrust (%.2f MN, in flight %.2f MN at the default power split), reactor rooms ×%.2f, hangar ×%.1f" % [
			name, int(extra.get(&"engine_room", 0)), stats.engine_room_factor, stats.thrust_forward_n / 1e6,
			flight.thrust_forward_n / 1e6, stats.reactor_room_factor, stats.hangar_factor])
		assert_near(stats.engine_room_factor, want, 1e-6, "%s: the engine rooms' extra cells set the factor" % name)
		assert_near(stats.thrust_forward_n, raw * stats.engine_room_factor, 1.0, "%s: main thrust carries it (N)" % name)
		assert_near(flight.thrust_forward_n, stats.thrust_forward_n * sys.channel_factor(ShipSystems.Channel.ENG), 1.0,
			"%s: in flight too (N)" % name)
	# Every cell more adds, less each time.
	var g1 := ShipStats.size_gain(1, ShipStats.ROOM_SIZE_GAIN, ShipStats.ROOM_SIZE_SCALE)
	var g7 := ShipStats.size_gain(7, ShipStats.ROOM_SIZE_GAIN, ShipStats.ROOM_SIZE_SCALE)
	var g8 := ShipStats.size_gain(8, ShipStats.ROOM_SIZE_GAIN, ShipStats.ROOM_SIZE_SCALE)
	var g99 := ShipStats.size_gain(99, ShipStats.ROOM_SIZE_GAIN, ShipStats.ROOM_SIZE_SCALE)
	print("    measured: engine room gain +1 cell %.3f, +7 %.3f, +8 %.3f, +99 %.3f" % [g1, g7, g8, g99])
	assert_true(ShipStats.size_gain(0, 0.25, 12.0) == 1.0 and g1 > 1.0 and g8 > g7 and g8 - g7 < g1 - 1.0 and g99 <= 1.0 + ShipStats.ROOM_SIZE_GAIN,
		"every cell adds, the first most, never past the gain")
	assert_true(Shipyard.room_size_text(cat.rooms[&"engine_room"]).begins_with("BIGGER IS BETTER") \
		and Shipyard.room_size_text(cat.rooms[&"corridor"]).contains("only connects"), "the room card says what size does")


func test_point_defence_draws_from_the_magazine() -> void:
	var cat := _catalog()
	var bp := _frigate()
	var grid := ShipGrid.build(bp, cat)
	var stats := ShipStats.compute(bp, grid)
	var pd_gun: KineticCannonConfig = stats.pd_gun
	var expected := floori(stats.magazine_kg * ShipStats.PD_MAGAZINE_SHARE / pd_gun.round_mass_kg + 1e-6)
	print("    measured: frigate magazine %.1f t — %d gun rounds, %d PD rounds (was 2 × %d built in)" % [stats.magazine_kg / 1000.0,
		stats.rounds_capacity, stats.pd_rounds_capacity, pd_gun.magazine_rounds])
	assert_true(stats.pd_rounds_capacity == expected and expected > 0, "PD takes %d %% of the magazine" % roundi(ShipStats.PD_MAGAZINE_SHARE * 100.0))
	var cfg := stats.to_ship_config("me")
	var s := ShipState.create(&"me", "me", cfg, Vector3.ZERO)
	assert_true(s.pd_rounds == stats.pd_rounds_capacity and s.pd_rounds_capacity == stats.pd_rounds_capacity, "the ship starts with the magazine's PD rounds")
	# A bigger magazine: more PD rounds.
	var big := _frigate()
	for r in big.rooms:
		if r.def_id == &"magazine":
			r.def_id = &"dense_magazine"
	var big_stats := ShipStats.compute(big, ShipGrid.build(big, cat))
	print("    measured: dense magazine %.1f t — %d PD rounds" % [big_stats.magazine_kg / 1000.0, big_stats.pd_rounds_capacity])
	assert_true(big_stats.magazine_kg <= stats.magazine_kg or big_stats.pd_rounds_capacity > stats.pd_rounds_capacity, "more magazine, more PD rounds")
	# Spent rounds are restocked at the yard.
	var p := PlayerProfile.new(3)
	p.ensure_vessel(_frigate())
	p.vessel.condition["stores"] = {"propellant_kg": stats.propellant_capacity_kg, "rounds": stats.rounds_capacity, "pd_rounds": 100}
	var need := ServiceYard.resupply_needs(p.vessel, cat)
	assert_true(int(need.pd_rounds) == stats.pd_rounds_capacity - 100 and int(need.credits) > 0, "the yard restocks %d PD rounds" % int(need.pd_rounds))
	# No magazine: a warning.
	var none := _frigate()
	none.rooms = none.rooms.filter(func(r: ShipBlueprint.PlacedRoom) -> bool: return r.def_id != &"magazine")
	var r := ShipValidator.validate(none, cat)
	assert_true(r.warnings().any(func(x: ShipValidator.Issue) -> bool: return x.code == &"pd_no_magazine"), "PD without a magazine is warned of")


func test_the_grappling_arm_unfolds_to_what_it_holds() -> void:
	var cat := _catalog()
	var def: EquipmentDefinition = cat.equipment[&"grapple_arm"]
	var bp := _frigate()
	var grid := ShipGrid.build(bp, cat)
	var arm_index := -1
	for k in bp.equipment.size():
		if bp.equipment[k].def_id == &"grapple_arm":
			arm_index = k
	assert_true(def.length_cells == 4 and arm_index >= 0 and grid.external_cells(arm_index).size() == 4, "the arm lies along four cells")
	assert_true(not ShipValidator.validate(bp, cat).has_errors(), "the Frigate still validates (its arm slid to fit)")
	var stats := ShipStats.compute(bp, grid)
	var view := ShipView.new()
	view.blueprint = bp
	view.grid = grid
	view.stats = stats
	view._ready()
	var id := bp.equipment[arm_index].id
	var arm: Dictionary = view._arms[id]
	var root: Vector3 = arm.folded[0]
	var claw := arm.claw as Node3D
	var folded_tip := claw.position
	var grip := root + Vector3(0, 30, -25)
	view.grapple_holds = {id: grip}
	for i in 150:
		view._move_arms(DT)
	var out := claw.position.distance_to(grip)
	view.grapple_holds = {}
	for i in 150:
		view._move_arms(DT)
	var back := claw.position.distance_to(folded_tip)
	print("    measured: claw %.2f m from a grip %.0f m out after %.1f s; folded back to %.2f m of its rest" % [out, root.distance_to(grip),
		150 * DT, back])
	assert_true(out < 0.5 and back < 0.01, "out to the grip, and folded back")
	view.free()
