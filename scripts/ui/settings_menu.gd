class_name SettingsMenu
extends Control
## The settings menu (Esc), in flight and at the station: window and UI
## scale, graphics, audio, controls, save data, stats, the changelog, game
## info and dev support. In flight it pauses the game while open. Values are
## GameSettings / DisplaySettings (user://settings.cfg), not the profile.

signal closed

const DEV_SUPPORT_URL := "https://forms.gle/XfDSXQJx8z6pi3zXA"
const CHANGELOG_PATH := "res://CHANGELOG.md"
const TABS := ["DISPLAY", "GRAPHICS", "AUDIO", "CONTROLS", "SAVE DATA", "STATS", "CHANGELOG", "ABOUT"]
const PANEL_SIZE := Vector2(1000, 640)
const LABEL_W := 240.0

## Pause the game while open (the flight scene).
var pauses := false
## Whose stats and save the menu shows (set by the scene; may be null).
var profile: PlayerProfile
var tabs: TabContainer
var controls: ControlsPanel
var status: Label
var _panel: PanelContainer
var _was_paused := false
var _fullscreen: CheckButton
var _options: Dictionary = {}  # setting key -> OptionButton
var _sliders: Dictionary = {}  # setting key -> HSlider
var _changelog: RichTextLabel
var _save_label: RichTextLabel
var _stats_label: RichTextLabel
var _licences: Label


