class_name Shipyard
extends Control
## Ship designer (spec §6 "Editor interface"). Wires the palette, deck editor,
## orthographic views, 3D preview, stats and validation panels to one
## ShipEditor. All edits go through ShipEditor; this script only translates
## UI intent into edits and refreshes the views.

enum Tool { SELECT, PLACE, HATCH }

const FLIGHT_SCENE := "res://scenes/main/main.tscn"
const COLOR_ERROR := CyberTheme.RED
const COLOR_WARNING := CyberTheme.AMBER
## Palette categories (the part kinds the catalog supports).
const CATEGORIES := ["All", "Hull", "Armour", "Interior", "Propulsion", "Power & thermal", "Weapons", "Sensors", "Utility", "Logistics"]
## Armour palette entries: id -> [mm (0 = remove), name, description].
const ARMOR_ENTRIES := {
	&"plate_40": [ShipBlueprint.PLATE_THIN_MM, "Thin armour plate (40 mm)",
		"Thin armour plate — 40 mm on top of the hull skin\nMASS %.2f t per face (more on a slope) · COST %d spare parts\nDrag across cells on this deck to plate their exposed faces (filter below). Sloped wedge faces count their full angle: a 45° slope is %.0f%% thicker against a level shot."],
	&"plate_80": [ShipBlueprint.PLATE_THICK_MM, "Thick armour plate (80 mm)",
		"Thick armour plate — 80 mm on top of the hull skin\nMASS %.2f t per face (more on a slope) · COST %d spare parts\nDrag across cells on this deck to plate their exposed faces (filter below). Sloped wedge faces count their full angle: a 45° slope is %.0f%% thicker against a level shot."],
	&"plate_remove": [0, "Remove armour plates", "Remove armour plates\nDrag across cells on this deck to strip their plates (filter below)."],
}
## Power bus palette entries: id -> [lay (true) / remove, name, description].
const BUS_ENTRIES := {
	&"bus_lay": [true, "Power conduit (bus)",
		"Power conduit — routes power from reactors through a distribution unit to systems and rooms\nMASS %.1f t per cell · COST 1 spare part per %d cells\nDrag across hull cells on this deck. Conduits join face to face and between decks (▲▼). A system or room is powered when one of its cells is on a network with a reactor and a working distribution unit. Hits cut conduits: run redundant paths.\nWithout any conduit the ship uses automatic distribution through its hull."],
	&"bus_remove": [false, "Remove power conduit", "Remove power conduit\nDrag across cells on this deck to pull out their conduit."],
}

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
## Spare parts, found parts and the hangar vessel (Main.get_profile()).
var profile: PlayerProfile
var tool: Tool = Tool.SELECT
## PLACE tool: which catalog table ("hull", "room", "equipment") and id.
var place_kind: String = ""
var place_def: StringName = &""
var place_rotation: int = 0
## Hull placement upside down (wedges slope down) — F.
var place_flip: bool = false
## Which faces an armour stroke covers.
var armor_faces: OptionButton
var selected_id: String = ""
var _hover_cell := Vector3i.ZERO
var _hover_face: StringName = &""
var _hangar_label: RichTextLabel
## HANGAR → LOOT TABLES: every possible crate drop and its odds.
var loot_tables_label: RichTextLabel
## The hangar's vessels (pick the one to fly and edit) and "build new".
var vessel_picker: OptionButton
## Modules selected together (Shift-click, Ctrl+A); arrows move them as one.
var group_ids: Array[String] = []
var _convert_button: Button
## Designing a new hull: Launch commissions it instead of refitting.
var building_new: bool = false
var _cargo_label: RichTextLabel
var _history_label: RichTextLabel
var _priority: OptionButton
var _repair_button: Button
var _bank_button: Button
var _buy_button: Button
var debrief: DebriefPanel
## Searchable, categorised palette (replaces the three tabs).
var palette_list: ItemList
var palette_search: LineEdit
var palette_category: OptionButton
var _figures: Dictionary = {}  # name -> value Label
var _expanded_view := ""
## The main editing view: "top" (deck editor) or "iso" (isometric 3D).
var main_view := "top"
var iso_view: ShipPreview3D
var _iso_turns: Array[Button] = []
var _view_toggle: Button


func _ready() -> void:
	InputBindings.apply_saved()
	theme = CyberTheme.build_theme()
	var catalog := ConstructionCatalog.default_catalog()
	profile = Main.get_profile()
	profile.ensure_vessel(_load_or_null(BlueprintIO.DEFAULT_TEMPLATE))
	var start: ShipBlueprint = (Main.launch_blueprint if Main.launch_blueprint != null else profile.vessel.blueprint).duplicate_blueprint()
	editor = ShipEditor.new(start, catalog)
	editor.profile = profile
	editor.revalidate()
	editor.changed.connect(_refresh)
	_build_palette()
	_build_key_figures()
	_build_view_bar()
	_build_hangar_panel()
	CyberTheme.style_button(launch_button, CyberTheme.CYAN, true)
	launch_button.custom_minimum_size = Vector2(200, 34)
	launch_button.clip_text = true
	debrief = DebriefPanel.new()
	debrief.name = "Debrief"
	add_child(debrief)
	debrief.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	if Main.debrief_pending and not profile.last_debrief.is_empty():
		Main.debrief_pending = false
		debrief.show_debrief(profile.last_debrief, "Bank your cargo before the next sortie: what's in the hold is lost with the ship.")
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
	iso_view = ShipPreview3D.new()
	iso_view.name = "IsoView"
	iso_view.isometric = true
	iso_view.editable = true
	iso_view.visible = false
	iso_view.size_flags_horizontal = deck_editor.size_flags_horizontal
	iso_view.size_flags_vertical = deck_editor.size_flags_vertical
	iso_view.custom_minimum_size = deck_editor.custom_minimum_size
	deck_editor.get_parent().add_child(iso_view)
	deck_editor.get_parent().move_child(iso_view, deck_editor.get_index() + 1)
	iso_view.cell_pressed.connect(apply_at)
	iso_view.room_dragged.connect(_on_room_dragged)
	iso_view.hover_changed.connect(_on_hover)
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
			KEY_A:
				select_all_hull()
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
		KEY_SLASH:
			palette_search.grab_focus()
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
		KEY_F:
			flip_current()
		KEY_DELETE, KEY_BACKSPACE:
			if selected_id != "":
				editor.remove(selected_id)
				selected_id = ""
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			if selected_id != "" or group_ids.size() > 1:
				# Screen directions: nose right (−z), starboard down (+x).
				var d := {KEY_UP: Vector3i(-1, 0, 0), KEY_DOWN: Vector3i(1, 0, 0),
					KEY_LEFT: Vector3i(0, 0, 1), KEY_RIGHT: Vector3i(0, 0, -1)}
				if group_ids.size() > 1:
					editor.move_group(group_ids, d[key])
				else:
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
		for list in [hull_list, room_list, equipment_list, palette_list]:
			if list != null:
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
	deck_editor.drag_rooms = kind == "room" or kind == "armor" or kind == "bus"
	if iso_view != null:
		iso_view.drag_rooms = deck_editor.drag_rooms
	if armor_faces != null:
		armor_faces.visible = kind == "armor"
	if kind == "bus":
		var entry: Array = BUS_ENTRIES[def_id]
		info_label.text = entry[2] % [ShipStats.BUS_KG_PER_CELL / 1000.0, ServiceYard.BUS_CELLS_PER_PART] if entry[0] else entry[2]
	elif kind == "armor":
		var entry: Array = ARMOR_ENTRIES[def_id]
		info_label.text = entry[2] if entry[0] == 0 else entry[2] % [ShipStats.plate_mass(entry[0]) / 1000.0,
			ServiceYard.plate_cost(entry[0]), (sqrt(2.0) - 1.0) * 100.0]
	else:
		info_label.text = _describe(kind, def_id)
	_update_ghost()


