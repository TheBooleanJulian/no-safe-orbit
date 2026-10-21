extends TestCase
## Measures: play-test batch 11, part 3 — the refit bay. A part's text is its
## cell's colour; families share a colour (the dense magazine the
## magazine's, lasers one cyan) and differ by shape; RCS blocks are white;
## 1×1 and 3×3 hull blocks, trusses and a 3×3 slope; "power distro"; a
## hangar needs a way out, and its door opens as craft come and go; the
## rendered top-down view looks straight down.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func test_colours_and_shapes() -> void:
	var cat := _catalog()
	var eq := cat.equipment
	assert_true(cat.rooms[&"dense_magazine"].color == cat.rooms[&"magazine"].color, "the dense magazine is the magazine's red")
	var lasers := [&"fibre_laser_turret", &"laser_turret", &"free_electron_laser_turret", &"laser_fighter_bay", &"laser_drone_rack"]
	for id: StringName in lasers:
		assert_true((eq[id] as EquipmentDefinition).color == (eq[&"laser_turret"] as EquipmentDefinition).color, "%s is laser cyan" % id)
	var shapes := {}
	for id: StringName in [&"laser_turret", &"laser_fighter_bay", &"laser_drone_rack", &"autocannon", &"missile_rack"]:
		shapes[str(EquipmentIcons.shape(eq[id]))] = id
	print("    measured: 5 parts, %d shapes; laser cyan %s; RCS %s" % [shapes.size(), (eq[&"laser_turret"] as EquipmentDefinition).color.to_html(false),
		(eq[&"rcs_block"] as EquipmentDefinition).color.to_html(false)])
	assert_true(shapes.size() == 5, "the laser turret, laser fighters and laser drones differ by shape (and the guns, the missiles)")
	assert_true((eq[&"rcs_block"] as EquipmentDefinition).color.get_luminance() > 0.95, "RCS blocks are white")
	var icon := EquipmentIcons.icon(eq[&"laser_fighter_bay"], Color.WHITE)
	var lit := 0
	var img := icon.get_image()
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				lit += 1
	assert_true(icon.get_width() == EquipmentIcons.ICON_PX and lit > 20, "a palette icon (%d px lit)" % lit)
	# Palette text is the cell's colour (lifted only when too dark to read).
	for id: StringName in [&"laser_turret", &"missile_rack", &"fighter_bay"]:
		var c := (eq[id] as EquipmentDefinition).color
		assert_true(Shipyard.palette_color(c) == c, "%s: the text is the cell colour" % id)
	assert_true((eq[&"power_distribution_unit"] as EquipmentDefinition).display_name == "Power distro", "power distro")


func test_new_hull_pieces() -> void:
	var hull := _catalog().hull
	var sizes := {}
	for id: StringName in [&"hull_block_1x1", &"hull_block_3x3", &"truss_1x1", &"truss_3x3", &"wedge_3x3"]:
		var def: HullModuleDefinition = hull.get(id)
		assert_true(def != null and not def.legacy, "%s is in the palette" % id)
		if def != null:
			sizes[String(id)] = "%d×%d%s" % [def.size_cells.x, def.size_cells.z, " slope" if def.is_wedge() else ("" if def.interior else " truss")]
	print("    measured: %s" % sizes)
	# A block of each placed together: one hull, valid shapes, a model built.
	var bp := ShipBlueprint.new()
	bp.add_module(&"hull_block_3x3", Vector3i(0, 0, 0))
	bp.add_module(&"hull_block_1x1", Vector3i(3, 0, 1))
	bp.add_module(&"truss_3x3", Vector3i(0, 0, 3))
	bp.add_module(&"truss_1x1", Vector3i(1, 0, 6))
	bp.add_module(&"wedge_3x3", Vector3i(0, 0, -3))
	var grid := ShipGrid.build(bp, _catalog())
	var r := ShipValidator.validate(bp, _catalog())
	assert_true(grid.module_at.size() == 9 + 1 + 9 + 1 + 9 and not r.has_code(&"module_overlap") and not r.has_code(&"module_detached"),
		"29 cells, joined, no overlaps (%d)" % grid.module_at.size())
	var model := ShipModelBuilder.build(bp, grid, Vector3.ZERO)
	assert_true(["m1", "m2", "m3", "m4", "m5"].all(func(id: String) -> bool: return model.parts.has(id)), "each drawn")
	model.root.free()


func test_hangars_need_a_way_out_and_their_doors_open() -> void:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var bay := -1
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def != null and not def.is_external() and def.kind == EquipmentDefinition.Kind.CRAFT_MOUNT:
			bay = i
	var door := ShipGrid.door_face(bp, grid, bay)
	print("    measured: the frigate's fighter bay %s opens at %s" % [bp.equipment[bay].id, door])
	assert_true(not door.is_empty() and not ShipValidator.validate(bp, _catalog()).has_code(&"hangar_enclosed"), "it has a way out")
	# Built round so every face of its hangar is inside the hull: an error.
	var shut := bp.duplicate_blueprint()
	var room: int = grid.room_at.get(bp.equipment[bay].cell, -1)
	for c in ShipGrid.room_cells(bp.rooms[room]):
		for n: Vector3i in ShipGrid.FACE_NORMALS.values():
			var next: Vector3i = c + n
			if not grid.module_at.has(next):
				shut.add_module(&"hull_block_1x1", next)
	var shut_grid := ShipGrid.build(shut, _catalog())
	var report := ShipValidator.validate(shut, _catalog())
	print("    measured: walled in — %s" % (report.issues.filter(func(i: ShipValidator.Issue) -> bool: return i.code == &"hangar_enclosed").map(func(i: ShipValidator.Issue) -> String: return i.message)))
	assert_true(ShipGrid.door_face(shut, shut_grid, bay).is_empty() and report.has_code(&"hangar_enclosed"), "no way out: an error")
	# The door slides open while a craft comes or goes, then shuts.
	var view := ShipView.new()
	view.blueprint = bp
	view.grid = grid
	view.stats = ShipStats.compute(bp, grid)
	view._ready()
	var id := bp.equipment[bay].id
	assert_true(view._hangar_doors.has(id), "the bay has a door")
	view.show_docked_craft(id, false)
	view._move_hangar_doors(2.0)
	var open := view.hangar_door_open(id)
	for k in 10:
		view._move_hangar_doors(1.0)
	print("    measured: door %.0f %% open 2 s after launch; %.0f %% after 12 s" % [open * 100.0, view.hangar_door_open(id) * 100.0])
	assert_true(open > 0.99 and view.hangar_door_open(id) < 0.01, "opens for the launch, shuts after")
	view.free()


func test_the_rendered_top_down_view() -> void:
	var p := ShipPreview3D.new()
	p.isometric = true
	p.plan = true
	p._ready()
	p._update_camera()
	var cam := p._camera
	print("    measured: camera looks along %s, screen right %s, up %s" % [-cam.transform.basis.z, cam.transform.basis.x, cam.transform.basis.y])
	assert_true((-cam.transform.basis.z).is_equal_approx(Vector3.DOWN), "straight down")
	assert_true(cam.transform.basis.x.is_equal_approx(Vector3(0, 0, -1)) and cam.transform.basis.y.is_equal_approx(Vector3(-1, 0, 0)),
		"fore to the right, port at the top, as the deck plan")
	p.free()
