class_name Shipyard
extends Control
## Ship designer (spec §6 "Editor interface"). Wires the palette, deck editor,
## orthographic views, 3D preview, stats and validation panels to one
## ShipEditor. All edits go through ShipEditor; this script only translates
## UI intent into edits and refreshes the views.

enum Tool { SELECT, PLACE, HATCH }

const FLIGHT_SCENE := "res://scenes/main/main.tscn"
const COLOR_ERROR := Color(1.0, 0.45, 0.4)
const COLOR_WARNING := Color(0.96, 0.78, 0.26)

@onready var name_edit: LineEdit = %NameEdit
@onready var template_list: OptionButton = %TemplateList
@onready var design_list: OptionButton = %DesignList
@onready var status_label: Label = %Status
@onready var launch_button: Button = %Launch
@onready var select_button: Button = %SelectTool
@onready var hatch_button: Button = %HatchTool
@onready var palette: TabContainer = %Palette
@onready var hull_list: ItemList = %Hull
@onready var room_list: ItemList = %Rooms
@onready var equipment_list: ItemList = %Equipment
@onready var info_label: Label = %InfoLabel
@onready var deck_label: Label = %DeckLabel
@onready var hint_label: Label = %Hint
@onready var deck_editor: DeckEditor = %DeckEditor
@onready var side_view: OrthoView = %SideView
@onready var front_view: OrthoView = %FrontView
@onready var preview: ShipPreview3D = %Preview
@onready var stats_label: Label = %StatsLabel
@onready var issue_text: RichTextLabel = %IssueText

var editor: ShipEditor
var tool: Tool = Tool.SELECT
## PLACE tool: which catalog table ("hull", "room", "equipment") and id.
var place_kind: String = ""
var place_def: StringName = &""
var place_rotation: int = 0
var selected_id: String = ""
var _hover_cell := Vector3i.ZERO
var _hover_face: StringName = &""


func _ready() -> void:
	var catalog := ConstructionCatalog.default_catalog()
	var start: ShipBlueprint = Main.launch_blueprint.duplicate_blueprint() if Main.launch_blueprint != null else _load_or_null(BlueprintIO.DEFAULT_TEMPLATE)
	editor = ShipEditor.new(start, catalog)
	editor.changed.connect(_refresh)
	for v in [deck_editor, side_view, front_view]:
		v.editor = editor
	_fill_palette(hull_list, catalog.hull)
	_fill_palette(room_list, catalog.rooms)
	_fill_palette(equipment_list, catalog.equipment)
	for list in [hull_list, room_list, equipment_list]:
		list.item_selected.connect(_on_palette_selected.bind(list))
	select_button.pressed.connect(set_tool.bind(Tool.SELECT))
	hatch_button.pressed.connect(set_tool.bind(Tool.HATCH))
	%DeckUp.pressed.connect(change_deck.bind(1))
	%DeckDown.pressed.connect(change_deck.bind(-1))
	%LoadTemplate.pressed.connect(func() -> void: load_design(template_list.get_item_metadata(template_list.selected)))
	%LoadDesign.pressed.connect(_on_load_design_pressed)
	%Save.pressed.connect(save_design)
	%Undo.pressed.connect(undo)
	%Redo.pressed.connect(redo)
	launch_button.pressed.connect(launch)
	name_edit.text_changed.connect(func(t: String) -> void: editor.blueprint.name = t)
	deck_editor.cell_pressed.connect(apply_at)
	deck_editor.room_dragged.connect(_on_room_dragged)
	deck_editor.hover_changed.connect(_on_hover)
	issue_text.meta_clicked.connect(_on_issue_clicked)
	_fill_file_list(template_list, BlueprintIO.list_templates())
	_fill_file_list(design_list, BlueprintIO.list_user())
	deck_editor.deck = 1
	set_tool(Tool.SELECT)
	_refresh()
	_set_status("Loaded %s" % editor.blueprint.name)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	var key := k.keycode
	if k.ctrl_pressed or k.meta_pressed:
		match key:
			KEY_Z:
				redo() if k.shift_pressed else undo()
			KEY_Y:
				redo()
			KEY_S:
				save_design()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_PAGEUP:
			change_deck(1)
		KEY_PAGEDOWN:
			change_deck(-1)
		KEY_S:
			set_tool(Tool.SELECT)
		KEY_H:
			set_tool(Tool.HATCH)
		KEY_R:
			rotate_current()
		KEY_DELETE, KEY_BACKSPACE:
			if selected_id != "":
				editor.remove(selected_id)
				selected_id = ""
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if selected_id != "":
				# Screen directions: nose right (−z), starboard down (+x).
				var d := {KEY_UP: Vector3i(-1, 0, 0), KEY_DOWN: Vector3i(1, 0, 0),
					KEY_LEFT: Vector3i(0, 0, 1), KEY_RIGHT: Vector3i(0, 0, -1)}
				editor.move(selected_id, d[key])
		KEY_ESCAPE:
			set_tool(Tool.SELECT)
		_:
			return
	get_viewport().set_input_as_handled()