func change_deck(delta: int) -> void:
	var b := editor.grid.cell_bounds()
	deck_editor.deck = clampi(deck_editor.deck + delta, int(b.position.y) - 1, int(b.end.y))
	_refresh_views()


## Ctrl+A: the whole hull as one group (everything moves with it).
func select_all_hull() -> void:
	set_tool(Tool.SELECT)
	group_ids.clear()
	for m in editor.blueprint.modules:
		group_ids.append(m.id)
	selected_id = group_ids[0] if not group_ids.is_empty() else ""
	_set_status("Whole hull selected (%d modules) — arrow keys move the ship" % group_ids.size())
	_refresh_views()


## Rebuild the design's old large sections from blocks. On the vessel's own
## design (nothing else changed) it is free: the yard re-plates the hull.
func convert_to_blocks() -> Dictionary:
	if not editor.has_legacy():
		_set_status("No old sections to convert")
		return {}
	var same_as_vessel := not building_new and JSON.stringify(editor.blueprint.to_dict()) == JSON.stringify(profile.vessel.blueprint.to_dict())
	if same_as_vessel and not (profile.vessel.condition.get("modules", {}) as Dictionary).is_empty():
		_set_status("Repair the hull first: damaged sections can't be converted", true)
		return {}
	var result := editor.convert_legacy()
	if same_as_vessel:
		# The hull's parts are reused: the vessel adopts the converted design as is.
		profile.vessel.blueprint = editor.blueprint.duplicate_blueprint()
		profile.vessel.record("Hull rebuilt from blocks (%d sections)" % result.converted)
		_save_profile()
	_set_status("Converted %d section%s to blocks%s" % [result.converted, "" if result.converted == 1 else "s",
		" — kept %s (an odd length doesn't tile)" % ", ".join(result.kept) if not result.kept.is_empty() else ""])
	_refresh_hangar()
	return result
func flip_current() -> void:
	if tool == Tool.PLACE and place_kind == "hull":
		place_flip = not place_flip
		_update_ghost()
	elif selected_id != "":
		editor.flip_module(selected_id)


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
			var picked := editor.item_at(cell, face)
			var module: Variant = editor.blueprint.find(editor.item_at(cell, &""))
			if shift and module is ShipBlueprint.PlacedModule:
				# Shift-click builds a group of modules that move together.
				var mid: String = module.id
				if group_ids.is_empty() and selected_id != "" and editor.blueprint.find(selected_id) is ShipBlueprint.PlacedModule:
					group_ids.append(selected_id)
				if group_ids.has(mid):
					group_ids.erase(mid)
				else:
					group_ids.append(mid)
				selected_id = mid
				_set_status("Group: %d modules — arrow keys move them together" % group_ids.size())
			else:
				group_ids.clear()
				selected_id = picked
			_refresh_views()
		Tool.HATCH:
			var other := DeckEditor.across(cell, face)
			var added := editor.toggle_hatch(cell, other)
			_set_status("%s hatch %s ↔ %s" % ["Added" if added else "Removed", cell, other])
		Tool.PLACE:
			match place_kind:
				"hull":
					selected_id = editor.place_module(place_def, cell, place_rotation, place_flip)
				"armor":
					_paint_armor(cell.y, Rect2i(cell.x, cell.z, 1, 1))
					return
				"bus":
					_paint_bus(cell.y, Rect2i(cell.x, cell.z, 1, 1))
					return
				"room":
					selected_id = editor.place_room(place_def, cell.y, Rect2i(cell.x, cell.z, 1, 1))
				"equipment":
					selected_id = editor.place_equipment(place_def, cell, face, place_rotation)
			_set_status("Placed %s" % selected_id)


func _on_room_dragged(deck: int, rect: Rect2i) -> void:
	if tool == Tool.PLACE and place_kind == "room":
		selected_id = editor.place_room(place_def, deck, rect)
		_set_status("Placed %s (%d×%d)" % [selected_id, rect.size.x, rect.size.y])
	elif tool == Tool.PLACE and place_kind == "armor":
		_paint_armor(deck, rect)
	elif tool == Tool.PLACE and place_kind == "bus":
		_paint_bus(deck, rect)


func _paint_bus(deck: int, rect: Rect2i) -> void:
	var lay: bool = BUS_ENTRIES[place_def][0]
	var n := editor.paint_bus(deck, rect, lay)
	_set_status(("%s %d conduit cell%s" % ["Laid" if lay else "Removed", n, "" if n == 1 else "s"]) if n > 0 else "No hull cells to change there")


## Replace the bus with an automatic tree from the distribution unit.
func auto_route_bus() -> int:
	var n := editor.auto_route_bus()
	_set_status("Auto-routed the power bus: %d conduit cells" % n if n > 0 else "Nothing to route: fit a reactor and a power distribution unit first", n == 0)
	return n


func _paint_armor(deck: int, rect: Rect2i) -> void:
	var mm: int = ARMOR_ENTRIES[place_def][0]
	var faces := armor_faces.selected if armor_faces != null else 0
	var n := editor.paint_armor(deck, rect, mm, faces)
	_set_status(("%s %d plate%s" % ["Removed" if mm == 0 else "Fitted %d mm on" % mm, n, "" if n == 1 else "s"]) if n > 0 else "No exposed faces there to plate")


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


