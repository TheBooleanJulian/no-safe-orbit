class_name ShipSchematic
extends Control
## Top-down module and damage map of one ship (nose to the right, port at
## the top), drawn from its ShipSystems every frame. States are shapes as
## well as colours (CyberTheme glyphs):
##   systems  ■ functional (cyan) · ▲ degraded (amber) · ◆ critical (red)
##            · ✕ destroyed (red) · ○ unpowered / switched off (grey)
##   rooms    tinted in their shipyard colour · hatched magenta vented · dashed
##            border isolated · or `room_overlay` (boarding control)
##   modules  outline; fill from cyan (intact) to magenta (structure gone),
##            dark when wrecked
##   crew     ● per fit person (white), ● amber wounded
## `deck` = -1 draws every deck merged (worst on top); else one deck.
## Interactive (`interactive`): clicking picks the system or room under the
## cursor (`picked`); the selection and the alerted subject are ringed.

signal picked(kind: StringName, id: String)

var systems: ShipSystems
var title: String = ""
var deck: int = -1
var accent: Color = CyberTheme.CYAN
## Room index -> fill colour (overrides pressure colouring).
var room_overlay: Dictionary = {}
var show_crew: bool = true
## The ship's crew are the enemy's: drawn in red. Our boarders aboard it:
## room index -> Array of CrewRoster.Member, drawn in their post colours.
var hostile_crew: bool = false
var boarders: Dictionary = {}
## A crew member to ring (picked in the roster).
var highlight_member: String = ""
var show_legend: bool = false
var interactive: bool = false
## Selected subject (equipment or room id) and the alert subject.
var selected_id: String = ""
var alert_id: String = ""

const PAD := 8.0
const TITLE_H := 16.0

var _hits: Array[Dictionary] = []  # {rect, kind, id} — systems first
var _clock := 0.0
var _origin := Vector2.ZERO
var _cell := 1.0
var _bounds := AABB()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE


## Redraws at most this often (s): a capital ship has hundreds of modules,
## and its dots and blinks don't need 60 Hz (play-test batch 6).
const REDRAW_S := 0.1
var _since_draw := INF


func _process(delta: float) -> void:
	_clock += delta
	_since_draw += delta
	if visible and systems != null and _since_draw >= REDRAW_S:
		_since_draw = 0.0
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var hit := pick_at(mb.position)
		if not hit.is_empty():
			selected_id = hit.id
			picked.emit(hit.kind, hit.id)
			accept_event()


## The system (preferred) or room under a local point: {kind, id} or {}.
func pick_at(p: Vector2) -> Dictionary:
	for h in _hits:
		if (h.rect as Rect2).grow(2.0).has_point(p):
			return {"kind": h.kind, "id": h.id}
	return {}


## Screen centre of a subject (tests, keyboard focus), or (-1, -1).
func center_of(id: String) -> Vector2:
	for h in _hits:
		if h.id == id:
			return (h.rect as Rect2).get_center()
	return Vector2(-1, -1)


## Geometry for the current size: cell size and origin. False without a ship.
func _update_geometry() -> bool:
	if systems == null:
		return false
	_bounds = systems.grid.cell_bounds()
	var area := Rect2(Vector2(PAD, TITLE_H + 2), size - Vector2(PAD * 2, TITLE_H + 2 + PAD + (14.0 if show_legend else 0.0)))
	_cell = minf(area.size.x / maxf(_bounds.size.z, 1.0), area.size.y / maxf(_bounds.size.x, 1.0))
	_origin = area.position + (area.size - Vector2(_bounds.size.z, _bounds.size.x) * _cell) * 0.5
	return true


## Screen point of grid (x, z): nose to the right, port at the top.
func _to_screen(x: float, z: float) -> Vector2:
	return _origin + Vector2((_bounds.end.z - z) * _cell, (x - _bounds.position.x) * _cell)


func _cell_rect(x0: float, z0: float, x1: float, z1: float) -> Rect2:
	var p0 := _to_screen(x0, z1)
	var p1 := _to_screen(x1, z0)
	return Rect2(p0, p1 - p0)


## [centre, half size] of a system's marker.
func _equipment_marker(e: ShipSystems.EquipmentState) -> Array:
	var pe := systems.blueprint.equipment[e.index]
	if e.def.is_external():
		var n: Vector3i = ShipGrid.FACE_NORMALS.get(pe.face, Vector3i.ZERO)
		return [_to_screen(pe.cell.x + 0.5 + n.x * 0.5, pe.cell.z + 0.5 + n.z * 0.5), clampf(_cell * 0.28, 3.0, 6.0)]
	var fp := systems.grid.equipment_footprint(e.index)
	return [_to_screen(pe.cell.x + fp.x * 0.5, pe.cell.z + fp.y * 0.5), clampf(_cell * minf(fp.x, fp.y) * 0.3, 3.5, 9.0)]


