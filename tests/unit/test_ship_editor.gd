extends TestCase
## Measures: shipyard editing operations (place, remove, move, rotate,
## hatches, picking, placement preview) and that validation follows edits.


func _editor() -> ShipEditor:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	return ShipEditor.new(bp, ConstructionCatalog.default_catalog())


func test_place_and_remove_update_validation() -> void:
	var ed := _editor()
	var rev := ed.revision
	var id := ed.place_equipment(&"radiator", Vector3i(3, 2, 6), &"dorsal")
	assert_true(ed.revision > rev and ed.blueprint.find(id) != null, "placed radiator %s" % id)
	assert_true(not ed.report.has_errors(), "radiator on an exterior face is valid:\n%s" % ed.report.summary())
	var bad := ed.place_equipment(&"radiator", Vector3i(3, 1, 6), &"dorsal")  # covered by deck 2
	assert_true(ed.report.has_code(&"equipment_not_exterior"), "inner-face radiator reported")
	assert_true(ed.remove(bad) and not ed.report.has_errors(), "removing it clears the error")


func test_item_at_picks_topmost_part() -> void:
	var ed := _editor()
	assert_true(ed.item_at(Vector3i(3, 0, 8)) == "e28", "reactor cell → reactor (got %s)" % ed.item_at(Vector3i(3, 0, 8)))
	assert_true(ed.item_at(Vector3i(2, 0, 10)) == "r15", "reactor-room cell → room")
	assert_true(ed.item_at(Vector3i(3, 2, 6)) == "m2", "empty deck-2 cell → fuselage module")
	assert_true(ed.item_at(Vector3i(3, 2, 4), &"dorsal") == "e41", "dorsal face of the gun cell → cannon")
	assert_true(ed.item_at(Vector3i(30, 0, 0)) == "", "empty space → nothing")


func test_move_and_rotate() -> void:
	var ed := _editor()
	assert_true(ed.move("e41", Vector3i(0, 0, 1)), "move cannon one cell aft")
	assert_true((ed.blueprint.find("e41") as ShipBlueprint.PlacedEquipment).cell == Vector3i(3, 2, 5), "cannon cell after move")
	assert_true(ed.move("m5", Vector3i(-3, 0, 0)) and ed.report.has_code(&"module_detached"), "pod moved away detaches")
	ed.move("m5", Vector3i(3, 0, 0))
	assert_true(not ed.report.has_code(&"module_detached"), "moved back, attached again")
	assert_true(ed.rotate_module("m6"), "rotate starboard pod")
	assert_true(ed.report.has_code(&"module_detached") or ed.report.has_code(&"module_overlap"),
		"rotated pod no longer fits:\n%s" % ed.report.summary())


func test_undo_and_redo() -> void:
	var ed := _editor()
	var original := BlueprintIO.to_json(ed.blueprint)
	assert_true(not ed.can_undo(), "nothing to undo after loading")
	ed.remove("e28")
	ed.place_equipment(&"radiator", Vector3i(3, 2, 6), &"dorsal")
	var edited := BlueprintIO.to_json(ed.blueprint)
	assert_true(ed.undo() and ed.undo(), "two undos")
	assert_true(BlueprintIO.to_json(ed.blueprint) == original and not ed.report.has_code(&"power_deficit"),
		"undo restores the original design and its validation")
	assert_true(ed.redo() and ed.redo() and BlueprintIO.to_json(ed.blueprint) == edited, "redo replays both edits")
	ed.undo()
	ed.move("e41", Vector3i(0, 0, 1))
	assert_true(not ed.can_redo(), "a new edit clears the redo history")


func test_moving_a_module_carries_its_contents() -> void:
	# The nose holds the bridge, four RCS blocks and the bridge hatch.
	var ed := _editor()
	var original := BlueprintIO.to_json(ed.blueprint)
	ed.move("m1", Vector3i(0, 0, -2))
	var bridge := ed.blueprint.find("r7") as ShipBlueprint.PlacedRoom
	var rcs := ed.blueprint.find("e33") as ShipBlueprint.PlacedEquipment
	assert_true(bridge.rect.position == Vector2i(2, -2) and rcs.cell == Vector3i(2, 1, -1), "bridge and RCS moved with the nose")
	assert_true((ed.blueprint.find("r8") as ShipBlueprint.PlacedRoom).rect.position == Vector2i(3, 3),
		"the corridor spanning nose and fuselage stays put")
	ed.move("m1", Vector3i(0, 0, 2))
	assert_true(BlueprintIO.to_json(ed.blueprint) == original, "moving back restores the design exactly")