## Fly the current design. Refused while the design has errors or the refit
## (parts the hangar vessel does not have yet) cannot be paid for.
func launch() -> bool:
	var errors := editor.report.errors()
	if not errors.is_empty():
		_set_status("Fix %d error%s before launch" % [errors.size(), "" if errors.size() == 1 else "s"], true)
		return false
	if building_new:
		var why_new := profile.commission(editor.blueprint, editor.catalog)
		if why_new != "":
			_set_status(why_new + " — buy parts or bank cargo", true)
			return false
		building_new = false
		profile.designing_new = false
		_save_profile()
		Main.launch_blueprint = editor.blueprint.duplicate_blueprint()
		get_tree().change_scene_to_file(FLIGHT_SCENE)
		return true
	var why := ServiceYard.refit(profile.vessel, editor.blueprint, profile, editor.catalog)
	if why != "":
		_set_status(why + " — remove new parts, bank cargo or buy parts", true)
		return false
	var supplied := ServiceYard.resupply(profile.vessel, profile, editor.catalog)
	if supplied != "":
		GameLog.info("shipyard", supplied)
	if not profile.vessel.cargo_is_empty():
		GameLog.info("shipyard", "Launching with cargo still in the hold: %s" % profile.vessel.cargo_summary())
	_save_profile()
	Main.launch_blueprint = editor.blueprint.duplicate_blueprint()
	get_tree().change_scene_to_file(FLIGHT_SCENE)
	return true


## Repair the hangar vessel by `priority` (default: the chosen one) with the
## spare parts available. Returns parts spent.
func repair(priority: int = -1) -> int:
	var pr: int = _priority.selected if priority < 0 else priority
	var jobs := ServiceYard.plan(ServiceYard.repair_jobs(profile.vessel, editor.catalog), pr, profile.spare_parts, profile.vessel, profile)
	var spent := ServiceYard.perform(jobs, profile.vessel, profile)
	_save_profile()
	if jobs.is_empty():
		_set_status("Nothing repairable with %d spare parts" % profile.spare_parts, true)
	else:
		_set_status("%s: %d repair%s for %d spare parts" % [ServiceYard.PRIORITY_NAMES[pr], jobs.size(), "" if jobs.size() == 1 else "s", spent])
	_refresh_hangar()
	return spent


## Start designing a new hull: a single block on an empty slip. Launch
## commissions it as another vessel in the hangar (every part built new,
## plus the yard's fee); the current vessel stays in the hangar.
func start_new_ship() -> void:
	var bp := ShipBlueprint.new()
	bp.name = "New ship %d" % (profile.vessels.size() + 1)
	bp.designer = "Player"
	bp.add_module(&"hull_block", Vector3i.ZERO)
	building_new = true
	profile.designing_new = true
	selected_id = ""
	editor.set_blueprint(bp)
	deck_editor.deck = 0
	_set_status("New hull laid down: build it, then COMMISSION (parts + %d cr fee)" % PlayerProfile.NEW_HULL_FEE)
	_refresh_hangar()


## Fly and edit vessel `index` of the hangar.
func select_vessel(index: int) -> void:
	if not profile.select_vessel(index):
		return
	building_new = false
	profile.designing_new = false
	selected_id = ""
	editor.set_blueprint(profile.vessel.blueprint.duplicate_blueprint())
	_save_profile()
	_set_status("Now working on %s" % profile.vessel.name)
	_refresh_hangar()


func _fill_vessel_picker() -> void:
	if vessel_picker == null:
		return
	vessel_picker.clear()
	for i in profile.vessels.size():
		var v := profile.vessels[i]
		vessel_picker.add_item("%s · %d sortie%s%s" % [v.name, v.sorties, "" if v.sorties == 1 else "s", " · damaged" if v.is_damaged() else ""])
	if building_new:
		vessel_picker.add_item("(new hull on the slip)")
		vessel_picker.select(vessel_picker.item_count - 1)
	else:
		vessel_picker.select(profile.active_vessel)


## Testing aid: 100 free credits (saved at once).
func dev_add_credits() -> void:
	profile.dev_grant_credits(100)
	_save_profile()
	_refresh_hangar()


## Unload the cargo hold into Earth Shipyard's bank.
func bank_cargo() -> PackedStringArray:
	var banked := profile.bank_cargo(editor.catalog)
	_save_profile()
	_set_status("Banked: %s" % ", ".join(banked) if not banked.is_empty() else "The hold is empty")
	_fill_palette(hull_list, editor.catalog.hull)
	_fill_palette(room_list, editor.catalog.rooms)
	_fill_palette(equipment_list, editor.catalog.equipment)
	_fill_palette_list()
	editor.revalidate()
	return banked


func buy_spare_parts() -> bool:
	if not profile.buy_spare_parts():
		_set_status("Not enough credits (%d needed)" % PlayerProfile.PARTS_LOT_PRICE, true)
		return false
	_save_profile()
	_set_status("Bought %d spare parts for %d credits" % [PlayerProfile.PARTS_LOT, PlayerProfile.PARTS_LOT_PRICE])
	_refresh_hangar()
	return true


func _save_profile() -> void:
	var err := profile.save()
	if err != OK:
		_set_status("Could not save the profile (%s)" % error_string(err), true)


func _on_load_design_pressed() -> void:
	if design_list.item_count > 0 and design_list.selected >= 0:
		load_design(design_list.get_item_metadata(design_list.selected))


# --- Refresh ------------------------------------------------------------------

func _refresh() -> void:
	if name_edit.text != editor.blueprint.name:
		name_edit.text = editor.blueprint.name
	_refresh_stats()
	_refresh_issues()
	_refresh_hangar()
	preview.show_design(editor)
	if iso_view != null and iso_view.visible:
		iso_view.show_design(editor)
	_update_ghost()
	_refresh_views()


func _refresh_views() -> void:
	deck_label.text = "DECK %d" % deck_editor.deck
	for v in [deck_editor, side_view, front_view]:
		v.deck = deck_editor.deck
		v.queue_redraw()
	deck_editor.selection_cells = editor.cells_of(selected_id) if selected_id != "" else ([] as Array[Vector3i])
	for gid in group_ids:
		deck_editor.selection_cells.append_array(editor.cells_of(gid))
	if iso_view != null and iso_view.visible and iso_view.deck != deck_editor.deck:
		iso_view.set_deck(deck_editor.deck)


## The deck editor's ghost changed: redraw it, and mirror it in the iso view.
func _ghost_changed() -> void:
	deck_editor.queue_redraw()
	if iso_view != null and iso_view.visible:
		iso_view.ghost_cells = deck_editor.ghost_cells
		iso_view.ghost_ok = deck_editor.ghost_ok
		iso_view.refresh_ghost()


## Swap the main view between the top-down deck editor and the isometric
## 3D view (both edit the same deck with the same tools).
func set_main_view(mode: String) -> void:
	main_view = mode
	if _view_toggle != null:
		_view_toggle.text = "%s ⇄" % ("ISOMETRIC" if mode == "iso" else "TOP-DOWN")
	for b in _iso_turns:
		b.visible = mode == "iso"
	expand_view(_expanded_view)
	if mode == "iso":
		iso_view.drag_rooms = deck_editor.drag_rooms
		iso_view.deck = deck_editor.deck
		iso_view.show_design(editor)
		_ghost_changed()