## Click targets for the visible systems (first) and rooms.
func layout_hits() -> void:
	_hits.clear()
	if not _update_geometry():
		return
	for e in systems.equipment:
		if deck >= 0 and systems.blueprint.equipment[e.index].cell.y != deck:
			continue
		var m := _equipment_marker(e)
		var half: float = m[1]
		_hits.append({"rect": Rect2(m[0] - Vector2(half, half), Vector2(half, half) * 2.0), "kind": &"equipment", "id": e.id})
	for i in systems.blueprint.rooms.size():
		var r := systems.blueprint.rooms[i]
		if deck >= 0 and r.deck != deck:
			continue
		_hits.append({"rect": _cell_rect(r.rect.position.x, r.rect.position.y, r.rect.position.x + r.rect.size.x, r.rect.position.y + r.rect.size.y),
			"kind": &"room", "id": r.id})


func _draw() -> void:
	layout_hits()
	var font := CyberTheme.sans()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.025, 0.8))
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r, accent.g, accent.b, CyberTheme.BORDER_ALPHA), false, 1.0)
	if title != "":
		draw_string(font, Vector2(PAD, TITLE_H - 3), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, CyberTheme.SIZE_SMALL + 1, accent)
	if systems == null:
		return
	var grid := systems.grid
	var bp := systems.blueprint
	var cell_rect := func(x0: float, z0: float, x1: float, z1: float) -> Rect2: return _cell_rect(x0, z0, x1, z1)

	for i in bp.modules.size():
		var def := grid.module_def(i)
		if def == null:
			continue
		var pos := bp.modules[i].position
		var sz := grid.module_size(i)
		if deck >= 0 and (deck < pos.y or deck >= pos.y + sz.y):
			continue
		var r: Rect2 = cell_rect.call(pos.x, pos.z, pos.x + sz.x, pos.z + sz.z)
		var m := systems.modules[i]
		var frac := m.structure / m.max_structure
		var fill := Color(0.12, 0.05, 0.05, 0.9) if m.wrecked() else CyberTheme.MAGENTA.lerp(CyberTheme.CYAN, frac) * Color(0.3, 0.3, 0.3, 0.5)
		draw_rect(r, fill)
		draw_rect(r, Color(CyberTheme.CYAN.r, CyberTheme.CYAN.g, CyberTheme.CYAN.b, 0.45), false, 1.0)
	# Rooms.
	var order: Array[int] = []
	for i in bp.rooms.size():
		if deck < 0 or bp.rooms[i].deck == deck:
			order.append(i)
	order.sort_custom(func(a: int, c: int) -> bool: return _room_rank(a) < _room_rank(c))
	var room_rects := {}
	for i in order:
		var rr := bp.rooms[i].rect
		var r: Rect2 = cell_rect.call(rr.position.x, rr.position.y, rr.position.x + rr.size.x, rr.position.y + rr.size.y)
		room_rects[i] = r
		var vented := not systems.rooms[i].pressurized
		var rdef: RoomDefinition = systems.grid.catalog.rooms.get(bp.rooms[i].def_id)
		var tint := Color(rdef.color, 0.22) if rdef != null else CyberTheme.CYAN * Color(1, 1, 1, 0.1)
		var col: Color = room_overlay.get(i, CyberTheme.MAGENTA * Color(1, 1, 1, 0.3) if vented else tint)
		draw_rect(r.grow(-1.0), col)
		if vented and not room_overlay.has(i):
			# Hatching: vented reads without colour.
			var step := 6.0
			var x := r.position.x - r.size.y
			while x < r.end.x:
				var a := Vector2(maxf(x, r.position.x), r.position.y + maxf(r.position.x - x, 0.0))
				var e := Vector2(minf(x + r.size.y, r.end.x), r.position.y + minf(r.size.y, r.end.x - x))
				draw_line(a, e, CyberTheme.MAGENTA * Color(1, 1, 1, 0.55), 1.0)
				x += step
		if systems.isolated_rooms.has(i):
			_dashed_rect(r.grow(-2.0), CyberTheme.AMBER)
	# Crew: a dot per person in their post's colour (red: the enemy's);
	# a ring = wounded. Our boarders aboard follow the ship's own crew.
	if show_crew and systems.crew != null:
		var per_room := {}
		for mem in systems.crew.members:
			if mem.location < 0 or mem.state == CrewRoster.State.DEAD or not room_rects.has(mem.location):
				continue
			var list: Array = per_room.get_or_add(mem.location, [])
			list.append(mem)
		for room in boarders:
			if room_rects.has(room):
				var list: Array = per_room.get_or_add(room, [])
				for mem in boarders[room]:
					list.append(mem)
		for room in per_room:
			var r: Rect2 = room_rects[room]
			var across := maxi(int((r.size.x - 4.0) / CREW_DOT_STEP), 1)
			var k := 0
			for mem: CrewRoster.Member in per_room[room]:
				var ours := not hostile_crew or (boarders.has(room) and (boarders[room] as Array).has(mem))
				var col: Color = CrewRoster.ROLE_COLORS[mem.role] if ours else CyberTheme.RED
				var p := r.position + Vector2(5.0 + (k % across) * CREW_DOT_STEP, 5.0 + floorf(float(k) / across) * CREW_DOT_STEP)
				if mem.fit():
					draw_circle(p, CREW_DOT_R, col)
				else:
					draw_arc(p, CREW_DOT_R, 0.0, TAU, 12, col, 1.5)
				if hostile_crew and ours:
					draw_arc(p, CREW_DOT_R + 1.5, 0.0, TAU, 12, Color.WHITE, 1.0)
				if mem.id == highlight_member and not hostile_crew:
					draw_arc(p, CREW_DOT_R + 3.0, 0.0, TAU, 16, Color.WHITE, 1.5)
				k += 1
	# Systems.
	for e in systems.equipment:
		if deck >= 0 and bp.equipment[e.index].cell.y != deck:
			continue
		var state := CyberTheme.equipment_state(e)
		if systems.switched_off.has(e.id):
			state = [CyberTheme.GLYPH_OFFLINE, CyberTheme.TEXT_DIM, "switched off"]
		var m := _equipment_marker(e)
		var center: Vector2 = m[0]
		var half: float = m[1]
		_glyph(state[0], center, half, state[1])
		if e.id == selected_id:
			draw_arc(center, half + 4.0, 0.0, TAU, 20, Color.WHITE, 1.5)
		if e.id == alert_id:
			draw_arc(center, half + 7.0 + 2.0 * sin(_clock * 6.0), 0.0, TAU, 20, CyberTheme.AMBER, 1.5)
	for i in room_rects:
		if bp.rooms[i].id == selected_id:
			draw_rect((room_rects[i] as Rect2).grow(1.0), Color.WHITE, false, 1.5)
		if bp.rooms[i].id == alert_id:
			draw_rect((room_rects[i] as Rect2).grow(3.0), CyberTheme.AMBER, false, 1.5)
	if show_legend:
		draw_string(font, Vector2(PAD, size.y - 4), "■ ok  ▲ degraded  ◆ critical  ✕ destroyed  ○ off  ● crew  ▨ vented",
			HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, CyberTheme.SIZE_SMALL, CyberTheme.TEXT_DIM)


