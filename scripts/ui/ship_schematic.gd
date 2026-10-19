class_name ShipSchematic
extends Control
## Top-down module and damage map of one ship (nose to the right, port at
## the top), drawn from its ShipSystems every frame:
##   modules — outline; fill from cyan (intact) to magenta (structure gone),
##             dark when wrecked;
##   rooms   — faint cyan when pressurised, magenta when vented, or the
##             colour in `room_overlay` (boarding control);
##   systems — cyan working, amber damaged, grey unpowered, red ✕ destroyed;
##   crew    — one dot per fit person in a room (white), wounded amber.
## `deck` = -1 draws every deck merged (worst state on top); otherwise one deck.

var systems: ShipSystems
var title: String = ""
var deck: int = -1
var accent: Color = CyberTheme.CYAN
## Room index -> fill colour (overrides pressure colouring).
var room_overlay: Dictionary = {}
var show_crew: bool = true
var show_legend: bool = false

const PAD := 8.0
const TITLE_H := 16.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible and systems != null:
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 0.75))
	draw_rect(Rect2(Vector2.ZERO, size), accent * Color(1, 1, 1, 0.6), false, 1.0)
	draw_line(Vector2.ZERO, Vector2(0, size.y), accent, 3.0)
	if title != "":
		draw_string(font, Vector2(PAD, TITLE_H - 3), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 12, accent)
	if systems == null:
		return
	var grid := systems.grid
	var bp := systems.blueprint
	var b := grid.cell_bounds()
	var cols := b.size.z  # along the ship
	var rows := b.size.x  # across
	var area := Rect2(Vector2(PAD, TITLE_H + 2), size - Vector2(PAD * 2, TITLE_H + 2 + PAD + (14.0 if show_legend else 0.0)))
	var cell := minf(area.size.x / maxf(cols, 1.0), area.size.y / maxf(rows, 1.0))
	var origin := area.position + (area.size - Vector2(cols, rows) * cell) * 0.5
	# Screen x = nose to the right (−z), screen y = port at the top (−x).
	var to_screen := func(x: float, z: float) -> Vector2:
		return origin + Vector2((b.end.z - z) * cell, (x - b.position.x) * cell)
	var cell_rect := func(x0: float, z0: float, x1: float, z1: float) -> Rect2:
		var p0: Vector2 = to_screen.call(x0, z1)
		var p1: Vector2 = to_screen.call(x1, z0)
		return Rect2(p0, p1 - p0)

	# Modules.
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
		var fill := Color(0.12, 0.05, 0.05, 0.9) if m.wrecked() else CyberTheme.MAGENTA.lerp(CyberTheme.CYAN, frac) * Color(0.35, 0.35, 0.35, 0.55)
		draw_rect(r, fill)
		draw_rect(r, CyberTheme.CYAN * Color(1, 1, 1, 0.55), false, 1.0)
	# Rooms: pressurised first, vented / overlaid on top.
	var order: Array[int] = []
	for i in bp.rooms.size():
		if deck < 0 or bp.rooms[i].deck == deck:
			order.append(i)
	order.sort_custom(func(a: int, c: int) -> bool: return _room_rank(a) < _room_rank(c))
	for i in order:
		var rr := bp.rooms[i].rect
		var r: Rect2 = cell_rect.call(rr.position.x, rr.position.y, rr.position.x + rr.size.x, rr.position.y + rr.size.y)
		var col: Color = room_overlay.get(i, CyberTheme.CYAN * Color(1, 1, 1, 0.12) if systems.rooms[i].pressurized else CyberTheme.MAGENTA * Color(1, 1, 1, 0.45))
		draw_rect(r.grow(-1.0), col)
	# Crew.
	if show_crew and systems.crew != null:
		var per_room := {}
		for mem in systems.crew.members:
			if mem.location < 0 or mem.state == CrewRoster.State.DEAD:
				continue
			if deck >= 0 and bp.rooms[mem.location].deck != deck:
				continue
			var list: Array = per_room.get_or_add(mem.location, [])
			list.append(mem)
		for room in per_room:
			var rr := bp.rooms[room].rect
			var r: Rect2 = cell_rect.call(rr.position.x, rr.position.y, rr.position.x + rr.size.x, rr.position.y + rr.size.y)
			var k := 0
			for mem in per_room[room]:
				var p := r.position + Vector2(4 + (k % 6) * 5, 4 + (k / 6) * 5)
				draw_circle(p, 1.8, Color.WHITE if mem.fit() else CyberTheme.WARN)
				k += 1
	# Systems.
	for e in systems.equipment:
		var pe := bp.equipment[e.index]
		if deck >= 0 and pe.cell.y != deck:
			continue
		var col := CyberTheme.CYAN
		if e.destroyed():
			col = CyberTheme.DANGER
		elif e.hp < e.max_hp:
			col = CyberTheme.WARN
		elif not e.powered:
			col = CyberTheme.TEXT_DIM
		var center: Vector2
		var half := maxf(cell * 0.28, 2.5)
		if e.def.is_external():
			var n: Vector3i = ShipGrid.FACE_NORMALS.get(pe.face, Vector3i.ZERO)
			center = to_screen.call(pe.cell.x + 0.5 + n.x * 0.5, pe.cell.z + 0.5 + n.z * 0.5)
		else:
			var fp := grid.equipment_footprint(e.index)
			center = to_screen.call(pe.cell.x + fp.x * 0.5, pe.cell.z + fp.y * 0.5)
			half = maxf(cell * minf(fp.x, fp.y) * 0.3, 3.0)
		if e.destroyed():
			draw_line(center - Vector2(half, half), center + Vector2(half, half), col, 2.0)
			draw_line(center + Vector2(-half, half), center + Vector2(half, -half), col, 2.0)
		else:
			draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), col)
	if show_legend:
		draw_string(font, Vector2(PAD, size.y - 4), "■ working  ■ damaged  ✕ destroyed  ▒ vented   ● crew", HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 11, CyberTheme.TEXT_DIM)


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
			return CyberTheme.DANGER * Color(1, 1, 1, 0.3)
	return Color(0, 0, 0, 0)