func _refresh_stats() -> void:
	var s := editor.stats
	if s.mass_kg <= 0.0:
		stats_label.text = "No hull."
		return
	var cfg := s.to_ship_config(editor.blueprint.name)
	var g := 9.80665
	_set_figure("MASS", "%.0f t" % (s.wet_mass_kg() / 1000.0), CyberTheme.TEXT)
	_set_figure("ACCEL", "%.2f g" % (s.thrust_forward_n / s.wet_mass_kg() / g), CyberTheme.TEXT if s.thrust_forward_n > 0.0 else CyberTheme.AMBER)
	_set_figure("Δv", "%.0f m/s" % s.delta_v_m_s(), CyberTheme.TEXT if s.delta_v_m_s() > 500.0 else CyberTheme.AMBER)
	var power := s.power_generation_kw - s.power_draw_kw
	_set_figure("POWER", "%s %+.0f kW" % [CyberTheme.GLYPH_OK if power >= 0.0 else CyberTheme.GLYPH_DEGRADED, power], CyberTheme.CYAN if power >= 0.0 else CyberTheme.AMBER)
	var heat := s.heat_rejection_kw - s.heat_generation_kw
	_set_figure("HEAT", "%s %+.0f kW" % [CyberTheme.GLYPH_OK if heat >= 0.0 else CyberTheme.GLYPH_DEGRADED, heat], CyberTheme.CYAN if heat >= 0.0 else CyberTheme.AMBER)
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
		"MAGAZINE   %.1f t · %d rounds" % [s.magazine_kg / 1000.0, s.rounds_capacity],
		"CARGO      %.0f m³" % s.cargo_m3,
		"HULL       %.0f × %.0f × %.0f m" % [s.hull_bounds_m.size.x, s.hull_bounds_m.size.y, s.hull_bounds_m.size.z],
	])


func _refresh_issues() -> void:
	var report := editor.report
	var lines := PackedStringArray()
	var title := get_node_or_null("Margin/VBox/Body/Right/IssuesTitle") as Label
	if title != null:
		title.text = "VALIDATION   ✖ %d errors   ▲ %d warnings" % [report.errors().size(), report.warnings().size()]
		title.add_theme_color_override("font_color", COLOR_ERROR if report.has_errors() else (COLOR_WARNING if not report.issues.is_empty() else CyberTheme.CYAN))
	if report.issues.is_empty():
		lines.append(CyberTheme.tint("✔ No issues — ready to launch", CyberTheme.CYAN))
	for issue in report.issues:
		var err := issue.severity == ShipValidator.Severity.ERROR
		var text := ("✖ " if err else "▲ ") + issue.message.replace("[", "(").replace("]", ")")
		if issue.subject != "":
			text = "[url=%s]%s[/url]" % [issue.subject, text]
		lines.append("[color=#%s]%s[/color]" % [(COLOR_ERROR if err else COLOR_WARNING).to_html(false), text])
	issue_text.text = "\n\n".join(lines)
	var n_err := report.errors().size()
	launch_button.disabled = n_err > 0
	launch_button.tooltip_text = "Fix %d error(s) first" % n_err if n_err > 0 else "Fly this design"
	deck_editor.issue_cells = []


# --- Hangar and service --------------------------------------------------------

## Searchable palette: a category picker, a search box and one list.
func _build_palette() -> void:
	palette.visible = false
	var left := palette.get_parent()
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", CyberTheme.SPACE_XS)
	palette_search = LineEdit.new()
	palette_search.placeholder_text = "Search parts…  [/]"
	palette_search.clear_button_enabled = true
	palette_search.text_changed.connect(func(_t: String) -> void: _fill_palette_list())
	box.add_child(palette_search)
	palette_category = OptionButton.new()
	for c in CATEGORIES:
		palette_category.add_item(c)
	palette_category.item_selected.connect(func(_i: int) -> void: _fill_palette_list())
	box.add_child(palette_category)
	palette_list = ItemList.new()
	palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_list.item_selected.connect(func(i: int) -> void:
		var m: Array = palette_list.get_item_metadata(i)
		select_palette(m[0], m[1]))
	box.add_child(palette_list)
	armor_faces = OptionButton.new()
	for n in ["Plate every exposed face", "Sides only", "Top only", "Underside only"]:
		armor_faces.add_item(n)
	armor_faces.tooltip_text = "Which faces an armour stroke covers"
	armor_faces.visible = false
	box.add_child(armor_faces)
	var route := Button.new()
	route.text = "Auto-route power bus"
	route.tooltip_text = "Lay conduit from the distribution unit to every powered system and room (replaces the current bus)"
	CyberTheme.style_button(route, CyberTheme.AMBER)
	route.pressed.connect(func() -> void: auto_route_bus())
	box.add_child(route)
	left.add_child(box)
	left.move_child(box, palette.get_index())
	_fill_palette_list()


## Category of a part, adapted to the kinds the catalog has.
static func category_of(kind: String, def: Resource) -> String:
	match kind:
		"hull":
			return "Hull"
		"room":
			return "Logistics" if def.role in [&"cargo", &"magazine"] else "Interior"
	match (def as EquipmentDefinition).kind:
		EquipmentDefinition.Kind.MAIN_ENGINE, EquipmentDefinition.Kind.RCS:
			return "Propulsion"
		EquipmentDefinition.Kind.REACTOR, EquipmentDefinition.Kind.RADIATOR, EquipmentDefinition.Kind.POWER_DISTRIBUTION:
			return "Power & thermal"
		EquipmentDefinition.Kind.CANNON, EquipmentDefinition.Kind.POINT_DEFENCE:
			return "Weapons"
		EquipmentDefinition.Kind.SENSOR:
			return "Sensors"
		EquipmentDefinition.Kind.PROPELLANT_TANK:
			return "Logistics"
	return "Utility"


