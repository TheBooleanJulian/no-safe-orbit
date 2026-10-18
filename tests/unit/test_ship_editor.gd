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