const CREW_DOT_R := 3.0
const CREW_DOT_STEP := 8.0


## State shapes: square, triangle, diamond, cross, ring.
func _glyph(glyph: String, c: Vector2, h: float, col: Color) -> void:
	match glyph:
		CyberTheme.GLYPH_DEGRADED:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, h), c + Vector2(-h, h)]), col)
		CyberTheme.GLYPH_CRITICAL:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 1.2), c + Vector2(h * 1.2, 0), c + Vector2(0, h * 1.2), c + Vector2(-h * 1.2, 0)]), col)
		CyberTheme.GLYPH_DESTROYED:
			draw_line(c - Vector2(h, h), c + Vector2(h, h), col, 2.0)
			draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col, 2.0)
		CyberTheme.GLYPH_OFFLINE:
			draw_arc(c, h, 0.0, TAU, 16, col, 1.5)
		_:
			draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), col)


func _dashed_rect(r: Rect2, col: Color) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var e: Vector2 = corners[(k + 1) % 4]
		draw_dashed_line(a, e, col, 1.5, 4.0)


## Draw order: pressurised, then vented, then overlaid.
func _room_rank(i: int) -> int:
	if room_overlay.has(i):
		return 2
	return 0 if systems.rooms[i].pressurized else 1


## Overlay colour for a BoardingAction.room_control() state (`t` = seconds, for the pulse).
static func control_color(state: StringName, t: float) -> Color:
	match state:
		&"held":
			return CyberTheme.CYAN * Color(1, 1, 1, 0.45)
		&"contested":
			return CyberTheme.MAGENTA * Color(1, 1, 1, 0.45 + 0.3 * sin(t * 8.0))
		&"defended":
			return CyberTheme.RED * Color(1, 1, 1, 0.3)
	return Color(0, 0, 0, 0)