# --- Tools ---------------------------------------------------------------------

func set_tool(t: Tool) -> void:
	tool = t
	select_button.button_pressed = t == Tool.SELECT
	hatch_button.button_pressed = t == Tool.HATCH
	if t != Tool.PLACE:
		for list in [hull_list, room_list, equipment_list]:
			list.deselect_all()
		place_kind = ""
		place_def = &""
		info_label.text = {
			Tool.SELECT: "SELECT — click a part to select it. Arrow keys move it (a module carries its rooms and equipment), R turns a module in place, Delete removes. Right-click removes anything. Ctrl+Z / Ctrl+Y undo / redo.",
			Tool.HATCH: "HATCH — click near an edge between two rooms to add/remove a door; click a cell's centre for a ladder to the deck above.",
		}[t]
	deck_editor.drag_rooms = t == Tool.PLACE and place_kind == "room"
	_update_ghost()


## Choose a palette item to place: kind is "hull", "room" or "equipment".
func select_palette(kind: String, def_id: StringName) -> void:
	tool = Tool.PLACE
	select_button.button_pressed = false
	hatch_button.button_pressed = false
	place_kind = kind
	place_def = def_id
	deck_editor.drag_rooms = kind == "room"
	info_label.text = _describe(kind, def_id)
	_update_ghost()


func change_deck(delta: int) -> void:
	var b := editor.grid.cell_bounds()
	deck_editor.deck = clampi(deck_editor.deck + delta, int(b.position.y) - 1, int(b.end.y))
	_refresh_views()


func rotate_current() -> void:
	if tool == Tool.PLACE and (place_kind == "hull" or place_kind == "equipment"):
		place_rotation = (place_rotation + 1) % 4
		_update_ghost()
	elif selected_id != "":
		editor.rotate_module(selected_id)


func undo() -> void:
	if editor.undo():
		_set_status("Undone")
	else:
		_set_status("Nothing to undo")


func redo() -> void:
	if editor.redo():
		_set_status("Redone")
	else:
		_set_status("Nothing to redo")


