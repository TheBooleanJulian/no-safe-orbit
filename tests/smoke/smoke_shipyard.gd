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
	# The yard opens on the station page; the builder is the REFIT section.
	_check(yard.sections.current == "STATION" and yard.sections.pages.size() == ShipyardSections.SECTIONS.size()
		and yard.sections.station_label.get_parsed_text().contains("CREDITS"),
		"the shipyard opens on its STATION page, %d sections" % yard.sections.pages.size())
	# The station directory (play-test batch 6): a place per section, each
	# with its live line; the berth has the dockmaster's log.
	var lines := yard.sections.directory_status()
	_check(yard.sections.buttons.size() == ShipyardSections.SECTIONS.size() and lines.size() == ShipyardSections.SECTIONS.size()
		and (yard.sections.status_labels["SERVICES"] as Label).text != ""
		and (yard.sections.station_cards["log"] as RichTextLabel).get_parsed_text().contains("DOCKMASTER"),
		"the station directory lists every place with a live line (%s); the berth has the dockmaster's log" % (yard.sections.status_labels["CREW"] as Label).text)
	(yard.sections.buttons["CREW"] as Button).pressed.emit()
	_check(yard.sections.current == "CREW", "a directory entry opens its place")
	yard.show_section("REFIT")
	await _frames(2)
	_check(yard.deck_editor.is_visible_in_tree() and not yard.sections.pages["STATION"].visible, "REFIT shows the builder")
	# Esc in the builder drops the tool in hand first; then it opens the
	# settings menu (the station doesn't pause); Esc closes it.
	yard.set_tool(Shipyard.Tool.HATCH)
	await _key(KEY_ESCAPE)
	var tool_dropped := yard.tool == Shipyard.Tool.SELECT and not yard.settings.visible
	await _key(KEY_ESCAPE)
	var opened := yard.settings.visible and not paused
	yard.settings.show_tab("CHANGELOG")
	await _frames(2)
	var log_shown := yard.settings._changelog.get_parsed_text().contains("0.16.0")
	await _key(KEY_ESCAPE)
	_check(tool_dropped and opened and log_shown and not yard.settings.visible,
		"Esc drops the hatch tool, then opens the settings menu (changelog shown), then closes it")

	var ed := yard.editor
	_check(ed.blueprint.name == "Frigate Mk I" and ed.report.issues.is_empty(), "shipyard opens on the Frigate Mk I template with no issues")
	_check(yard.issue_text.get_parsed_text().contains("No issues") and not yard.launch_button.disabled, "validation panel reads clean; launch enabled")
	_check(yard.stats_label.text.contains("MASS") and yard.stats_label.text.contains("MAGAZINE   1.2 t · 1020 rounds · 600 PD rounds"), "stats panel shows mass and magazine (point defence drawing from it)")
	await process_frame
	var side := yard._crew_tab.find_child("HallAndRest", true, false)
	_check(yard._crew_tab.find_child("CrewBoard", true, false) != null and side != null and side.find_child("Hall", true, false) != null
		and side.find_child("DeptResting", true, false) != null and yard._crew_tab.find_child("FillBerths", true, false) != null
		and yard._vendor_tab.get_child_count() > 1 and yard._tech_tab.find_child("TechGraph", true, false) != null,
		"the crew manifest (departments; hiring hall and resting crew on the right; fill berths), quartermaster and upgrades are filled")

	# Searchable, categorised palette.
	yard.palette_search.text = "radiator"
	yard.palette_search.text_changed.emit("radiator")
	var names := yard.palette_items()
	_check(names.size() == 4 and " ".join(names).contains("Radiator panel (3 cells) 1×3 — along")
		and " ".join(names).contains("Radiator panel (3 cells) 3×1 — fin, 3 out") and " ".join(names).contains("Heat-pipe radiator 3×1"),
		"search 'radiator' lists both long radiators, each both ways round: %s" % ", ".join(names))
	# A fin's ghost stands out from the face (play-test batch 11), not along it.
	yard.select_palette("equipment", &"radiator_long")
	yard.place_rotation = ShipGrid.FIN_ROTATION
	yard._hover_cell = Vector3i(2, 1, 6)
	yard._hover_face = &"port"
	yard._update_ghost()
	_check(yard.deck_editor.ghost_out == 3 and yard.deck_editor.ghost_cells.size() == 1, "the fin's ghost: one cell, standing 3 out (%d)" % yard.deck_editor.ghost_out)
	yard.place_rotation = 0
	yard._update_ghost()
	_check(yard.deck_editor.ghost_out == 0 and yard.deck_editor.ghost_cells.size() == 3, "laid along the hull: three cells")
	yard.palette_search.text = ""
	yard.palette_category.select(Shipyard.CATEGORIES.find("Weapons"))
	yard.palette_category.item_selected.emit(yard.palette_category.selected)
	var weapons := yard.palette_items()
	_check(weapons.size() == 13 and " ".join(weapons).contains("Railgun") and " ".join(weapons).contains("Yb-fibre laser turret")
		and " ".join(weapons).contains("Nd:YAG pulse laser turret") and " ".join(weapons).contains("Free-electron laser turret") and " ".join(weapons).contains("Point-defence")
		and " ".join(weapons).contains("Missile rack") and " ".join(weapons).contains("Flare launcher") and " ".join(weapons).contains("EW jammer"),
		"the Weapons category lists the guns, point defence, launchers and countermeasures: %s" % ", ".join(weapons))
	var first := 0
	while first < yard.palette_list.item_count and not yard.palette_list.is_item_selectable(first):
		first += 1
	_check(not yard.palette_list.is_item_selectable(0) and yard.palette_list.get_item_text(0).strip_edges() == "Guns",
		"sections head the list (%s)" % yard.palette_list.get_item_text(0).strip_edges())
	yard.palette_list.select(first)
	yard.palette_list.item_selected.emit(first)
	_check(yard.tool == Shipyard.Tool.PLACE and yard.place_kind == "equipment", "picking from the list arms the place tool")
	yard.set_tool(Shipyard.Tool.SELECT)
	yard.expand_view("3d")
	await _frames(2)
	var row_w := (yard.preview.get_parent() as Control).size.x
	_check(not yard.deck_editor.visible and yard.preview.visible and not yard.side_view.visible and yard.preview.size.x > 0.9 * row_w,
		"the 3D preview expands, to the full width (%.0f of %.0f px)" % [yard.preview.size.x, row_w])
	yard.expand_view("front")
	await _frames(2)
	_check(yard.front_view.visible and yard.front_view.size.x > 0.9 * row_w, "so does the front view (%.0f of %.0f px)" % [yard.front_view.size.x, row_w])
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

	# The map: the route button opens it; click the Moon, pick two ships.
	_check(yard.route_button.text.contains("EARTH ORBIT") and yard.route_button.text.contains("1 SHIP"),
		"a new player launches from Earth orbit against one ship (%s)" % yard.route_button.text)
	yard.route_button.pressed.emit()
	await _frames(3)
	_check(yard.map_tab.is_visible_in_tree(), "the route button opens HANGAR › MAP")
	var moon_at: Vector2 = yard.system_map.disc(Location.by_id("moon"))[0]
	await _click(yard.system_map, moon_at)
	await _frames(2)
	var title := yard.get_node("Margin/VBox/TopBar/Title") as Label
	_check(yard.profile.location == "earth" and yard.profile.launch_point() == "moon" and title.text == "EARTH SHIPYARD"
		and yard.route_button.text.contains("→ LUNAR ORBIT") and yard.route_button.text.contains("Δv"),
		"clicking the Moon lays in a course — still docked at Earth until launch (%s · %s)" % [title.text, yard.route_button.text])
	yard.size_buttons[1].pressed.emit()
	var saved := PlayerProfile.load_file(PlayerProfile.path, PackedStringArray())
	_check(yard.profile.encounter_size == 2 and saved.location == "earth" and saved.encounter_size == 2,
		"two ships picked and saved; the berth is still Earth's (%s, %d)" % [saved.location, saved.encounter_size])

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
		var alt := main.world.altitude_of(player)
		var speed := main.world.pci_velocity(player.velocity).length()
		_check(main.world.body.display_name == "Moon" and absf(alt - 100_000.0) < 500.0 and absf(speed - 1633.0) < 5.0,
			"launched into lunar orbit: %s, %.1f km, %.0f m/s" % [main.world.body.display_name, alt / 1000.0, speed])
		_check(player.propellant_kg >= player.config.propellant_capacity_kg - 1.0,
			"topped up at the Lunar Shipyard on arrival: %.1f of %.1f t" % [player.propellant_kg / 1000.0, player.config.propellant_capacity_kg / 1000.0])
		_check(main.hud.weapon_label.text.contains("FUEL") and main.hud.weapon_label.text.contains("Δv"), "the weapon strip shows the fuel left")
		var earth_km: float = main.sky.sky_body_center.length() / 1000.0 if main.sky.sky_body != null else 0.0
		_check(main.sky.sky_body != null and main.sky.sky_body.display_name == "Earth" and earth_km > 356_000.0 and earth_km < 407_000.0,
			"Earth hangs in the lunar sky (%.0f km)" % earth_km)
		var hidden := PlanetSky.below_horizon(main.sky.planet_center, main.world.body.radius_m, main.sky.sky_body_center)
		var expect := 0.0 if hidden else Main.SUN_ENERGY * main.sky.sky_body_light
		_check(absf(main.sky_light.light_energy - expect) < 1e-4 and (hidden or main.sky_light.light_energy > 0.0),
			"earthlight on the ship by Earth's phase (%.3f of the Sun's energy, Earth %s)" % [
				main.sky_light.light_energy / Main.SUN_ENERGY, "below the horizon" if hidden else "up"])
		_check(main.encounter.contacts.size() == 2 and main.hud.station_name == "Lunar Shipyard",
			"two ships to meet; the jump drive goes to the Lunar Shipyard (%d, %s)" % [main.encounter.contacts.size(), main.hud.station_name])
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
		_check(back != null and (back.get_node("Margin/VBox/TopBar/Title") as Label).text == "LUNAR SHIPYARD",
			"the jump drive brought it to the Lunar Shipyard")
		if back != null:
			await _dealer_and_services(back)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("smoke_shipyard: %d failure(s)" % _failures.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + PlayerProfile.BACKUP_SUFFIX))
	quit(1 if not _failures.is_empty() else 0)


