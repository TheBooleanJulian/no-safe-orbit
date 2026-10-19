class_name OrthoView
extends Control
## Side or front orthographic projection of the hull and external equipment,
## with the deck being edited marked. Read-only.
## SIDE: nose right (like the deck editor), decks up.
## FRONT: seen from ahead, so starboard is on the left.

enum Mode { SIDE, FRONT }

@export var mode: Mode = Mode.SIDE

var editor: ShipEditor
var deck: int = 0


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05))
	draw_string(font, Vector2(6, 14), "SIDE (nose ▶)" if mode == Mode.SIDE else "FRONT (from ahead)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.82, 0.9, 1.0, 0.6))
	if editor == null or editor.blueprint.modules.is_empty():
		return
	var grid := editor.grid
	var b := grid.cell_bounds()
	var cols := int(b.size.z if mode == Mode.SIDE else b.size.x) + 2
	var rows := int(b.size.y) + 2
	var px := floorf(minf((size.x - 8) / cols, (size.y - 22) / rows))
	var origin := Vector2((size.x - cols * px) * 0.5, 18 + (size.y - 22 - rows * px) * 0.5)
	var top_deck := int(b.end.y) - 1
	var to_screen := func(cell: Vector3i) -> Rect2:
		var col := (int(b.end.z) - 1 - cell.z) if mode == Mode.SIDE else (int(b.end.x) - 1 - cell.x)
		return Rect2(origin + Vector2(col + 1, top_deck - cell.y + 1) * px, Vector2.ONE * px)

	# Current deck band.
	var band: Rect2 = to_screen.call(Vector3i(int(b.end.x) - 1, deck, int(b.end.z) - 1))
	draw_rect(Rect2(origin.x, band.position.y, cols * px, px), Color(0.35, 0.65, 0.9, 0.12))
	for cell: Vector3i in grid.module_at:
		var mi: int = grid.module_at[cell]
		var def := grid.module_def(mi)
		var r: Rect2 = (to_screen.call(cell) as Rect2).grow(-0.5)
		if grid.is_wedge(mi):
			var poly := _wedge_profile(grid, mi, cell, r)
			if poly.size() >= 3:
				draw_colored_polygon(poly, def.color.darkened(0.25))
			continue
		draw_rect(r, def.color.darkened(0.35))
	# Armour plates seen edge-on or face-on along the view: a bright edge.
	for key: String in editor.blueprint.armor:
		var cf := ShipBlueprint.parse_plate_key(key)
		var cell: Vector3i = cf[0]
		var r: Rect2 = to_screen.call(cell)
		var col := Color(CyberTheme.AMBER if int(editor.blueprint.armor[key]) >= ShipBlueprint.PLATE_THICK_MM else CyberTheme.CYAN, 0.8)
		var w := maxf(px * 0.12, 1.5)
		match cf[1]:
			&"dorsal":
				draw_line(r.position, Vector2(r.end.x, r.position.y), col, w)
			&"ventral":
				draw_line(Vector2(r.position.x, r.end.y), r.end, col, w)
			&"fore", &"aft":
				if mode == Mode.SIDE:
					var x := r.end.x if cf[1] == &"fore" else r.position.x
					draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), col, w)
			&"port", &"starboard":
				if mode == Mode.FRONT:
					var x2 := r.end.x if cf[1] == &"port" else r.position.x
					draw_line(Vector2(x2, r.position.y), Vector2(x2, r.end.y), col, w)
	for i in editor.blueprint.equipment.size():
		var def := grid.equipment_def(i)
		var e := editor.blueprint.equipment[i]
		if def == null or not def.is_external():
			continue
		var r: Rect2 = to_screen.call(e.cell)
		var n := Vector3(ShipGrid.FACE_NORMALS.get(e.face, Vector3i.ZERO))
		var dir := Vector2(-n.z, -n.y) if mode == Mode.SIDE else Vector2(-n.x, -n.y)
		draw_circle(r.get_center() + dir * px * 0.55, maxf(px * 0.18, 2.0), def.color)


## Silhouette of a wedge cell in this view: the cell square clipped to where
## the wedge is solid at any depth across the cell.
func _wedge_profile(grid: ShipGrid, mi: int, cell: Vector3i, r: Rect2) -> PackedVector2Array:
	# Screen corner → grid point (cell units) at depth `d` ∈ [0, 1] across the view.
	var to_grid := func(p: Vector2, d: float) -> Vector3:
		var u := (p.x - r.position.x) / r.size.x   # 0 = left of the square
		var v := (p.y - r.position.y) / r.size.y   # 0 = top
		var y := cell.y + 1.0 - v
		if mode == Mode.SIDE:
			return Vector3(cell.x + d, y, cell.z + 1.0 - u)   # nose right: left = aft
		return Vector3(cell.x + 1.0 - u, y, cell.z + d)       # from ahead: left = starboard
	var solid := func(p: Vector2) -> bool:
		var q := r.get_center() + (p - r.get_center()) * 0.98
		for d in [0.05, 0.5, 0.95]:
			if grid.wedge_contains(mi, to_grid.call(q, d)):
				return true
		return false
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var out := PackedVector2Array()
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var ia: bool = solid.call(a)
		if ia:
			out.append(a)
		if ia != solid.call(b):
			var lo := a
			var hi := b
			for i in 16:
				var mid := (lo + hi) * 0.5
				if solid.call(mid) == ia:
					lo = mid
				else:
					hi = mid
			out.append((lo + hi) * 0.5)
	return out
