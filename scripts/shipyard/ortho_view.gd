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
		var def := grid.module_def(grid.module_at[cell])
		draw_rect((to_screen.call(cell) as Rect2).grow(-0.5), def.color.darkened(0.35))
	for i in editor.blueprint.equipment.size():
		var def := grid.equipment_def(i)
		var e := editor.blueprint.equipment[i]
		if def == null or not def.is_external():
			continue
		var r: Rect2 = to_screen.call(e.cell)
		var n := Vector3(ShipGrid.FACE_NORMALS.get(e.face, Vector3i.ZERO))
		var dir := Vector2(-n.z, -n.y) if mode == Mode.SIDE else Vector2(-n.x, -n.y)
		draw_circle(r.get_center() + dir * px * 0.55, maxf(px * 0.18, 2.0), def.color)
