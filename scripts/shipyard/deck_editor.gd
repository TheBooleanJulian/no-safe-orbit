class_name DeckEditor
extends Control
## Top view of one deck: hull cells, connectors, rooms, equipment, hatches
## and the placement ghost. The nose points right (screen x grows towards
## lower z) and starboard is down (screen y grows with x). Reports intent
## through signals; the Shipyard applies edits through ShipEditor.

signal cell_pressed(cell: Vector3i, face: StringName, button: MouseButton, shift: bool)
signal room_dragged(deck: int, rect: Rect2i)
signal hover_changed(cell: Vector3i, face: StringName, shift: bool)

const COLOR_BG := Color(0.02, 0.03, 0.05)
const COLOR_GRID := Color(0.35, 0.65, 0.9, 0.08)
const COLOR_OUTLINE := Color(0.82, 0.9, 1.0, 0.9)
const COLOR_HATCH := Color(1.0, 0.85, 0.35)
const COLOR_SELECT := Color(1, 1, 1, 0.95)
const COLOR_ISSUE := Color(1.0, 0.35, 0.3, 0.95)
const COLOR_GHOST_OK := Color(0.4, 1.0, 0.55, 0.45)
const COLOR_GHOST_BAD := Color(1.0, 0.35, 0.3, 0.45)
const CONNECTOR_COLORS := {&"spine": Color(0.3, 0.9, 1.0), &"pod": Color(1.0, 0.4, 0.9)}
const MARGIN_CELLS := 3
## Pointer within this fraction of a cell edge selects that edge's face.
const EDGE_ZONE := 0.28

var editor: ShipEditor
var deck: int = 0
## Room tool: left-drag draws a rectangle instead of clicking.
var drag_rooms: bool = false
var ghost_cells: Array[Vector3i] = []
var ghost_ok: bool = true
## External-equipment ghost: the face being targeted.
var ghost_face: StringName = &""
var selection_cells: Array[Vector3i] = []
var issue_cells: Array[Vector3i] = []

var _x_min := 0
var _z_max := 0
var _px := 24.0
var _origin := Vector2.ZERO
var _hover_cell := Vector3i(999, 999, 999)
var _hover_face: StringName = &""
var _drag_start: Variant = null  # Vector3i while dragging a room


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	resized.connect(queue_redraw)


# --- Mapping ------------------------------------------------------------------

func _update_mapping() -> void:
	var b := editor.grid.cell_bounds() if not editor.blueprint.modules.is_empty() else AABB(Vector3.ZERO, Vector3(4, 1, 8))
	_x_min = int(b.position.x) - MARGIN_CELLS
	var x_max := int(b.end.x) - 1 + MARGIN_CELLS
	var z_min := int(b.position.z) - MARGIN_CELLS
	_z_max = int(b.end.z) - 1 + MARGIN_CELLS
	var cols := _z_max - z_min + 1
	var rows := x_max - _x_min + 1
	_px = floorf(minf(size.x / cols, size.y / rows))
	_origin = ((size - Vector2(cols, rows) * _px) * 0.5).floor()


func cell_rect(cell: Vector3i) -> Rect2:
	return Rect2(_origin + Vector2(_z_max - cell.z, cell.x - _x_min) * _px, Vector2.ONE * _px)


func cell_at(pos: Vector2) -> Vector3i:
	var local := (pos - _origin) / _px
	return Vector3i(_x_min + int(floor(local.y)), deck, _z_max - int(floor(local.x)))


## Face of the hovered cell the pointer is nearest to: an edge face when
## close to an edge; in the middle, whichever of top (dorsal) and underside
## (ventral) is open to space — Shift picks the other one.
func face_at(pos: Vector2, shift: bool) -> StringName:
	var r := cell_rect(cell_at(pos))
	var u := (pos.x - r.position.x) / _px  # 0 = aft edge, 1 = fore edge
	var v := (pos.y - r.position.y) / _px  # 0 = port edge, 1 = starboard edge
	var d := {&"aft": u, &"fore": 1.0 - u, &"port": v, &"starboard": 1.0 - v}
	var best: StringName = &""
	var best_d := EDGE_ZONE
	for face in d:
		if d[face] < best_d:
			best = face
			best_d = d[face]
	if best == &"":
		return vertical_face(cell_at(pos), shift)
	return best


## Top or underside of a cell: the one open to space (top if both or
## neither are); `other` picks the opposite.
func vertical_face(cell: Vector3i, other: bool) -> StringName:
	var up := editor != null and editor.grid.is_exterior_face(cell, &"dorsal")
	var down := editor != null and editor.grid.is_exterior_face(cell, &"ventral")
	var face: StringName = &"ventral" if down and not up else &"dorsal"
	if other:
		face = &"dorsal" if face == &"ventral" else &"ventral"
	return face