func test_rotating_a_module_turns_it_in_place_with_contents() -> void:
	# A free-standing pod (2×2×6) with a cargo hold, a tank and an RCS block.
	var bp := ShipBlueprint.new()
	bp.add_module(&"side_pod", Vector3i(0, 0, 0))
	bp.add_room(&"cargo_hold", 0, Rect2i(0, 0, 2, 6))
	bp.add_equipment(&"propellant_tank", Vector3i(0, 0, 1))
	bp.add_equipment(&"rcs_block", Vector3i(0, 1, 2), &"port")
	var ed := ShipEditor.new(bp, ConstructionCatalog.default_catalog())
	var original := BlueprintIO.to_json(ed.blueprint)
	var center := func(cells: Array[Vector3i]) -> Vector3:
		var sum := Vector3.ZERO
		for c in cells:
			sum += Vector3(c)
		return sum / cells.size()
	var before: Vector3 = center.call(ed.cells_of("m1"))
	ed.rotate_module("m1")
	assert_vec_near(center.call(ed.cells_of("m1")), before, 0.51, "pod turns about its own centre (cells)")
	var placement_codes := [&"room_outside_hull", &"equipment_outside_room", &"equipment_not_exterior", &"equipment_bad_face"]
	assert_true(not ed.report.issues.any(func(i: ShipValidator.Issue) -> bool: return placement_codes.has(i.code)),
		"hold, tank and RCS turned with the pod and still fit:\n%s" % ed.report.summary())
	assert_true((ed.blueprint.find("e4") as ShipBlueprint.PlacedEquipment).face == &"aft", "port-facing RCS faces aft after a CCW quarter turn")
	for i in 3:
		ed.rotate_module("m1")
	assert_true(BlueprintIO.to_json(ed.blueprint) == original, "four quarter turns restore the design exactly")


func test_toggle_hatch() -> void:
	var ed := _editor()
	assert_true(not ed.toggle_hatch(Vector3i(6, 0, 6), Vector3i(5, 0, 6)), "toggling existing hatch (reversed order) removes it")
	assert_true(ed.report.has_code(&"room_unreachable"), "cargo hold now unreachable")
	assert_true(ed.toggle_hatch(Vector3i(5, 0, 7), Vector3i(6, 0, 7)), "new hatch added")
	assert_true(not ed.report.has_code(&"room_unreachable"), "reachable again")


func test_preview_reports_new_errors_without_editing() -> void:
	var ed := _editor()
	var json := BlueprintIO.to_json(ed.blueprint)
	var issues := ed.preview_new_errors(func(bp: ShipBlueprint) -> void: bp.add_module(&"nose_section", Vector3i(2, 0, 0)))
	assert_true(issues.size() >= 1 and issues[0].code == &"module_overlap", "preview predicts the overlap")
	assert_true(BlueprintIO.to_json(ed.blueprint) == json, "preview leaves the blueprint unchanged")
	var none := ed.preview_new_errors(func(bp: ShipBlueprint) -> void: bp.add_equipment(&"radiator", Vector3i(3, 2, 6), &"dorsal"))
	assert_true(none.is_empty(), "valid placement previews clean")


func test_every_part_has_an_engineering_card() -> void:
	var catalog := ConstructionCatalog.default_catalog()
	for entry in [["hull", catalog.hull], ["room", catalog.rooms], ["equipment", catalog.equipment]]:
		for id in entry[1]:
			var text := Shipyard.describe_definition(entry[0], catalog, id)
			assert_true(text.contains("COST") and not text.contains("Connectors"), "%s card has costs and no connector list" % id)
	var gun := Shipyard.describe_definition("equipment", catalog, &"kinetic_cannon")
	assert_true(gun.contains("rpm") and gun.contains("penetration") and gun.contains("uses"), "cannon card: rate of fire, penetration, power:\n%s" % gun)
	var room := Shipyard.describe_definition("room", catalog, &"magazine")
	assert_true(room.contains("PER CELL") and room.contains("rounds"), "room card is per cell:\n%s" % room)


func test_middle_of_a_bottom_cell_picks_the_underside() -> void:
	var ed := ShipEditor.new(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()), ConstructionCatalog.default_catalog())
	var deck := DeckEditor.new()
	deck.editor = ed
	# Deck 0 of the engine section: covered above by deck 1, open below.
	assert_true(deck.vertical_face(Vector3i(3, 0, 13), false) == &"ventral", "bottom deck: the underside")
	assert_true(deck.vertical_face(Vector3i(3, 0, 13), true) == &"dorsal", "Shift: the other face")
	assert_true(deck.vertical_face(Vector3i(3, 2, 6), false) == &"dorsal", "top deck: the top")
	# Right-click in the middle finds an underside RCS too.
	var id := ed.place_equipment(&"rcs_block", Vector3i(2, 0, 13), &"ventral")
	assert_true(ed.item_at(Vector3i(2, 0, 13), &"dorsal") == id, "the underside RCS is found from the middle of its cell")
	assert_true(ed.remove(id) and ed.blueprint.find(id) == null, "and removed")
	deck.free()