func _fill_palette_list() -> void:
	if palette_list == null:
		return
	palette_list.clear()
	var want: String = CATEGORIES[maxi(palette_category.selected, 0)]
	var query := palette_search.text.strip_edges().to_lower()
	for id: StringName in BUS_ENTRIES:
		var b_name: String = BUS_ENTRIES[id][1]
		if (want != "All" and want != "Power & thermal") or (query != "" and not (b_name.to_lower().contains(query) or "bus".contains(query) or "power".contains(query))):
			continue
		var bi := palette_list.add_item(b_name if want != "All" else "%s · Power & thermal" % b_name)
		palette_list.set_item_metadata(bi, ["bus", id])
		palette_list.set_item_custom_fg_color(bi, CyberTheme.AMBER if BUS_ENTRIES[id][0] else CyberTheme.TEXT_DIM)
	for id: StringName in ARMOR_ENTRIES:
		var a_name: String = ARMOR_ENTRIES[id][1]
		if (want != "All" and want != "Armour") or (query != "" and not (a_name.to_lower().contains(query) or "armour".contains(query))):
			continue
		var ai := palette_list.add_item(a_name if want == "Armour" else "%s · Armour" % a_name)
		palette_list.set_item_metadata(ai, ["armor", id])
		var mm: int = ARMOR_ENTRIES[id][0]
		palette_list.set_item_custom_fg_color(ai, CyberTheme.AMBER if mm >= ShipBlueprint.PLATE_THICK_MM else (CyberTheme.CYAN if mm > 0 else CyberTheme.TEXT_DIM))
	for entry in [["hull", editor.catalog.hull], ["room", editor.catalog.rooms], ["equipment", editor.catalog.equipment]]:
		for id in ConstructionCatalog.sorted_ids(entry[1]):
			var def: Resource = entry[1][id]
			if (def is HullModuleDefinition or def is EquipmentDefinition) and def.legacy:
				continue
			var cat := category_of(entry[0], def)
			if want != "All" and cat != want:
				continue
			if query != "" and not (def.display_name.to_lower().contains(query) or String(id).contains(query) or cat.to_lower().contains(query)):
				continue
			var text: String = def.display_name
			var color := (def.color as Color).lightened(0.2)
			if def.rarity != Rarity.Tier.COMMON:
				color = Rarity.color_of(def.rarity)
				if def is EquipmentDefinition:
					text += "  ×%d" % profile.owned(id)
				elif not profile.is_unlocked(def):
					text += "  (locked)"
					color = color.darkened(0.45)
			if want == "All":
				text = "%s · %s" % [text, cat]
			var i := palette_list.add_item(text)
			palette_list.set_item_metadata(i, [entry[0], id])
			palette_list.set_item_custom_fg_color(i, color)
			palette_list.set_item_tooltip(i, "%s — %s · %s" % [def.display_name, cat, Rarity.name_of(def.rarity)])


## Key figures above the detailed stats.
func _build_key_figures() -> void:
	var panel := stats_label.get_parent()
	panel.remove_child(stats_label)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	panel.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", CyberTheme.SPACE_M)
	for name in ["MASS", "ACCEL", "Δv", "POWER", "HEAT"]:
		var cell := VBoxContainer.new()
		var cap := Label.new()
		cap.theme_type_variation = &"Caption"
		cap.text = name
		var value := Label.new()
		value.add_theme_font_override("font", CyberTheme.sans())
		value.add_theme_font_size_override("font_size", 17)
		cell.add_child(cap)
		cell.add_child(value)
		grid.add_child(cell)
		_figures[name] = value
	box.add_child(grid)
	stats_label.add_theme_font_size_override("font_size", CyberTheme.SIZE_SMALL + 1)
	stats_label.add_theme_color_override("font_color", CyberTheme.TEXT_DIM.lerp(CyberTheme.TEXT, 0.5))
	box.add_child(stats_label)


func _set_figure(name: String, text: String, color: Color) -> void:
	var l: Label = _figures.get(name)
	if l != null:
		l.text = text
		l.add_theme_color_override("font_color", color)


## Expand one of the side / front / 3D views to fill the centre (the deck
## editor hides until restored).
func _build_view_bar() -> void:
	var views := side_view.get_parent()
	var center := views.get_parent()
	var bar := HBoxContainer.new()
	var cap := Label.new()
	cap.theme_type_variation = &"Caption"
	cap.text = "VIEWS"
	bar.add_child(cap)
	_view_toggle = Button.new()
	_view_toggle.text = "TOP-DOWN ⇄"
	_view_toggle.tooltip_text = "Swap the main view between top-down and isometric (both edit the current deck)"
	CyberTheme.style_button(_view_toggle, CyberTheme.CYAN, true)
	_view_toggle.pressed.connect(func() -> void: set_main_view("top" if main_view == "iso" else "iso"))
	bar.add_child(_view_toggle)
	for turn in [[-1, "⟲"], [1, "⟳"]]:
		var tb := Button.new()
		tb.text = turn[1]
		tb.tooltip_text = "Turn the isometric view"
		tb.visible = false
		var q: int = turn[0]
		tb.pressed.connect(func() -> void: iso_view.turn_iso(q))
		bar.add_child(tb)
		_iso_turns.append(tb)
	for entry in [["side", "Side"], ["front", "Front"], ["3d", "3D"], ["", "Restore"]]:
		var b := Button.new()
		b.text = entry[1]
		var which: String = entry[0]
		b.pressed.connect(func() -> void: expand_view(which))
		bar.add_child(b)
	center.add_child(bar)
	center.move_child(bar, views.get_index())


func expand_view(which: String) -> void:
	_expanded_view = which
	var views := side_view.get_parent() as Control
	deck_editor.visible = which == "" and main_view == "top"
	if iso_view != null:
		iso_view.visible = which == "" and main_view == "iso"
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL if which != "" else Control.SIZE_FILL
	side_view.visible = which in ["", "side"]
	front_view.visible = which in ["", "front"]
	preview.visible = which in ["", "3d"]
	_refresh_views()