## The station's other sections, through their buttons: the DEALER sells a
## Cutter (crew included), the HANGAR scraps it, the ARMOURY rearms.
func _dealer_and_services(yard: Shipyard) -> void:
	var p := yard.profile
	yard.show_section("DEALER")
	# The cards come one a frame (play-test batch 10: twelve hulls).
	var waited := 0
	while yard.sections.dealer_rows.size() < BlueprintIO.list_templates().size() and waited < 600:
		await process_frame
		waited += 1
	_check(yard.sections.dealer_rows.size() == BlueprintIO.list_templates().size(), "the dealer shows all %d hulls" % yard.sections.dealer_rows.size())
	var cutter_path := ""
	for path: String in yard.sections.dealer_rows:
		if path.contains("cutter"):
			cutter_path = path
	var price := ServiceYard.dealer_price(BlueprintIO.load_file(cutter_path, PackedStringArray()), yard.editor.catalog)
	p.credits = int(price.total) + 50
	yard.sections.refresh()
	var buy: Button = yard.sections.dealer_rows[cutter_path]
	var ships := p.vessels.size()
	_check(not buy.disabled and buy.text.contains(str(price.total)), "the dealer offers the Cutter at %d cr (%s)" % [price.total, buy.text])
	buy.pressed.emit()
	await _frames(2)
	_check(p.vessels.size() == ships + 1 and p.vessel.blueprint.name == "Cutter Mk I" and p.credits == 50 and yard.sections.current == "HANGAR",
		"bought: the Cutter is the active vessel, paid in full, and the hangar shows it")
	var parts := p.spare_parts
	yard.sections.refresh()
	yard.sections.scrap_button.pressed.emit()
	await _frames(2)
	_check(p.vessels.size() == ships and p.spare_parts > parts, "scrapped for %d spare parts" % (p.spare_parts - parts))
	yard.show_section("MISSIONS")
	await _frames(2)
	var offer: Dictionary = p.board[0]
	var size_before := p.encounter_size
	(yard.sections.accept_buttons[str(offer.id)] as Button).pressed.emit()
	await _frames(2)
	# A cargo contract (play-test batch 9) keeps the chosen fight size and loads its freight.
	var sized := p.vessel.cargo.has("freight") and p.encounter_size == size_before if offer.kind == "cargo" else p.encounter_size == int(offer.ships)
	_check(p.active_contract.get("id", "") == offer.id and p.launch_point() == offer.location and sized,
		"MISSIONS: accepting %s sets the next sortie's course (%s → %s, %d ships)" % [offer.title, p.location, p.launch_point(), p.encounter_size])
	yard.sections.abandon_button.pressed.emit()
	await _frames(2)
	_check(p.active_contract.is_empty(), "and it can be abandoned")
	# The service bay (play-test batch 9): a big button each to repair,
	# rearm and refuel, with the cargo hold; spare parts are the quartermaster's.
	var cat := yard.editor.catalog
	var st := ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, cat))
	p.vessel.condition["stores"] = {"propellant_kg": st.propellant_capacity_kg * 0.5, "rounds": st.rounds_capacity / 2,
		"pd_rounds": st.pd_rounds_capacity / 2, "jump_reserve_kg": JumpDrive.standard().reserve_capacity_kg(st.propellant_capacity_kg)}
	p.credits = 5000
	yard.show_section("SERVICES")
	await _frames(2)
	var sb: Dictionary = yard.sections.service_buttons
	_check((sb.repair as Button).is_visible_in_tree() and (sb.rearm as Button).is_visible_in_tree() and (sb.refuel as Button).is_visible_in_tree()
		and (sb.refuel as Button).text.begins_with("REFUEL ·") and (sb.rearm as Button).text.begins_with("REARM ·"),
		"the SERVICE BAY has its three buttons (%s / %s / %s)" % [(sb.repair as Button).text, (sb.rearm as Button).text, (sb.refuel as Button).text])
	(sb.refuel as Button).pressed.emit()
	await _frames(2)
	var after: Dictionary = ServiceYard.resupply_needs(p.vessel, cat)
	_check(float(after.propellant_kg) <= 0.0 and int(after.rounds) > 0, "REFUEL fills the tanks, not the magazine")
	(sb.rearm as Button).pressed.emit()
	await _frames(2)
	after = ServiceYard.resupply_needs(p.vessel, cat)
	_check(int(after.rounds) == 0 and int(after.pd_rounds) == 0 and not p.vessel.condition.has("stores"), "REARM fills the magazine and point defence")
	_check(not (yard._bank_button.get_parent() as Node).get_children().any(func(n: Node) -> bool: return n is Button and (n as Button).text.contains("parts")),
		"the cargo hold no longer sells spare parts")
	yard.show_section("QUARTERMASTER")
	await _frames(2)
	var parts_before := p.spare_parts
	var credits_before := p.credits
	yard.parts_amount = 120
	_check(yard.buy_spare_parts(yard.parts_amount) and p.spare_parts == parts_before + 120 and p.credits == credits_before - PlayerProfile.parts_price(120),
		"the QUARTERMASTER sells any number of spare parts (120 for %d cr)" % PlayerProfile.parts_price(120))
	_check(yard._vendor_tab.find_child("BuyParts", true, false) != null and yard._vendor_tab.is_visible_in_tree(), "with a counter and a buy button")