## Cell on the other side of `face` (dorsal/ventral = deck above/below).
static func across(cell: Vector3i, face: StringName) -> Vector3i:
	return cell + ShipGrid.FACE_NORMALS.get(face, Vector3i.ZERO)


# --- Input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var cell := cell_at(mm.position)
		var face := face_at(mm.position, mm.shift_pressed)
		if cell != _hover_cell or face != _hover_face:
			_hover_cell = cell
			_hover_face = face
			hover_changed.emit(cell, face, mm.shift_pressed)
		if _drag_start != null:
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var cell := cell_at(mb.position)
		var face := face_at(mb.position, mb.shift_pressed)
		if mb.button_index == MOUSE_BUTTON_LEFT and drag_rooms:
			if mb.pressed:
				_drag_start = cell
			elif _drag_start != null:
				var a: Vector3i = _drag_start
				_drag_start = null
				room_dragged.emit(deck, Rect2i(mini(a.x, cell.x), mini(a.z, cell.z),
					absi(cell.x - a.x) + 1, absi(cell.z - a.z) + 1))
			accept_event()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			grab_focus()
			cell_pressed.emit(cell, face, mb.button_index, mb.shift_pressed)
			accept_event()


## Cells of the rectangle being dragged (for the room ghost), or [].
func drag_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if _drag_start == null:
		return out
	var a: Vector3i = _drag_start
	for x in range(mini(a.x, _hover_cell.x), maxi(a.x, _hover_cell.x) + 1):
		for z in range(mini(a.z, _hover_cell.z), maxi(a.z, _hover_cell.z) + 1):
			out.append(Vector3i(x, deck, z))
	return out