func _build_hangar_panel() -> void:
	var right := stats_label.get_parent().get_parent().get_parent()
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", CyberTheme.SPACE_S)
	var heading := Label.new()
	heading.theme_type_variation = &"Heading"
	heading.text = "HANGAR"
	title.add_child(heading)
	vessel_picker = OptionButton.new()
	vessel_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vessel_picker.clip_text = true
	vessel_picker.fit_to_longest_item = false
	vessel_picker.custom_minimum_size = Vector2(80, 0)
	vessel_picker.tooltip_text = "The vessel to fly and refit"
	vessel_picker.item_selected.connect(func(i: int) -> void:
		if i < profile.vessels.size():
			select_vessel(i))
	title.add_child(vessel_picker)
	var new_ship := Button.new()
	new_ship.text = "New ship"
	new_ship.tooltip_text = "Lay down a new hull on an empty slip (every part built new + %d credits)" % PlayerProfile.NEW_HULL_FEE
	CyberTheme.style_button(new_ship, CyberTheme.AMBER)
	new_ship.pressed.connect(start_new_ship)
	title.add_child(new_ship)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 240)
	var box := VBoxContainer.new()
	box.name = "SERVICE"
	_hangar_label = _rich_label()
	var cargo_box := VBoxContainer.new()
	cargo_box.name = "CARGO & BANK"
	_cargo_label = _rich_label()
	var history_box := VBoxContainer.new()
	history_box.name = "HISTORY"
	_history_label = _rich_label()
	var loot_scroll := ScrollContainer.new()
	loot_scroll.name = "LOOT TABLES"
	loot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	loot_tables_label = _rich_label()
	loot_tables_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_tables_label.text = LootRoller.table_text(editor.catalog)
	loot_scroll.add_child(loot_tables_label)
	var row := HBoxContainer.new()
	_priority = OptionButton.new()
	for n in ServiceYard.PRIORITY_NAMES:
		_priority.add_item(n)
	_priority.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_priority.tooltip_text = "What to fix first when spare parts are short"
	_priority.item_selected.connect(func(_i: int) -> void: _refresh_hangar())
	_repair_button = Button.new()
	_repair_button.pressed.connect(func() -> void: repair())
	row.add_child(_priority)
	row.add_child(_repair_button)
	_convert_button = Button.new()
	_convert_button.text = "Convert to blocks"
	_convert_button.tooltip_text = "Rebuild the old large sections from blocks with armour plates (free on your own vessel's design)"
	CyberTheme.style_button(_convert_button, CyberTheme.AMBER)
	_convert_button.pressed.connect(func() -> void: convert_to_blocks())
	row.add_child(_convert_button)
	var row2 := HFlowContainer.new()
	_bank_button = Button.new()
	_bank_button.text = "Bank cargo"
	_bank_button.tooltip_text = "Unload the hold into Earth Shipyard's bank: safe from loss"
	_bank_button.pressed.connect(func() -> void: bank_cargo())
	_buy_button = Button.new()
	_buy_button.text = "Buy %d parts (%d cr)" % [PlayerProfile.PARTS_LOT, PlayerProfile.PARTS_LOT_PRICE]
	_buy_button.pressed.connect(func() -> void: buy_spare_parts())
	var debrief_button := Button.new()
	debrief_button.text = "Last debrief"
	debrief_button.pressed.connect(func() -> void: debrief.show_debrief(profile.last_debrief))
	var dev_button := Button.new()
	dev_button.text = "DEV +100 cr"
	dev_button.tooltip_text = "Testing aid: 100 free credits"
	dev_button.pressed.connect(func() -> void: dev_add_credits())
	for b in [_bank_button, _buy_button, dev_button]:
		row2.add_child(b)
	for b in [_repair_button, _bank_button, _buy_button, debrief_button]:
		CyberTheme.style_button(b)
	CyberTheme.style_button(dev_button, CyberTheme.AMBER)
	box.add_child(_hangar_label)
	box.add_child(row)
	cargo_box.add_child(_cargo_label)
	cargo_box.add_child(row2)
	history_box.add_child(_history_label)
	history_box.add_child(debrief_button)
	for b in [box, cargo_box, history_box, loot_scroll]:
		tabs.add_child(b)
	right.add_child(title)
	right.move_child(title, 1)
	right.add_child(tabs)
	right.move_child(tabs, 2)


func _rich_label() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", CyberTheme.SIZE_SMALL + 1)
	r.add_theme_font_size_override("bold_font_size", CyberTheme.SIZE_BODY)
	return r


func _refresh_hangar() -> void:
	if _hangar_label == null:
		return
	var v := profile.vessel
	var catalog := editor.catalog
	var jobs := ServiceYard.repair_jobs(v, catalog)
	var refit := ServiceYard.refit_jobs(v, editor.blueprint, catalog)
	var gold := Rarity.color_of(Rarity.Tier.LEGENDARY).to_html(false)
	var lines := PackedStringArray([
		"[b]%s[/b] · SPARE PARTS [color=#%s]%d[/color]" % [v.name, gold, profile.spare_parts],
	])
	if jobs.is_empty():
		lines.append(CyberTheme.tint("✔ Vessel in full repair", CyberTheme.CYAN))
	else:
		lines.append("DAMAGE  %d jobs · %d parts for everything" % [jobs.size(), ServiceYard.total_cost(jobs)])
		# Lost craft first: they ground the wing until replaced.
		var listed: Array = jobs.filter(func(j: ServiceYard.Job) -> bool: return j.label.begins_with("Replace lost")) 			+ jobs.filter(func(j: ServiceYard.Job) -> bool: return not j.label.begins_with("Replace lost"))
		for j in listed.slice(0, 5):
			var blocked := "" if ServiceYard.available(j, v, profile) else "  [color=#ff7766](no unit)[/color]"
			lines.append("  • %s — %d%s" % [j.label, j.cost, blocked])
		if jobs.size() > 5:
			lines.append("  … %d more" % (jobs.size() - 5))
	var supply := ServiceYard.resupply_needs(v, catalog)
	if int(supply.credits) > 0 and not building_new:
		lines.append("RESUPPLY  %.1f t propellant · %d rounds — %d cr at launch%s" % [supply.propellant_kg / 1000.0, supply.rounds, supply.credits,
			"  [color=#ff7766](credits short: partial)[/color]" if int(supply.credits) > profile.credits else ""])
	if building_new:
		var hull := profile.new_hull_cost(editor.blueprint, editor.catalog)
		lines.append(CyberTheme.tint("NEW HULL on the slip: %d spare parts + %d credits at commissioning" % [hull.x, hull.y], CyberTheme.AMBER))
	elif not refit.is_empty():
		var cost := ServiceYard.total_cost(refit)
		lines.append("REFIT   %d new part%s · %d spare parts at launch%s" % [refit.size(), "" if refit.size() == 1 else "s", cost,
			"  [color=#ff7766]short by %d[/color]" % (cost - profile.spare_parts) if cost > profile.spare_parts else ""])
	_hangar_label.text = "\n".join(lines)
	var pity := profile.pity_countdown()
	_cargo_label.text = "\n".join([
		"CREDITS [color=#%s]%d[/color] · respawn fee %d cr" % [gold, profile.credits, profile.respawn_fee(catalog)],
		"BANKED  %d spare parts" % profile.spare_parts,
		"HOLD    %.1f / %.0f m³ · %s%s" % [v.cargo_volume_m3(catalog), editor.stats.cargo_m3, CyberTheme.tint(v.cargo_summary(), CyberTheme.MAGENTA),
			CyberTheme.tint("  ▲ at risk until banked", CyberTheme.AMBER) if not v.cargo_is_empty() else ""],
		"FOUND   %s" % _found_text(),
		"LOOT    %d crates opened · Rare+ in %d · Legendary in %d" % [profile.total_pulls, pity.x, pity.y],
	])
	var history := PackedStringArray(["[b]%s[/b] · %d sorties · %d salvaged · %d lost" % [v.name, v.sorties, v.salvaged, profile.vessels_lost]])
	for line in Array(v.history).slice(-12):
		history.append("• " + str(line))
	_history_label.text = "\n".join(history)
	var refit_cost := ServiceYard.total_cost(refit)
	launch_button.text = "LAUNCH ▶" if refit.is_empty() else "LAUNCH ▶ · refit %d parts" % refit_cost
	if building_new:
		var cost := profile.new_hull_cost(editor.blueprint, editor.catalog)
		launch_button.text = "COMMISSION ▶ · %d parts + %d cr" % [cost.x, cost.y]
	_fill_vessel_picker()
	if _convert_button != null:
		_convert_button.visible = editor.has_legacy()
	var plan := ServiceYard.plan(jobs, _priority.selected, profile.spare_parts, v, profile)
	_repair_button.disabled = plan.is_empty()
	_bank_button.disabled = v.cargo_is_empty()
	_buy_button.disabled = profile.credits < PlayerProfile.PARTS_LOT_PRICE
	_repair_button.text = "Repair (%d)" % ServiceYard.total_cost(plan) if not plan.is_empty() else "Repair"


