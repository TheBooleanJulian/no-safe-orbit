extends SceneTree
## End-to-end smoke test of the shipyard (spec M2 exit criteria: modify a
## ship, validate it, save it and launch it).
##   godot --headless --path . -s res://tests/smoke/smoke_shipyard.gd
## Measures: template loads clean; a real mouse click on the deck editor
## places equipment; validation reacts to edits; launch is blocked by
## errors; save/load round-trips; launch flies the design's own numbers;
## B in flight returns to the shipyard with the same design.

var _failures := PackedStringArray()
## A script error aborts the coroutine before quit(); never hang the checks.
const WATCHDOG_S := 120.0


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("smoke_shipyard: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
		quit(2))
	_run.call_deferred()


func _check(condition: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if condition else "FAIL", what])
	if not condition:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _click(control: Control, local_pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var pos := control.get_global_rect().position + local_pos
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await process_frame


func _key(keycode: Key, ctrl: bool = false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame


func _run() -> void:
	print("== smoke_shipyard")
	# A throwaway profile: never touch the player's real save.
	PlayerProfile.path = "user://smoke_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	root.size = Vector2i(1600, 900)
	Main.launch_blueprint = null
	var yard: Shipyard = (load("res://scenes/shipyard/shipyard.tscn") as PackedScene).instantiate()
	root.add_child(yard)
	current_scene = yard
	await _frames(3)

	var ed := yard.editor
	_check(ed.blueprint.name == "Frigate Mk I" and ed.report.issues.is_empty(), "shipyard opens on the Frigate Mk I template with no issues")
	_check(yard.issue_text.get_parsed_text().contains("No issues") and not yard.launch_button.disabled, "validation panel reads clean; launch enabled")
	_check(yard.stats_label.text.contains("MASS") and yard.stats_label.text.contains("MAGAZINE   400 rounds"), "stats panel shows mass and magazine")

	# Searchable, categorised palette.
	yard.palette_search.text = "radiator"
	yard.palette_search.text_changed.emit("radiator")
	var names := PackedStringArray()
	for i in yard.palette_list.item_count:
		names.append(yard.palette_list.get_item_text(i))
	_check(names.size() == 2 and " ".join(names).contains("Radiator panel") and " ".join(names).contains("Heat-pipe radiator"),
		"search 'radiator' lists both radiators: %s" % ", ".join(names))
	yard.palette_search.text = ""
	yard.palette_category.select(Shipyard.CATEGORIES.find("Weapons"))
	yard.palette_category.item_selected.emit(yard.palette_category.selected)
	var weapons := PackedStringArray()
	for i in yard.palette_list.item_count:
		weapons.append(yard.palette_list.get_item_text(i))
	_check(weapons.size() == 4 and " ".join(weapons).contains("Railgun") and " ".join(weapons).contains("Point-defence"),
		"the Weapons category lists the guns and point defence: %s" % ", ".join(weapons))
	yard.palette_list.select(0)
	yard.palette_list.item_selected.emit(0)
	_check(yard.tool == Shipyard.Tool.PLACE and yard.place_kind == "equipment", "picking from the list arms the place tool")
	yard.set_tool(Shipyard.Tool.SELECT)
	yard.expand_view("3d")
	await _frames(2)
	_check(not yard.deck_editor.visible and yard.preview.visible and not yard.side_view.visible, "the 3D preview expands")
	yard.expand_view("")
	await _frames(2)
	_check(yard.deck_editor.visible and yard.side_view.visible, "restore brings the deck editor back")
	# Isometric main view: edits the same deck with the same tools.
	var deck_was := yard.deck_editor.deck
	yard.set_main_view("iso")
	await _frames(3)
	_check(yard.iso_view.visible and not yard.deck_editor.visible, "the main view swaps to isometric")
	yard.change_deck(2 - yard.deck_editor.deck)
	var hit := yard.iso_view.pick(yard.iso_view.size * 0.5)
	_check(not hit.is_empty() and hit.cell.y == 2, "a point in the iso view picks a cell on the edited deck (%s)" % str(hit))
	yard.select_palette("bus", &"bus_remove")
	var conduit_before := ed.blueprint.bus.size()
	yard.iso_view.room_dragged.emit(2, Rect2i(0, 0, 20, 20))
	_check(ed.blueprint.bus.size() < conduit_before, "a drag in the iso view edits like the deck editor (conduit %d → %d)" % [conduit_before, ed.blueprint.bus.size()])
	ed.undo()
	yard.set_tool(Shipyard.Tool.SELECT)
	yard.set_main_view("top")
	await _frames(2)
	_check(yard.deck_editor.visible and not yard.iso_view.visible, "and back to top-down")
	yard.change_deck(deck_was - yard.deck_editor.deck)

	# Place a radiator on top of the fuselage with a real mouse click.
	var mass_before := ed.stats.mass_kg
	var rejection_before := ed.stats.heat_rejection_kw
	yard.select_palette("equipment", &"radiator")
	yard.change_deck(1)  # deck 1 → 2
	await _frames(2)
	var target_cell := Vector3i(3, 2, 6)
	var center := yard.deck_editor.cell_rect(target_cell).get_center()
	await _click(yard.deck_editor, center)
	var placed := ed.item_at(target_cell, &"dorsal")
	_check(placed != "", "mouse click placed a radiator on the dorsal face of %s" % target_cell)
	_check(absf(ed.stats.mass_kg - mass_before - 5000.0) < 1.0 and absf(ed.stats.heat_rejection_kw - rejection_before - 1200.0) < 1e-6,
		"stats follow the edit: +5 t, +1200 kW rejection (2-cell panel) (got %+.0f kg, %+.0f kW)" % [ed.stats.mass_kg - mass_before, ed.stats.heat_rejection_kw - rejection_before])

	# Right-click the reactor away: a warning, but launch is still allowed.
	yard.apply_at(Vector3i(3, 0, 8), &"dorsal", MOUSE_BUTTON_RIGHT)
	await _frames(1)
	_check(ed.report.has_code(&"power_deficit") and yard.issue_text.get_parsed_text().contains("Power deficit"),
		"removing the reactor shows a power-deficit warning")
	_check(not yard.launch_button.disabled, "warnings do not block launch:
%s" % ed.report.summary())

	# An overlapping module is an error: launch blocked.
	yard.select_palette("hull", &"nose_section")
	yard.apply_at(Vector3i(2, 0, 0), &"dorsal")
	await _frames(1)
	_check(ed.report.has_code(&"module_overlap") and yard.launch_button.disabled, "overlapping module is an error and disables launch")
	_check(not yard.launch(), "launch() refuses a design with errors")
	# Ctrl+Z twice (real key events): takes back the nose and the reactor removal.
	for i in 2:
		await _key(KEY_Z, true)
	_check(not ed.report.has_errors() and not ed.report.has_code(&"power_deficit") and ed.item_at(Vector3i(3, 2, 6), &"dorsal") != "",
		"two Ctrl+Z undo the last two edits, keeping the radiator")
	await _key(KEY_Y, true)
	_check(ed.report.has_code(&"power_deficit"), "Ctrl+Y redoes the reactor removal")
	await _key(KEY_Z, true)

	# Save, reload, compare.
	yard.name_edit.text = "Smoke Test Frigate"
	yard.name_edit.text_changed.emit(yard.name_edit.text)
	var json := BlueprintIO.to_json(ed.blueprint)
	var path := yard.save_design()
	_check(path != "" and FileAccess.file_exists(path), "design saved to %s" % path)
	_check(yard.load_design(path) and BlueprintIO.to_json(yard.editor.blueprint) == json, "reloaded design is identical")

	# Launch and fly it.
	var expected_mass := yard.editor.stats.mass_kg
	_check(yard.launch(), "launch() accepted the valid design")
	await _frames(4)
	var main := current_scene as Main
	_check(main != null, "flight scene is running after launch")
	if main != null:
		var player := main.world.get_ship(Main.PLAYER_ID)
		_check(player.config.display_name == "Smoke Test Frigate" and absf(player.config.mass_kg - expected_mass) < 1e-3,
			"player flies the launched design (%s, %.1f t)" % [player.config.display_name, player.config.mass_kg / 1000.0])
		# B returns to the shipyard with the same design.
		# Hold B: the jump drive charges for 5 s (sped up here).
		Engine.time_scale = 8.0
		Input.action_press("open_shipyard")
		for i in 900:
			if current_scene is Shipyard:
				break
			await process_frame
		Input.action_release("open_shipyard")
		Engine.time_scale = 1.0
		await _frames(4)
		var back := current_scene as Shipyard
		_check(back != null and back.editor.blueprint.name == "Smoke Test Frigate", "B in flight reopens the shipyard with the flown design")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("smoke_shipyard: %d failure(s)" % _failures.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	quit(1 if not _failures.is_empty() else 0)