## Apply the current tool at a cell (deck editor click, or tests).
func apply_at(cell: Vector3i, face: StringName, button: MouseButton = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		var id := editor.item_at(cell, face)
		if id != "":
			editor.remove(id)
			_set_status("Removed %s" % id)
			if id == selected_id:
				selected_id = ""
		return
	match tool:
		Tool.SELECT:
			selected_id = editor.item_at(cell, face)
			_refresh_views()
		Tool.HATCH:
			var other := DeckEditor.across(cell, face)
			var added := editor.toggle_hatch(cell, other)
			_set_status("%s hatch %s ↔ %s" % ["Added" if added else "Removed", cell, other])
		Tool.PLACE:
			match place_kind:
				"hull":
					selected_id = editor.place_module(place_def, cell, place_rotation)
				"room":
					selected_id = editor.place_room(place_def, cell.y, Rect2i(cell.x, cell.z, 1, 1))
				"equipment":
					selected_id = editor.place_equipment(place_def, cell, face, place_rotation)
			_set_status("Placed %s" % selected_id)


func _on_room_dragged(deck: int, rect: Rect2i) -> void:
	if tool == Tool.PLACE and place_kind == "room":
		selected_id = editor.place_room(place_def, deck, rect)
		_set_status("Placed %s (%d×%d)" % [selected_id, rect.size.x, rect.size.y])


# --- Files and launch -------------------------------------------------------------

func save_design() -> String:
	var path := BlueprintIO.user_path_for(editor.blueprint.name)
	var err := BlueprintIO.save(editor.blueprint, path)
	if err != OK:
		_set_status("Save failed (%s)" % error_string(err), true)
		return ""
	_fill_file_list(design_list, BlueprintIO.list_user())
	_set_status("Saved %s" % path)
	return path


func load_design(path: String) -> bool:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(path, errors)
	if bp == null:
		_set_status("Could not load %s: %s" % [path.get_file(), "; ".join(errors)], true)
		return false
	selected_id = ""
	editor.set_blueprint(bp)
	_set_status("Loaded %s%s" % [bp.name, "" if errors.is_empty() else " (with problems: %s)" % "; ".join(errors)], not errors.is_empty())
	return true


## Fly the current design. Refused while the design has errors.
func launch() -> bool:
	var errors := editor.report.errors()
	if not errors.is_empty():
		_set_status("Fix %d error%s before launch" % [errors.size(), "" if errors.size() == 1 else "s"], true)
		return false
	Main.launch_blueprint = editor.blueprint.duplicate_blueprint()
	get_tree().change_scene_to_file(FLIGHT_SCENE)
	return true


func _on_load_design_pressed() -> void:
	if design_list.item_count > 0 and design_list.selected >= 0:
		load_design(design_list.get_item_metadata(design_list.selected))


# --- Refresh ------------------------------------------------------------------

func _refresh() -> void:
	if name_edit.text != editor.blueprint.name:
		name_edit.text = editor.blueprint.name
	_refresh_stats()
	_refresh_issues()
	preview.show_design(editor)
	_update_ghost()
	_refresh_views()


func _refresh_views() -> void:
	deck_label.text = "DECK %d" % deck_editor.deck
	for v in [deck_editor, side_view, front_view]:
		v.deck = deck_editor.deck
		v.queue_redraw()
	deck_editor.selection_cells = editor.cells_of(selected_id) if selected_id != "" else ([] as Array[Vector3i])


func _refresh_stats() -> void:
	var s := editor.stats
	if s.mass_kg <= 0.0:
		stats_label.text = "No hull."
		return
	var cfg := s.to_ship_config(editor.blueprint.name)
	var g := 9.80665
	stats_label.text = "\n".join([
		"MASS       %.1f t dry · %.1f t wet" % [s.mass_kg / 1000.0, s.wet_mass_kg() / 1000.0],
		"CoM        x %.1f  y %.1f  z %.1f m" % [s.center_of_mass_m.x, s.center_of_mass_m.y, s.center_of_mass_m.z],
		"MAIN       %.2f MN  %.2f m/s² (%.2f g) wet" % [s.thrust_forward_n / 1e6, s.thrust_forward_n / s.wet_mass_kg(), s.thrust_forward_n / s.wet_mass_kg() / g],
		"RCS        %.0f kN  %.2f m/s²  (%d blocks)" % [s.thrust_rcs_n / 1000.0, s.thrust_rcs_n / s.wet_mass_kg(), s.rcs_count],
		"PROPELLANT %.0f t  Δv %.0f m/s  (Isp %.0f / %.0f s)" % [s.propellant_capacity_kg / 1000.0, s.delta_v_m_s(), s.main_isp_s, s.rcs_isp_s],
		"TURN RATE  P %.0f  Y %.0f  R %.0f °/s" % [rad_to_deg(cfg.assist_max_rate_rad_s.x), rad_to_deg(cfg.assist_max_rate_rad_s.y), rad_to_deg(cfg.assist_max_rate_rad_s.z)],
		"POWER      %.0f / %.0f kW" % [s.power_draw_kw, s.power_generation_kw],
		"HEAT       %.0f / %.0f kW rejected" % [s.heat_generation_kw, s.heat_rejection_kw],
		"CREW       %d berths" % s.crew_capacity,
		"MAGAZINE   %d rounds" % s.rounds_capacity,
		"CARGO      %.0f m³" % s.cargo_m3,
		"HULL       %.0f × %.0f × %.0f m" % [s.hull_bounds_m.size.x, s.hull_bounds_m.size.y, s.hull_bounds_m.size.z],
	])


func _refresh_issues() -> void:
	var report := editor.report
	var lines := PackedStringArray()
	if report.issues.is_empty():
		lines.append("[color=#80ff99]✔ No issues — ready to launch[/color]")
	for issue in report.issues:
		var err := issue.severity == ShipValidator.Severity.ERROR
		var text := ("✖ " if err else "▲ ") + issue.message.replace("[", "(").replace("]", ")")
		if issue.subject != "":
			text = "[url=%s]%s[/url]" % [issue.subject, text]
		lines.append("[color=#%s]%s[/color]" % [(COLOR_ERROR if err else COLOR_WARNING).to_html(false), text])
	issue_text.text = "

".join(lines)
	var n_err := report.errors().size()
	launch_button.disabled = n_err > 0
	launch_button.tooltip_text = "Fix %d error(s) first" % n_err if n_err > 0 else "Fly this design"
	deck_editor.issue_cells = []


## Clicking an issue highlights the part it names and jumps to its deck.
func _on_issue_clicked(meta: Variant) -> void:
	var subject := str(meta)
	deck_editor.issue_cells = editor.cells_of(subject)
	if not deck_editor.issue_cells.is_empty():
		deck_editor.deck = deck_editor.issue_cells[0].y
	_refresh_views()


func _on_hover(cell: Vector3i, face: StringName, _shift: bool) -> void:
	_hover_cell = cell
	_hover_face = face
	_update_ghost()


## Placement ghost and hint: green if placing here adds no new errors.
func _update_ghost() -> void:
	deck_editor.ghost_cells = []
	deck_editor.ghost_face = &""
	var hint := ""
	var cell := _hover_cell
	if tool == Tool.PLACE and place_def != &"":
		var edit: Callable
		match place_kind:
			"hull":
				var def: HullModuleDefinition = editor.catalog.hull[place_def]
				var size := ShipGrid.rotated_size(def.size_cells, place_rotation)
				for x in size.x:
					for z in size.z:
						deck_editor.ghost_cells.append(cell + Vector3i(x, 0, z))
				edit = func(bp: ShipBlueprint) -> void: bp.add_module(place_def, cell, place_rotation)
				hint = "%s — rotation %d° [R]" % [def.display_name, place_rotation * 90]
			"room":
				deck_editor.ghost_cells.append(cell)
				edit = func(bp: ShipBlueprint) -> void: bp.add_room(place_def, cell.y, Rect2i(cell.x, cell.z, 1, 1))
				hint = "%s — drag to size the room" % editor.catalog.rooms[place_def].display_name
			"equipment":
				var def: EquipmentDefinition = editor.catalog.equipment[place_def]
				if def.is_external():
					deck_editor.ghost_cells.append(cell)
					deck_editor.ghost_face = _hover_face
					hint = "%s — %s face (edges: fore/aft/port/starboard, centre: dorsal, Shift: ventral)" % [def.display_name, _hover_face]
				else:
					var fp := def.footprint_cells
					if place_rotation % 2 == 1:
						fp = Vector2i(fp.y, fp.x)
					for x in fp.x:
						for z in fp.y:
							deck_editor.ghost_cells.append(cell + Vector3i(x, 0, z))
					hint = "%s — %d×%d [R rotates]" % [def.display_name, fp.x, fp.y]
				var face := _hover_face if def.is_external() else &""
				var rot := 0 if def.is_external() else place_rotation
				edit = func(bp: ShipBlueprint) -> void: bp.add_equipment(place_def, cell, face, rot)
		var new_errors := editor.preview_new_errors(edit)
		deck_editor.ghost_ok = new_errors.is_empty()
		if not new_errors.is_empty():
			hint += "   ✖ " + new_errors[0].message
	elif tool == Tool.HATCH:
		hint = "Hatch: %s ↔ %s" % [cell, DeckEditor.across(cell, _hover_face)]
	else:
		var id := editor.item_at(cell, _hover_face)
		hint = "%s at %s" % [_name_of(id), cell] if id != "" else "%s" % cell
	hint_label.text = hint
	deck_editor.queue_redraw()


# --- Helpers ------------------------------------------------------------------

func _on_palette_selected(index: int, list: ItemList) -> void:
	var kind: String = {hull_list: "hull", room_list: "room", equipment_list: "equipment"}[list]
	select_palette(kind, list.get_item_metadata(index))


func _fill_palette(list: ItemList, table: Dictionary) -> void:
	list.clear()
	for id in ConstructionCatalog.sorted_ids(table):
		var i := list.add_item(table[id].display_name)
		list.set_item_metadata(i, id)
		list.set_item_custom_fg_color(i, (table[id].color as Color).lightened(0.2))


func _fill_file_list(button: OptionButton, paths: PackedStringArray) -> void:
	button.clear()
	for p in paths:
		button.add_item(p.get_file().get_basename())
		button.set_item_metadata(button.item_count - 1, p)
	button.disabled = paths.is_empty()


func _describe(kind: String, def_id: StringName) -> String:
	match kind:
		"hull":
			var d: HullModuleDefinition = editor.catalog.hull[def_id]
			var con := PackedStringArray()
			for face in d.connectors:
				con.append("%s: %s" % [face, d.connectors[face]])
			return "%s\n%d×%d×%d cells, %d decks, %.0f t, armour %.0f mm\n%s\nConnectors — %s\nClick to place (base on this deck). R rotates." % [
				d.display_name, d.size_cells.x, d.size_cells.z, d.size_cells.y, d.size_cells.y, d.structure_mass_kg / 1000.0,
				d.armor_mm, "Pressurised" if d.interior else "Unpressurised (no rooms)", ", ".join(con)]
		"room":
			var d: RoomDefinition = editor.catalog.rooms[def_id]
			return "%s (role: %s)\nPer cell: %.1f t, %+.0f kW%s%s%s\nDrag on the deck to place." % [
				d.display_name, d.role, d.mass_per_cell_kg / 1000.0, d.power_kw_per_cell,
				", %d berths" % d.crew_capacity_per_cell if d.crew_capacity_per_cell > 0 else "",
				", %d rounds" % d.rounds_per_cell if d.rounds_per_cell > 0 else "",
				", %.0f m³ cargo" % d.cargo_m3_per_cell if d.cargo_m3_per_cell > 0 else ""]
		_:
			var d: EquipmentDefinition = editor.catalog.equipment[def_id]
			var where := "Internal %d×%d, rooms: %s" % [d.footprint_cells.x, d.footprint_cells.y,
				", ".join(d.allowed_room_roles.map(func(r: StringName) -> String: return String(r)))] if not d.is_external() \
				else "External, faces: %s" % ", ".join(d.allowed_faces.map(func(f: StringName) -> String: return String(f)))
			var extra := PackedStringArray()
			if d.thrust_n > 0.0:
				extra.append("thrust %.0f kN" % (d.thrust_n / 1000.0))
			if d.heat_rejection_kw > 0.0:
				extra.append("rejects %.0f kW" % d.heat_rejection_kw)
			if d.heat_kw > 0.0:
				extra.append("heat %.0f kW" % d.heat_kw)
			return "%s\n%s\n%.1f t, %+.0f kW%s" % [d.display_name, where, d.mass_kg / 1000.0, d.power_kw,
				(", " + ", ".join(extra)) if not extra.is_empty() else ""]


func _name_of(id: String) -> String:
	var item: Variant = editor.blueprint.find(id)
	if item == null:
		return id
	for table in [editor.catalog.hull, editor.catalog.rooms, editor.catalog.equipment]:
		if table.has(item.def_id if "def_id" in item else &""):
			return "%s %s" % [table[item.def_id].display_name, id]
	return "Hatch %s" % id


func _set_status(text: String, is_error: bool = false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", COLOR_ERROR if is_error else Color(0.6, 1.0, 0.72))
	if is_error:
		GameLog.warn("shipyard", text)
	else:
		GameLog.info("shipyard", text)


static func _load_or_null(path: String) -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(path, errors)