func _found_text() -> String:
	var parts := PackedStringArray()
	var catalog := editor.catalog
	for id in ConstructionCatalog.sorted_ids(catalog.equipment):
		if profile.owned(id) > 0:
			parts.append(_rarity_bb(catalog.equipment[id], "%s ×%d" % [catalog.equipment[id].display_name, profile.owned(id)]))
	for table in [catalog.hull, catalog.rooms]:
		for id in ConstructionCatalog.sorted_ids(table):
			if table[id].rarity != Rarity.Tier.COMMON and profile.is_unlocked(table[id]):
				parts.append(_rarity_bb(table[id], table[id].display_name))
	return ", ".join(parts) if not parts.is_empty() else "nothing yet — disable ships in flight and salvage them [G]"


static func _rarity_bb(def: Resource, text: String) -> String:
	return "[color=#%s]%s[/color]" % [Rarity.color_of(def.rarity).to_html(false), text]


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
				edit = func(bp: ShipBlueprint) -> void: bp.add_module(place_def, cell, place_rotation, place_flip)
				hint = "%s — rotation %d° [R]%s" % [def.display_name, place_rotation * 90,
					("  ·  slope %s [F]" % ("down" if place_flip else "up")) if def.is_wedge() else ("  ·  upside down [F]" if place_flip else "")]
			"bus":
				deck_editor.ghost_cells.append(cell)
				hint = "%s — drag across hull cells on this deck" % BUS_ENTRIES[place_def][1]
				hint_label.text = hint
				deck_editor.ghost_ok = editor.grid.is_hull(cell)
				_ghost_changed()
				return
			"armor":
				deck_editor.ghost_cells.append(cell)
				hint = "%s — drag across cells; %s" % [ARMOR_ENTRIES[place_def][1], armor_faces.get_item_text(armor_faces.selected).to_lower()]
				hint_label.text = hint
				deck_editor.ghost_ok = editor.grid.is_hull(cell)
				_ghost_changed()
				return
			"room":
				deck_editor.ghost_cells.append(cell)
				edit = func(bp: ShipBlueprint) -> void: bp.add_room(place_def, cell.y, Rect2i(cell.x, cell.z, 1, 1))
				hint = "%s — drag to size the room" % editor.catalog.rooms[place_def].display_name
			"equipment":
				var def: EquipmentDefinition = editor.catalog.equipment[place_def]
				if def.is_external():
					var step := ShipGrid.external_step(_hover_face, place_rotation)
					for k in maxi(def.length_cells, 1):
						deck_editor.ghost_cells.append(cell + step * k)
					deck_editor.ghost_face = _hover_face
					hint = "%s — %s face (near an edge: that side; middle: top or underside, whichever is open — Shift: the other)" % [def.display_name, _hover_face]
				else:
					var fp := def.footprint_cells
					if place_rotation % 2 == 1:
						fp = Vector2i(fp.y, fp.x)
					for x in fp.x:
						for z in fp.y:
							deck_editor.ghost_cells.append(cell + Vector3i(x, 0, z))
					hint = "%s — %d×%d [R rotates]" % [def.display_name, fp.x, fp.y]
				var face := _hover_face if def.is_external() else &""
				var rot := 0 if def.is_external() and def.length_cells <= 1 else place_rotation
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
	_ghost_changed()


# --- Helpers ------------------------------------------------------------------

func _on_palette_selected(index: int, list: ItemList) -> void:
	var kind: String = {hull_list: "hull", room_list: "room", equipment_list: "equipment"}[list]
	select_palette(kind, list.get_item_metadata(index))


func _fill_palette(list: ItemList, table: Dictionary) -> void:
	list.clear()
	for id in ConstructionCatalog.sorted_ids(table):
		var def: Resource = table[id]
		var text: String = def.display_name
		var color := (def.color as Color).lightened(0.2)
		if def.rarity != Rarity.Tier.COMMON:
			color = Rarity.color_of(def.rarity)
			if def is EquipmentDefinition:
				text += "  ×%d" % profile.owned(id)
			elif not profile.is_unlocked(def):
				text += "  (locked)"
				color = color.darkened(0.45)
		var i := list.add_item(text)
		list.set_item_metadata(i, id)
		list.set_item_custom_fg_color(i, color)
		list.set_item_tooltip(i, "%s — %s" % [def.display_name, Rarity.name_of(def.rarity)])


func _fill_file_list(button: OptionButton, paths: PackedStringArray) -> void:
	button.clear()
	for p in paths:
		button.add_item(p.get_file().get_basename())
		button.set_item_metadata(button.item_count - 1, p)
	button.disabled = paths.is_empty()


func _describe(kind: String, def_id: StringName) -> String:
	var table: Dictionary = {"hull": editor.catalog.hull, "room": editor.catalog.rooms}.get(kind, editor.catalog.equipment)
	var def: Resource = table[def_id]
	var rarity := ""
	if def.rarity != Rarity.Tier.COMMON:
		if def is EquipmentDefinition:
			rarity = "\n%s — you own %d" % [Rarity.name_of(def.rarity), profile.owned(def_id)]
		else:
			rarity = "\n%s blueprint — %s" % [Rarity.name_of(def.rarity), "unlocked" if profile.is_unlocked(def) else "LOCKED: find it in salvage"]
	return _describe_def(kind, def_id) + rarity


func _describe_def(kind: String, def_id: StringName) -> String:
	return describe_definition(kind, editor.catalog, def_id)