## A menu on its own canvas layer above everything in `parent`.
static func attach(parent: Node, pause_game: bool) -> SettingsMenu:
	var layer := CanvasLayer.new()
	layer.name = "SettingsLayer"
	layer.layer = 100
	parent.add_child(layer)
	var menu := SettingsMenu.new()
	menu.name = "Settings"
	menu.pauses = pause_game
	layer.add_child(menu)
	return menu


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = CyberTheme.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", CyberTheme.panel(CyberTheme.CYAN, CyberTheme.SPACE_L, 0.97))
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_color_override("font_color", CyberTheme.CYAN)
	title.add_theme_font_size_override("font_size", CyberTheme.SIZE_TITLE + 3)
	head.add_child(title)
	var ver := Label.new()
	ver.text = "   %s %s" % [str(ProjectSettings.get_setting("application/config/name", "")), Credits.version()]
	ver.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
	ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(ver)
	var resume := _button("Resume  [Esc]", close, CyberTheme.CYAN, true)
	resume.name = "Resume"
	head.add_child(resume)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	_build_display()
	_build_graphics()
	_build_audio()
	_build_controls()
	_build_save()
	_build_stats()
	_build_changelog()
	_build_about()
	tabs.tab_changed.connect(func(_i: int) -> void: _refresh_tab())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	box.add_child(foot)
	status = Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
	foot.add_child(status)
	foot.add_child(_button("Dev support ↗", open_dev_support, CyberTheme.AMBER))
	var quit := _button("Quit to desktop", quit_game, CyberTheme.RED)
	quit.name = "Quit"
	foot.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("release_mouse"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fit()
	_sync_controls()
	_refresh_tab()
	status.text = ""
	if pauses:
		_was_paused = get_tree().paused
		get_tree().paused = true


func close() -> void:
	if not visible:
		return
	visible = false
	if pauses:
		get_tree().paused = _was_paused
	closed.emit()


## The panel fits the window at any UI scale.
func _fit() -> void:
	var view := get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(minf(PANEL_SIZE.x, view.x - 32.0), minf(PANEL_SIZE.y, view.y - 32.0))


func show_tab(tab_name: String) -> void:
	tabs.current_tab = TABS.find(tab_name)


func open_dev_support() -> void:
	OS.shell_open(DEV_SUPPORT_URL)
	status.text = "Opened the dev support form in your browser"


## As if the window were closed: a sortie in progress docks as it is.
func quit_game() -> void:
	get_tree().paused = false
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


# --- Pages ---------------------------------------------------------------------

func _page(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	scroll.add_child(box)
	return box


func _row(page: VBoxContainer, text: String, control: Control, hint: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CyberTheme.SPACE_M)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	row.add_child(l)
	control.custom_minimum_size = Vector2(maxf(control.custom_minimum_size.x, 220.0), 0)
	row.add_child(control)
	if hint != "":
		var h := Label.new()
		h.text = hint
		h.add_theme_color_override("font_color", CyberTheme.TEXT_DIM)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(h)
	page.add_child(row)


func _heading(page: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", CyberTheme.AMBER)
	page.add_child(l)


## An OptionButton over `choices` for setting `key`, labelled by `fmt`.
func _choice(key: String, choices: Array, fmt: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.name = key
	for c: Variant in choices:
		o.add_item(fmt.call(c))
	o.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value(key, choices[i], get_tree())
		status.text = "Saved"
		if key == "ui_scale":
			_fit.call_deferred())
	_options[key] = [o, choices]
	return o


func _build_display() -> void:
	var page := _page("DISPLAY")
	_fullscreen = CheckButton.new()
	_fullscreen.name = "fullscreen"
	_fullscreen.toggled.connect(func(on: bool) -> void:
		if on != DisplaySettings.is_fullscreen():
			DisplaySettings.toggle_fullscreen()
		status.text = "Saved")
	_row(page, "Fullscreen", _fullscreen, "F11 toggles it anywhere")
	_row(page, "UI scale", _choice("ui_scale", GameSettings.UI_SCALES, func(v: float) -> String: return "%d %%" % roundi(v * 100.0)),
		"Text, panels and the HUD; the 3D view is not affected")


func _build_graphics() -> void:
	var page := _page("GRAPHICS")
	var vsync := CheckButton.new()
	vsync.name = "vsync"
	vsync.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value("vsync", on, get_tree())
		status.text = "Saved")
	_options["vsync"] = [vsync, []]
	_row(page, "V-Sync", vsync, "Off: no frame-rate ceiling from the monitor, possible tearing")
	_row(page, "Frame-rate cap", _choice("max_fps", GameSettings.FPS_CAPS, func(v: int) -> String: return "Unlimited" if v == 0 else "%d fps" % v))
	_row(page, "Anti-aliasing (MSAA)", _choice("msaa", GameSettings.MSAA_LEVELS, func(v: int) -> String: return "Off" if v == 0 else "%d×" % v),
		"Smooths the edges of the 3D view")
	_row(page, "3D resolution", _choice("render_scale", GameSettings.RENDER_SCALES, func(v: float) -> String: return "%d %%" % roundi(v * 100.0)),
		"Below 100 % the 3D view is drawn smaller and scaled up: faster, softer; the HUD stays sharp")
	var reset := _button("Reset settings to defaults", func() -> void:
		GameSettings.reset(get_tree())
		_sync_controls()
		_fit.call_deferred()
		status.text = "Settings back to their defaults (the window mode is kept)", CyberTheme.AMBER)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(reset)


func _build_audio() -> void:
	var page := _page("AUDIO")
	for spec in [["volume_master", "Master volume", ""], ["volume_effects", "Effects", "Guns, hits, engines, thrusters"],
			["volume_ambience", "Ambience", "The hull's hum"], ["volume_alarms", "Alarms", "Alert tones (they still duck the rest)"]]:
		var key: String = spec[0]
		var row := HBoxContainer.new()
		var s := HSlider.new()
		s.name = key
		s.min_value = 0
		s.max_value = 100
		s.step = 5
		s.custom_minimum_size = Vector2(260, 0)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var shown := Label.new()
		shown.custom_minimum_size = Vector2(56, 0)
		s.value_changed.connect(func(v: float) -> void:
			shown.text = "%d %%" % roundi(v)
			if absf(float(GameSettings.value(key)) * 100.0 - v) > 0.5:
				GameSettings.set_value(key, v / 100.0)
				status.text = "Saved")
		row.add_child(s)
		row.add_child(shown)
		_sliders[key] = [s, shown]
		_row(page, spec[1], row, spec[2])


func _build_controls() -> void:
	var page := _page("CONTROLS")
	controls = ControlsPanel.new()
	controls.embedded = true
	page.add_child(controls)


func _build_save() -> void:
	var page := _page("SAVE DATA")
	_save_label = _rich()
	page.add_child(_save_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	row.add_child(_button("Open the save folder", func() -> void:
		OS.shell_open(ProjectSettings.globalize_path(PlayerProfile.path.get_base_dir()))))
	var backup := _button("Back up now", func() -> void:
		var to := PlayerProfile.backup_copy()
		status.text = "Backed up to %s" % ProjectSettings.globalize_path(to) if to != "" else "Nothing saved yet to back up"
		_refresh_tab(), CyberTheme.AMBER)
	backup.name = "BackUp"
	row.add_child(backup)
	row.add_child(_button("Open the backups", func() -> void:
		DirAccess.make_dir_recursive_absolute(PlayerProfile.backup_dir())
		OS.shell_open(ProjectSettings.globalize_path(PlayerProfile.backup_dir()))))
	page.add_child(row)


func _build_stats() -> void:
	var page := _page("STATS")
	_stats_label = _rich()
	page.add_child(_stats_label)


func _build_changelog() -> void:
	_changelog = RichTextLabel.new()
	_changelog.name = "CHANGELOG"
	_changelog.bbcode_enabled = true
	_changelog.scroll_active = true
	_changelog.selection_enabled = true
	_changelog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_changelog)


func _build_about() -> void:
	var page := _page("ABOUT")
	var info := _rich()
	info.text = about_text()
	info.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	page.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	row.add_child(_button("Dev support: feedback and bug reports ↗", open_dev_support, CyberTheme.AMBER, true))
	row.add_child(_button("Credits & licences (full)", func() -> void:
		if _licences.text == "":
			_licences.text = Credits.full_text()
		_licences.visible = not _licences.visible))
	page.add_child(row)
	_licences = Label.new()
	_licences.visible = false
	_licences.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_licences.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL)
	_licences.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(_licences)


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func _button(text: String, on_press: Callable, accent: Color = CyberTheme.CYAN, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	CyberTheme.style_button(b, accent, primary)
	b.pressed.connect(on_press)
	return b


# --- Refresh -------------------------------------------------------------------

## Show the saved values.
func _sync_controls() -> void:
	_fullscreen.set_pressed_no_signal(DisplaySettings.is_fullscreen())
	for key: String in _options:
		var entry: Array = _options[key]
		if entry[0] is CheckButton:
			(entry[0] as CheckButton).set_pressed_no_signal(bool(GameSettings.value(key)))
			continue
		var choices: Array = entry[1]
		var v: Variant = GameSettings.value(key)
		var best := 0
		for i in choices.size():
			if absf(float(choices[i]) - float(v)) < absf(float(choices[best]) - float(v)):
				best = i
		(entry[0] as OptionButton).select(best)
	for key: String in _sliders:
		var entry: Array = _sliders[key]
		(entry[0] as HSlider).set_value_no_signal(roundf(float(GameSettings.value(key)) * 100.0))
		(entry[1] as Label).text = "%d %%" % roundi(float(GameSettings.value(key)) * 100.0)


func _refresh_tab() -> void:
	match TABS[tabs.current_tab] if tabs.current_tab >= 0 else "":
		"SAVE DATA":
			_save_label.text = save_text(PlayerProfile.path)
		"STATS":
			_stats_label.text = stats_text(profile)
		"CHANGELOG":
			if _changelog.text == "":
				_changelog.text = changelog_bbcode(FileAccess.get_file_as_string(CHANGELOG_PATH))
		"CONTROLS":
			controls.refresh()


# --- Text ----------------------------------------------------------------------

static func about_text() -> String:
	return "\n".join([
		"[b]%s[/b] %s — a space-combat game of orbits, ship design and salvage." % [str(ProjectSettings.get_setting("application/config/name", "")), Credits.version()],
		"© 2026 %s · made with Godot Engine %s" % [Credits.PUBLISHER, Engine.get_version_info().string],
		"",
		CyberTheme.tint("DEV SUPPORT", CyberTheme.AMBER),
		"Found a bug, or have an idea? The dev support form goes straight to the developer:",
		"[url]%s[/url]" % DEV_SUPPORT_URL,
		"",
		CyberTheme.tint("DATA AND SOUND", CyberTheme.AMBER),
		"\n".join(PackedStringArray(Array(Credits.DATA_CREDITS).map(func(l: String) -> String: return "• " + l.replace("[", "[lb]")))),
	])


## What is saved where.
static func save_text(file_path: String) -> String:
	var lines := PackedStringArray()
	var exists := FileAccess.file_exists(file_path)
	lines.append(CyberTheme.tint("PROFILE", CyberTheme.AMBER))
	lines.append("File        %s" % ProjectSettings.globalize_path(file_path))
	if exists:
		var f := FileAccess.open(file_path, FileAccess.READ)
		var size := f.get_length() if f != null else 0
		var bias := int(Time.get_time_zone_from_system().get("bias", 0))
		var when := int(FileAccess.get_modified_time(file_path)) + bias * 60
		lines.append("Size        %.1f kB · format version %d" % [size / 1024.0, PlayerProfile.SCHEMA_VERSION])
		lines.append("Last saved  %s" % Time.get_datetime_string_from_unix_time(when, true))
	else:
		lines.append("Not saved yet.")
	lines.append("Backup      %s" % ("the save before the last one is kept as %s" % (file_path + PlayerProfile.BACKUP_SUFFIX).get_file()
		if FileAccess.file_exists(file_path + PlayerProfile.BACKUP_SUFFIX) else "none yet"))
	var dir := PlayerProfile.backup_dir(file_path)
	var copies := DirAccess.get_files_at(dir).size() if DirAccess.dir_exists_absolute(dir) else 0
	lines.append("Your copies %d in %s (Back up now adds one)" % [copies, ProjectSettings.globalize_path(dir)])
	lines.append("")
	lines.append(CyberTheme.tint("ALSO SAVED", CyberTheme.AMBER))
	lines.append("Designs     %s" % ProjectSettings.globalize_path(BlueprintIO.USER_DIR))
	lines.append("Settings    %s (window, UI scale, graphics, volumes, key bindings)" % ProjectSettings.globalize_path(DisplaySettings.SAVE_PATH))
	lines.append("")
	lines.append(CyberTheme.tint("The game saves on its own: after every sortie and every change at the station.", CyberTheme.TEXT_DIM))
	return "[code]%s[/code]" % "\n".join(lines).replace("[code]", "")


## Career, fleet and money, from the profile.
static func stats_text(p: PlayerProfile) -> String:
	if p == null:
		return "No profile loaded."
	var sorties := 0
	var salvaged := 0
	var crew := 0
	for v: ShipInstance in p.vessels:
		sorties += v.sorties
		salvaged += v.salvaged
		crew += v.crew.size()
	var rows := [
		["CAREER", ""],
		["Missions completed", str(p.missions_completed)],
		["Sorties flown (ships you have)", str(sorties)],
		["Wrecks salvaged", str(salvaged)],
		["Loot crates opened", str(p.total_pulls)],
		["Ships lost", str(p.vessels_lost)],
		["Artifacts surveyed", str(p.codex.size())],
		["Locations charted", str(p.known_locations.size())],
		["FLEET AND CREW", ""],
		["Ships in the hangar", str(p.vessels.size())],
		["Crew aboard your ships", str(crew)],
		["Resting crew at the station", str(p.resting.size())],
		["MONEY", ""],
		["Credits", str(p.credits)],
		["Spare parts banked", str(p.spare_parts)],
		["Bank deposit", "%d cr" % p.bank_deposit],
		["Owed", "%d cr" % p.debt()],
	]
	var out := PackedStringArray(["[table=2]"])
	for r: Array in rows:
		if r[1] == "":
			out.append("[cell][color=%s]%s[/color][/cell][cell] [/cell]" % [CyberTheme.html(CyberTheme.AMBER), r[0]])
		else:
			out.append("[cell]%s     [/cell][cell][color=%s]%s[/color][/cell]" % [r[0], CyberTheme.html(CyberTheme.CYAN), r[1]])
	out.append("[/table]")
	if not p.vessels.is_empty():
		out.append("")
		out.append(CyberTheme.tint("SHIPS", CyberTheme.AMBER))
		for v: ShipInstance in p.vessels:
			out.append("• %s — %d sortie%s, %d salvaged, %d crew" % [v.name.replace("[", "[lb]"), v.sorties, "" if v.sorties == 1 else "s", v.salvaged, v.crew.size()])
	return "\n".join(out)


## CHANGELOG.md as BBCode: versions in teal, sections in gold, bullets,
## bold and code; soft-wrapped lines joined.
static func changelog_bbcode(md: String) -> String:
	if md == "":
		return "The changelog isn't included in this build."
	var out := PackedStringArray()
	var para := ""
	for raw: String in md.split("\n"):
		var line := raw.strip_edges(false, true)
		var starts_block := line == "" or line.begins_with("#") or line.begins_with("- ") or line.begins_with("|")
		if not starts_block and para != "":
			para += " " + line.strip_edges()
			continue
		if para != "":
			out.append(_inline(para))
			para = ""
		if line.begins_with("## "):
			out.append("")
			out.append("[font_size=%d][b][color=%s]%s[/color][/b][/font_size]" % [CyberTheme.SIZE_TITLE + 3, CyberTheme.html(CyberTheme.CYAN), _inline(line.substr(3))])
		elif line.begins_with("### "):
			out.append("[b][color=%s]%s[/color][/b]" % [CyberTheme.html(CyberTheme.AMBER), _inline(line.substr(4))])
		elif line.begins_with("#### "):
			out.append("[color=%s]%s[/color]" % [CyberTheme.html(CyberTheme.TEXT_DIM), _inline(line.substr(5))])
		elif line.begins_with("# "):
			continue
		elif line.begins_with("- "):
			para = "  • " + line.substr(2)
		elif line == "":
			out.append("")
		else:
			para = line
	if para != "":
		out.append(_inline(para))
	return "\n".join(out).strip_edges()


## Escape BBCode, then **bold**, `code` and [text](link) → text.
static func _inline(text: String) -> String:
	var s := text
	var links := RegEx.create_from_string("\\[([^\\]]+)\\]\\([^)]+\\)")
	s = links.sub(s, "$1", true)
	s = s.replace("[", "[lb]")
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	s = bold.sub(s, "[b]$1[/b]", true)
	var code := RegEx.create_from_string("`([^`]+)`")
	s = code.sub(s, "[color=%s]$1[/color]" % CyberTheme.html(CyberTheme.CYAN), true)
	return s
