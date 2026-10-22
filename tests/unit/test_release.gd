extends TestCase
## Measures: Steam release prep — a version, TheBooleanJulian on the
## executables, a Windows and a Linux export preset, credits and every
## licence shipped (in game and as a file), every data source credited, the
## UI scaling with the window, and a remembered fullscreen toggle.

const SETTINGS := "user://test_release_settings.cfg"


func test_version_and_publisher() -> void:
	var v := Credits.version()
	print("    measured: version %s" % v)
	assert_true(RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$").search(v) != null, "a x.y.z version (%s)" % v)
	var presets := ConfigFile.new()
	assert_true(presets.load("res://export_presets.cfg") == OK, "export presets load")
	var platforms := {}
	for section: String in presets.get_sections():
		if section.ends_with(".options") or not presets.has_section_key(section, "platform"):
			continue
		platforms[presets.get_value(section, "platform")] = section
	assert_true(platforms.has("Windows Desktop") and platforms.has("Linux"), "Windows and Linux presets (%s)" % ", ".join(platforms.keys()))
	var win: String = platforms.get("Windows Desktop", "") + ".options"
	assert_true(presets.get_value(win, "application/company_name", "") == "TheBooleanJulian", "the Windows executable names TheBooleanJulian")
	assert_true(presets.get_value(win, "application/product_name", "") == "No Safe Orbit", "and the game")
	for section: String in platforms.values():
		assert_true(str(presets.get_value(section, "include_filter", "")).contains("data/blueprints/*.json"), "%s ships the blueprints" % section)


func test_credits_and_licences() -> void:
	var text := Credits.full_text()
	print("    measured: credits and licences %d characters, %d engine components" % [text.length(), Engine.get_copyright_info().size()])
	for needle in ["TheBooleanJulian", "Godot Engine", "Permission is hereby granted", "Yale Bright Star", "Blue Marble", "Moon Kit", "Kenney", "FreeType"]:
		assert_true(text.contains(needle), "credits mention %s" % needle)
	# Every data source in data/ATTRIBUTION.md has a credit line.
	var rows := 0
	var keys := {"stars/": "Yale Bright Star", "earth/": "Blue Marble", "moon/": "Moon Kit", "moon/lola": "LOLA (Lunar Orbiter", "mars/": "Viking Colorized",
		"artifacts/": "Horizons", "audio/": "Kenney", "mercury/": "MESSENGER", "jupiter/": "PIA07782", "phobos/": "Phobos Viking",
		"deimos/": "Stooke", "venus/": "made for the game"}
	for line in FileAccess.get_file_as_string("res://data/ATTRIBUTION.md").split("\n"):
		if not line.begins_with("| `"):
			continue
		rows += 1
		var credited := false
		for k: String in keys:
			if line.contains("`" + k):
				credited = Credits.summary().contains(keys[k])
		assert_true(credited, "credited: %s" % line.left(40))
	assert_true(rows == keys.size(), "every attribution row is known (%d rows) — add a credit for a new one" % rows)


func test_credits_in_the_controls_panel() -> void:
	var panel := ControlsPanel.new()
	panel._ready()
	assert_true(not panel.is_credits_shown() and panel._credits_text.text == "", "the panel opens on the bindings; the licences are not laid out yet")
	panel.show_credits(true)
	assert_true(panel.is_credits_shown() and not panel._grid.visible, "Credits & licences swaps them in")
	assert_true(panel._credits_text.text.contains("Permission is hereby granted"), "with the Godot licence")
	panel.show_credits(true)
	assert_true(not panel.is_credits_shown(), "pressed again: back to the bindings")
	panel.show_credits(true)
	panel.hide_panel()
	assert_true(not panel.is_credits_shown(), "closing resets it")
	panel.free()


func test_window_scales_and_fullscreen_is_remembered() -> void:
	assert_true(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items"
		and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "the UI scales with the window from 1600 × 900")
	var f11 := false
	for ev in InputMap.action_get_events(&"toggle_fullscreen"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F11:
			f11 = true
	assert_true(f11, "F11 toggles fullscreen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	assert_true(not DisplaySettings.load_fullscreen(SETTINGS), "windowed by default")
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", 0.5)
	cfg.save(SETTINGS)
	DisplaySettings.save_fullscreen(true, SETTINGS)
	assert_true(DisplaySettings.load_fullscreen(SETTINGS), "fullscreen is remembered")
	cfg.load(SETTINGS)
	assert_true(cfg.get_value("audio", "volume", 0.0) == 0.5, "other settings are kept")
	DisplaySettings.save_fullscreen(false, SETTINGS)
	assert_true(not DisplaySettings.load_fullscreen(SETTINGS), "and windowed again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
