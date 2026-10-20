extends TestCase
## Measures: the flight view's merged geometry — a ship's hull modules and
## armour plates drawn as one mesh that holds every piece (same triangle
## count, same bounds), redrawn when a plate wears or a module is wrecked;
## an external system's fixed pieces folded into one mesh; missiles sharing
## one body mesh per side.


func _view() -> ShipView:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, ConstructionCatalog.default_catalog())
	var view := ShipView.new()
	view.blueprint = bp
	view.grid = grid
	view.stats = ShipStats.compute(bp, grid)
	view._ready()
	return view


func _systems(view: ShipView) -> ShipSystems:
	return ShipSystems.create(view.blueprint, view.grid, view.stats, view.stats.to_ship_config("t"))


func _triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var idx: Variant = a[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty() \
			else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func _materials(mesh: Mesh) -> Array:
	var out := []
	for s in mesh.get_surface_count():
		out.append(mesh.surface_get_material(s))
	return out


func test_hull_is_one_mesh_holding_every_piece() -> void:
	var view := _view()
	assert_true(not view.blueprint.armor.is_empty(), "the template carries armour plates (%d)" % view.blueprint.armor.size())
	var pieces := view._hull_pieces.size()
	var expected := 0
	var bounds := AABB()
	var first := true
	for piece: MeshInstance3D in view._hull_pieces:
		expected += _triangles(piece.mesh)
		assert_true(not piece.visible, "piece %s is hidden (drawn by the batch)" % piece.name)
		var box := ShipModelBuilder._relative_transform(piece, view._model_root) * piece.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var got := _triangles(view._hull_batch.mesh)
	print("    measured: %d hull pieces, %d triangles merged into %d surfaces (expected %d triangles)" % [
		pieces, got, view._hull_batch.mesh.get_surface_count(), expected])
	assert_true(pieces > 20, "a frigate's hull is many pieces (%d)" % pieces)
	assert_true(got == expected, "the batch holds every piece's triangles (%d / %d)" % [got, expected])
	var batch_box := view._hull_batch.mesh.get_aabb()
	assert_vec_near(batch_box.position, bounds.position, 0.01, "batch bounds start where the pieces' do")
	assert_vec_near(batch_box.end, bounds.end, 0.01, "batch bounds end where the pieces' do")
	view.free()


func test_hull_batch_redraws_worn_plates_and_wrecks() -> void:
	var view := _view()
	var systems := _systems(view)
	var before: Mesh = view._hull_batch.mesh
	view._show_damage(systems)
	assert_true(view._hull_batch.mesh == before, "nothing worn: the batch is not rebuilt")
	var key: String = view.blueprint.armor.keys()[0]
	systems.plates[key] = 0.0
	view._wear_check = 0.0
	view._show_damage(systems)
	var charred: Material = view._char_mats.get(3)
	assert_true(view._hull_batch.mesh != before, "a plate shot through rebuilds the batch")
	assert_true(charred != null and _materials(view._hull_batch.mesh).has(charred), "the batch draws the charred plate")
	var mi := 0
	systems.modules[mi].structure = 0.0
	view._wear_check = 1.0
	view._show_damage(systems)
	assert_true(_materials(view._hull_batch.mesh).has(view._wreck_material), "a wrecked module is drawn wrecked in the batch")
	var mod := view._parts[view.blueprint.modules[mi].id] as MeshInstance3D
	assert_true(not mod.visible, "the wrecked module's own node stays hidden")
	view.free()


func test_equipment_fixed_pieces_merge() -> void:
	var view := _view()
	var merged := 0
	var radiator_meshes := -1
	for e in view.blueprint.equipment:
		var part := view._parts.get(e.id) as Node3D
		# Internal systems (a bay's door: a frame and a hatch) are not merged.
		if part == null or not view.grid.catalog.equipment[e.def_id].is_external():
			continue
		var direct := 0
		for c in part.get_children():
			if c is MeshInstance3D and c.get_child_count() == 0:
				direct += 1
		assert_true(direct <= 1, "%s: fixed pieces are one mesh (%d)" % [e.id, direct])
		if part.get_node_or_null("Static") != null:
			merged += 1
		if view.grid.catalog.equipment[e.def_id].kind == EquipmentDefinition.Kind.RADIATOR:
			radiator_meshes = direct
	print("    measured: %d equipment parts merged; a radiator is %d mesh" % [merged, radiator_meshes])
	assert_true(merged > 0, "some parts were merged (%d)" % merged)
	view.free()


func test_missiles_share_one_body_mesh_per_side() -> void:
	var a := MissileView.new()
	var b := MissileView.new()
	var h := MissileView.new()
	h.hostile = true
	for v in [a, b, h]:
		v._ready()
	var mesh_a := (a.get_child(0) as MeshInstance3D).mesh
	assert_true(mesh_a == (b.get_child(0) as MeshInstance3D).mesh, "two friendly missiles share one body mesh")
	assert_true(mesh_a != (h.get_child(0) as MeshInstance3D).mesh, "hostile missiles have their own (magenta fins)")
	assert_true(a.get_child_count() == 2, "a missile is two meshes, body and exhaust (%d)" % a.get_child_count())
	for v in [a, b, h]:
		v.free()