## Full engineering card for a palette entry: what it is, what it costs,
## what it consumes and produces, and how it fights or breaks.
static func describe_definition(kind: String, catalog: ConstructionCatalog, def_id: StringName) -> String:
	match kind:
		"hull":
			var d: HullModuleDefinition = catalog.hull[def_id]
			var cells := d.size_cells.x * d.size_cells.y * d.size_cells.z
			return "\n".join(PackedStringArray([
				d.display_name,
				"%d×%d×%d cells (%d decks) · %s" % [d.size_cells.x, d.size_cells.z, d.size_cells.y, d.size_cells.y,
					"pressurised: rooms fit inside" if d.interior else "unpressurised: no rooms"],
				"MASS %.1f t (%.1f t per cell) · STRUCTURE %.0f pts" % [d.structure_mass_kg / 1000.0, d.structure_mass_kg / 1000.0 / cells,
					d.structure_mass_kg * ShipSystems.STRUCTURE_POINTS_PER_KG],
				"SKIN ARMOUR %.0f mm · PASSIVE COOLING %.2f kW per exposed face" % [d.armor_mm, ShipStats.PASSIVE_REJECTION_KW_PER_FACE],
				"COST %d spare parts" % ServiceYard.module_cost(d),
				"Click to place (base on this deck) · R rotates",
			]))
		"room":
			var d: RoomDefinition = catalog.rooms[def_id]
			var per := PackedStringArray(["%.1f t" % (d.mass_per_cell_kg / 1000.0)])
			if d.power_kw_per_cell != 0.0:
				per.append("%s %.0f kW" % ["uses" if d.power_kw_per_cell < 0.0 else "makes", absf(d.power_kw_per_cell)])
			if d.heat_kw_per_cell > 0.0:
				per.append("heat %.0f kW" % d.heat_kw_per_cell)
			if d.crew_capacity_per_cell > 0:
				per.append("%d berth%s" % [d.crew_capacity_per_cell, "" if d.crew_capacity_per_cell == 1 else "s"])
			if d.rounds_per_cell > 0:
				per.append("%d rounds" % d.rounds_per_cell)
			if d.ammo_kg_per_cell > 0.0:
				per.append("%.0f kg of rounds" % d.ammo_kg_per_cell)
			if d.cargo_m3_per_cell > 0.0:
				per.append("%.0f m³ cargo" % d.cargo_m3_per_cell)
			return "\n".join(PackedStringArray([
				"%s — role: %s" % [d.display_name, d.role],
				"PER CELL  " + " · ".join(per),
				"COST %d spare parts per cell" % ServiceYard.room_cost(d, 1),
				"Drag on the deck to place",
			]))
	var e: EquipmentDefinition = catalog.equipment[def_id]
	var lines := PackedStringArray([
		"%s — %s" % [e.display_name, "external" if e.is_external() else "internal, %d×%d cells" % [e.footprint_cells.x, e.footprint_cells.y]],
		"MASS %.1f t · POWER %s · HEAT %.0f kW" % [e.mass_kg / 1000.0,
			"makes %.0f kW" % e.power_kw if e.power_kw > 0.0 else ("uses %.0f kW" % -e.power_kw if e.power_kw < 0.0 else "none"), e.heat_kw],
		"DURABILITY %.0f hp · stops %.0f mm of a round passing through" % [e.max_hit_points(), e.shielding_mm()],
		"COST %d spare parts%s" % [ServiceYard.equipment_cost(e), " (fitting an owned unit)" if e.rarity != Rarity.Tier.COMMON else ""],
	])
	match e.kind:
		EquipmentDefinition.Kind.CANNON:
			var g := e.cannon
			lines.append("GUN %.0f rpm · %.0f m/s · %.1f kg rounds · %.0f mm penetration at the muzzle (%.0f mm at 500 m/s)" % [
				g.rate_of_fire_rpm, g.muzzle_velocity_mps, g.round_mass_kg, g.penetration_mm, g.penetration_at(500.0)])
			lines.append("TURRET %s · spread %.2f° · energy %.1f MJ a round · fed from magazines" % [
				"trains %.0f°/s" % g.traverse_deg_s if g.traverse_deg_s > 0.0 else "fixed, fires along the nose", g.dispersion_deg,
				0.5 * g.round_mass_kg * g.muzzle_velocity_mps * g.muzzle_velocity_mps / 1.0e6])
		EquipmentDefinition.Kind.POINT_DEFENCE:
			var pg := e.cannon
			lines.append("POINT DEFENCE engages hostile craft within %.1f km on its own · %.0f rpm · %d rounds of its own · trains %.0f°/s · works with a gangway attached" % [
				WorldSimulation.PD_RANGE_M / 1000.0, pg.rate_of_fire_rpm, pg.magazine_rounds, pg.traverse_deg_s])
		EquipmentDefinition.Kind.MAIN_ENGINE:
			lines.append("THRUST %.0f kN · Isp %.0f s · burns %.1f kg/s · aft faces only" % [e.thrust_n / 1000.0, e.isp_s, e.thrust_n / (e.isp_s * ShipDynamics.G0)])
		EquipmentDefinition.Kind.RCS:
			lines.append("THRUST %.0f kN each way · Isp %.0f s · burns %.2f kg/s at full · torque grows with distance from the centre of mass" % [
				e.thrust_n / 1000.0, e.isp_s, e.thrust_n / (e.isp_s * ShipDynamics.G0)])
		EquipmentDefinition.Kind.REACTOR:
			lines.append("OUTPUT %.0f kW · throttles at %.0f K, scrams at %.0f K · explodes when destroyed (%.0f m blast)" % [
				e.power_kw, ShipSystems.THROTTLE_TEMP_K, ShipSystems.SCRAM_TEMP_K, ShipSystems.REACTOR_BLAST_RADIUS_M])
		EquipmentDefinition.Kind.RADIATOR:
			lines.append("REJECTS %.0f kW at nominal temperature (more when hot)" % e.heat_rejection_kw)
		EquipmentDefinition.Kind.PROPELLANT_TANK:
			lines.append("HOLDS %.0f t of propellant · a destroyed tank loses its share" % (e.propellant_capacity_kg / 1000.0))
		EquipmentDefinition.Kind.SENSOR:
			lines.append("SENSOR RANGE %.0f km (without one: %.0f km visual) · needed to scan" % [e.sensor_range_m / 1000.0, ShipSystems.VISUAL_RANGE_M / 1000.0])
		EquipmentDefinition.Kind.CRAFT_MOUNT:
			var c := e.craft
			lines.append("CARRIES %s · %.0f t · %s · hull %.0f" % [c.display_name, c.mass_kg / 1000.0,
				"gun %s" % c.cannon.display_name if c.cannon != null else "unarmed (recon)", c.hull_hp])
		EquipmentDefinition.Kind.DOCKING_COLLAR:
			lines.append("GANGWAY up to %.0f m · seals in %.0f s · opens into the room behind it" % [Docking.GANGWAY_MAX_M, Docking.COLLAR_SEAL_S])
	if e.rarity != Rarity.Tier.COMMON:
		lines.append("%s — found in salvage" % Rarity.name_of(e.rarity).to_upper())
	return "\n".join(lines)


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