func is_dragging() -> bool:
	return _drag_start != null


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	if editor == null:
		return
	_update_mapping()
	var font := get_theme_default_font()
	var grid := editor.grid
	var bp := editor.blueprint
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	_draw_grid_lines()

	# Deck below, as a faint outline for alignment.
	for cell: Vector3i in grid.module_at:
		if cell.y == deck - 1 and not grid.module_at.has(Vector3i(cell.x, deck, cell.z)):
			draw_rect(cell_rect(cell).grow(-_px * 0.42), Color(0.6, 0.7, 0.8, 0.18))

	# Hull cells on this deck.
	for cell: Vector3i in grid.module_at:
		if cell.y != deck:
			continue
		var def := grid.module_def(grid.module_at[cell])
		var r := cell_rect(cell)
		draw_rect(r, def.color.darkened(0.55))
		if not def.interior:
			draw_line(r.position, r.end, def.color.darkened(0.2), 1.0)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), def.color.darkened(0.2), 1.0)

	for i in bp.rooms.size():
		var room := bp.rooms[i]
		var def: RoomDefinition = grid.catalog.rooms.get(room.def_id)
		if room.deck != deck or def == null:
			continue
		var rr := _cells_rect(ShipGrid.room_cells(room)).grow(-2)
		draw_rect(rr, Color(def.color, 0.55))
		draw_rect(rr, def.color.lightened(0.3), false, 1.5)
		# Top-left, so equipment labels drawn over the room centre stay readable.
		_label(font, rr, def.display_name, Color(1, 1, 1, 0.9), true)

	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or def.is_external() or bp.equipment[i].cell.y != deck:
			continue
		var er := _cells_rect(grid.equipment_cells(i)).grow(-_px * 0.18)
		draw_rect(er, def.color.darkened(0.2))
		draw_rect(er, def.color.lightened(0.4), false, 1.5)
		_label(font, er, def.display_name, Color.BLACK)

	_draw_slopes()
	_draw_module_outlines()
	_draw_bus()
	_draw_plates()
	_draw_hatches()
	_draw_external_equipment()

	for cell in issue_cells:
		if cell.y == deck:
			draw_rect(cell_rect(cell).grow(-1), COLOR_ISSUE, false, 2.0)
	for cell in selection_cells:
		if cell.y == deck:
			draw_rect(cell_rect(cell).grow(-1), COLOR_SELECT, false, 2.0)

	var ghost := drag_cells() if is_dragging() else ghost_cells
	for cell in ghost:
		if cell.y == deck:
			draw_rect(cell_rect(cell).grow(-1), COLOR_GHOST_OK if ghost_ok else COLOR_GHOST_BAD)
	if ghost_face != &"" and not ghost.is_empty():
		_draw_face_marker(ghost[0], ghost_face, COLOR_GHOST_OK if ghost_ok else COLOR_GHOST_BAD, 1.0)

	var hint_col := Color(0.82, 0.9, 1.0, 0.55)
	draw_string(font, Vector2(8, 18), "DECK %d" % deck, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.82, 0.9, 1.0))
	draw_string(font, Vector2(size.x - 70, size.y * 0.5), "FORE ▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hint_col)
	draw_string(font, Vector2(size.x * 0.5 - 20, 18), "PORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hint_col)
	draw_string(font, Vector2(size.x * 0.5 - 30, size.y - 8), "STARBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hint_col)


func _draw_grid_lines() -> void:
	var b := Rect2(_origin, Vector2(size - _origin * 2.0))
	var x := _origin.x
	while x <= b.end.x + 0.5:
		draw_line(Vector2(x, b.position.y), Vector2(x, b.end.y), COLOR_GRID)
		x += _px
	var y := _origin.y
	while y <= b.end.y + 0.5:
		draw_line(Vector2(b.position.x, y), Vector2(b.end.x, y), COLOR_GRID)
		y += _px


## Module boundaries, plus a coloured tick where a free face (nothing
## attached yet) has a connector — where the next module can go.
func _draw_module_outlines() -> void:
	var grid := editor.grid
	for cell: Vector3i in grid.module_at:
		if cell.y != deck:
			continue
		var mi: int = grid.module_at[cell]
		for face: StringName in [&"fore", &"aft", &"port", &"starboard"]:
			var other: int = grid.module_at.get(across(cell, face), -1)
			if other == mi:
				continue
			var seg := _edge(cell, face)
			draw_line(seg[0], seg[1], COLOR_OUTLINE, 2.0)
			var conn := grid.module_connector(mi, face)
			if conn != &"" and other < 0:
				var mid: Vector2 = (seg[0] + seg[1]) * 0.5
				var inward: Vector2 = cell_rect(cell).get_center() - mid
				draw_line(mid + inward * 0.05, mid + inward * 0.3, CONNECTOR_COLORS.get(conn, Color.WHITE), 3.0)


## Wedge cells: contour lines across the slope, and a chevron pointing to
## its low edge (dimmer when the slope faces down).
func _draw_slopes() -> void:
	var grid := editor.grid
	for cell: Vector3i in grid.module_at:
		if cell.y != deck or not grid.is_wedge_cell(cell):
			continue
		var faces := grid.slope_faces(cell)
		var low := _edge(cell, faces[0])
		var r := cell_rect(cell)
		var inward: Vector2 = r.get_center() - (low[0] + low[1]) * 0.5
		var col := Color(0.82, 0.9, 1.0, 0.55 if faces[1] == &"dorsal" else 0.28)
		for k in [0.25, 0.5, 0.75]:
			var off: Vector2 = inward * 2.0 * k
			draw_line(low[0] + off, low[1] + off, col, 1.0)
		var mid: Vector2 = (low[0] + low[1]) * 0.5 + inward * 0.35
		var side: Vector2 = (low[1] - low[0]) * 0.18
		draw_polyline(PackedVector2Array([mid - side + inward * 0.25, mid, mid + side + inward * 0.25]), col, 2.0)


## Power bus: gold conduit through cell centres; ▲/▼ where it rises to the
## deck above / drops to the one below.
func _draw_bus() -> void:
	var bus := editor.blueprint.bus
	if bus.is_empty():
		return
	var col := Color(CyberTheme.AMBER, 0.85)
	var w := maxf(_px * 0.1, 2.0)
	for key: String in bus:
		var cell := ShipBlueprint.parse_cell_key(key)
		if cell.y != deck:
			continue
		var c := cell_rect(cell).get_center()
		draw_rect(Rect2(c - Vector2.ONE * w, Vector2.ONE * w * 2.0), col)
		for face in [&"fore", &"starboard"]:
			var other := across(cell, face)
			if bus.has(ShipBlueprint.cell_key(other)):
				draw_line(c, cell_rect(other).get_center(), col, w)
		if bus.has(ShipBlueprint.cell_key(cell + Vector3i.UP)):
			draw_string(get_theme_default_font(), c + Vector2(w + 1, -w), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		if bus.has(ShipBlueprint.cell_key(cell + Vector3i.DOWN)):
			draw_string(get_theme_default_font(), c + Vector2(w + 1, w + 8), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)


## Armour plates: a bar inside the edge for side plates, a corner tab for
## top (filled) and underside (outline) plates. Cyan = 40 mm, amber = 80 mm.
func _draw_plates() -> void:
	for key: String in editor.blueprint.armor:
		var cf := ShipBlueprint.parse_plate_key(key)
		var cell: Vector3i = cf[0]
		if cell.y != deck:
			continue
		var mm := int(editor.blueprint.armor[key])
		var col := Color(CyberTheme.AMBER if mm >= ShipBlueprint.PLATE_THICK_MM else CyberTheme.CYAN, 0.9)
		var r := cell_rect(cell)
		var tab := Vector2.ONE * maxf(_px * 0.24, 4.0)
		match cf[1]:
			&"dorsal":
				draw_rect(Rect2(r.position + Vector2(2, 2), tab), col)
			&"ventral":
				draw_rect(Rect2(Vector2(r.position.x + 2, r.end.y - 2 - tab.y), tab), col, false, 1.5)
			_:
				var seg := _edge(cell, cf[1])
				var inward: Vector2 = (r.get_center() - (seg[0] + seg[1]) * 0.5).normalized() * _px * 0.1
				draw_line(seg[0] + inward, seg[1] + inward, col, maxf(_px * (0.16 if mm >= ShipBlueprint.PLATE_THICK_MM else 0.09), 2.0))


func _draw_hatches() -> void:
	for h in editor.blueprint.hatches:
		if h.a.y == h.b.y:
			if h.a.y != deck:
				continue
			var face := ShipGrid.face_of(h.b - h.a)
			if face == &"":
				continue
			var seg := _edge(h.a, face)
			var mid: Vector2 = (seg[0] + seg[1]) * 0.5
			var half: Vector2 = (seg[1] - seg[0]) * 0.3
			draw_line(mid - half, mid + half, COLOR_HATCH, 5.0)
		else:
			for c in [h.a, h.b]:
				if c.y == deck:
					var up: bool = maxi(h.a.y, h.b.y) > deck
					var center := cell_rect(c).get_center()
					draw_arc(center, _px * 0.22, 0.0, TAU, 16, COLOR_HATCH, 2.0)
					var tip := center + Vector2(0, -_px * 0.15 if up else _px * 0.15)
					draw_line(center, tip, COLOR_HATCH, 2.0)


func _draw_external_equipment() -> void:
	var bp := editor.blueprint
	for i in bp.equipment.size():
		var def := editor.grid.equipment_def(i)
		var e := bp.equipment[i]
		if def == null or not def.is_external():
			continue
		for cell in editor.grid.external_cells(i):
			if cell.y == deck:
				_draw_face_marker(cell, e.face, def.color, 1.0)


## Edge faces: a bar just outside the edge. Dorsal: filled dot; ventral: ring.
func _draw_face_marker(cell: Vector3i, face: StringName, color: Color, alpha: float) -> void:
	var c := Color(color, alpha)
	var r := cell_rect(cell)
	match face:
		&"dorsal":
			draw_circle(r.get_center(), _px * 0.2, c)
		&"ventral":
			draw_arc(r.get_center(), _px * 0.2, 0.0, TAU, 16, c, 2.5)
		_:
			var seg := _edge(cell, face)
			var outward: Vector2 = (seg[0] + seg[1]) * 0.5 - r.get_center()
			var off: Vector2 = outward.normalized() * _px * 0.12
			var along: Vector2 = (seg[1] - seg[0]) * 0.32
			var mid: Vector2 = (seg[0] + seg[1]) * 0.5 + off
			draw_line(mid - along, mid + along, c, maxf(_px * 0.22, 3.0))


## Screen segment of a cell's horizontal face.
func _edge(cell: Vector3i, face: StringName) -> Array[Vector2]:
	var r := cell_rect(cell)
	match face:
		&"fore":
			return [Vector2(r.end.x, r.position.y), r.end]
		&"aft":
			return [r.position, Vector2(r.position.x, r.end.y)]
		&"port":
			return [r.position, Vector2(r.end.x, r.position.y)]
		_:
			return [Vector2(r.position.x, r.end.y), r.end]


func _cells_rect(cells: Array[Vector3i]) -> Rect2:
	var out := Rect2()
	for k in cells.size():
		out = cell_rect(cells[k]) if k == 0 else out.merge(cell_rect(cells[k]))
	return out


func _label(font: Font, r: Rect2, text: String, color: Color, top_left: bool = false) -> void:
	var fs := 11
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > r.size.x - 6.0:
		text = text.split(" ")[0]
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > r.size.x - 6.0 or r.size.y < fs + 2:
			return
	var at := r.position + Vector2(4, fs + 2) if top_left else r.get_center() + Vector2(-w * 0.5, fs * 0.35)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
