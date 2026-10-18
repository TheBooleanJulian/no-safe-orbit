class_name HudOverlay
extends Control
## World-space markers drawn in screen space: heading reticle, prograde /
## retrograde (velocity is NOT heading in space), target bracket with an
## edge arrow when off-screen, and the mouse virtual-stick indicator.

const COLOR_HEADING := Color(0.85, 0.9, 1.0, 0.85)
const COLOR_PROGRADE := Color(0.35, 1.0, 0.55, 0.95)
const COLOR_TARGET := Color(1.0, 0.45, 0.3, 0.95)
const COLOR_STICK := Color(0.85, 0.9, 1.0, 0.5)
const MARKER_DISTANCE_M := 5000.0
const EDGE_MARGIN := 48.0
const MIN_PROGRADE_SPEED := 0.5

var camera: Camera3D
var ship_render_pos := Vector3.ZERO
var ship_forward := Vector3.FORWARD
var ship_velocity := Vector3.ZERO
var has_target := false
var target_render_pos := Vector3.ZERO
var target_label := ""
var mouse_stick := Vector2.ZERO


func _draw() -> void:
	if camera == null:
		return
	var font := ThemeDB.fallback_font
	var center := size * 0.5

	# Mouse virtual stick around screen centre.
	draw_arc(center, 60.0, 0.0, TAU, 48, COLOR_STICK, 1.0)
	if mouse_stick.length() > 0.01:
		var tip := center + Vector2(mouse_stick.x, -mouse_stick.y) * 60.0
		draw_line(center, tip, COLOR_STICK, 1.5)
		draw_circle(tip, 3.0, COLOR_STICK)

	# Heading: where the nose points.
	var heading_pt := ship_render_pos + ship_forward * MARKER_DISTANCE_M
	if not camera.is_position_behind(heading_pt):
		var p := camera.unproject_position(heading_pt)
		draw_line(p + Vector2(-18, 0), p + Vector2(-6, 0), COLOR_HEADING, 2.0)
		draw_line(p + Vector2(6, 0), p + Vector2(18, 0), COLOR_HEADING, 2.0)
		draw_line(p + Vector2(0, 6), p + Vector2(0, 14), COLOR_HEADING, 2.0)
		draw_circle(p, 2.0, COLOR_HEADING)

	# Prograde / retrograde: where the ship is actually going.
	if ship_velocity.length() > MIN_PROGRADE_SPEED:
		var dir := ship_velocity.normalized()
		var pro := ship_render_pos + dir * MARKER_DISTANCE_M
		var retro := ship_render_pos - dir * MARKER_DISTANCE_M
		if not camera.is_position_behind(pro):
			var p := camera.unproject_position(pro)
			draw_arc(p, 9.0, 0.0, TAU, 24, COLOR_PROGRADE, 2.0)
			draw_line(p + Vector2(9, 0), p + Vector2(17, 0), COLOR_PROGRADE, 2.0)
			draw_line(p + Vector2(-9, 0), p + Vector2(-17, 0), COLOR_PROGRADE, 2.0)
			draw_line(p + Vector2(0, -9), p + Vector2(0, -17), COLOR_PROGRADE, 2.0)
		if not camera.is_position_behind(retro):
			var q := camera.unproject_position(retro)
			draw_arc(q, 9.0, 0.0, TAU, 24, COLOR_PROGRADE, 2.0)
			draw_line(q + Vector2(-6, -6), q + Vector2(6, 6), COLOR_PROGRADE, 2.0)
			draw_line(q + Vector2(-6, 6), q + Vector2(6, -6), COLOR_PROGRADE, 2.0)

	# Target bracket or edge arrow.
	if has_target:
		var on_screen := false
		var tp := Vector2.ZERO
		if not camera.is_position_behind(target_render_pos):
			tp = camera.unproject_position(target_render_pos)
			on_screen = _inner_rect().has_point(tp)
		if on_screen:
			_draw_bracket(tp, 16.0)
			draw_string(font, tp + Vector2(22, -6), target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TARGET)
		else:
			_draw_edge_arrow(center, font)


## Screen area treated as "on screen"; collapses safely on tiny viewports.
func _inner_rect() -> Rect2:
	var margin := minf(EDGE_MARGIN, minf(size.x, size.y) * 0.25)
	return Rect2(Vector2.ZERO, size).grow(-margin).abs()


func _draw_bracket(p: Vector2, r: float) -> void:
	var l := r * 0.5
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := p + Vector2(sx * r, sy * r)
			draw_line(corner, corner - Vector2(sx * l, 0), COLOR_TARGET, 2.0)
			draw_line(corner, corner - Vector2(0, sy * l), COLOR_TARGET, 2.0)


func _draw_edge_arrow(center: Vector2, font: Font) -> void:
	# Direction to the target in camera space, flattened onto the screen.
	var local := camera.global_transform.affine_inverse() * target_render_pos
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 1e-3:
		dir = Vector2.DOWN  # dead astern: point down by convention
	dir = dir.normalized()
	var half := _inner_rect().size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
	var tip := center + dir * t
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 18.0 + side * 9.0, tip - dir * 18.0 - side * 9.0]), COLOR_TARGET)
	# Place the label just inward of the arrow, centred on the arrow's axis.
	var text_size := font.get_string_size(target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var reach := 26.0 + text_size.x * 0.5 * absf(dir.x) + text_size.y * 0.5 * absf(dir.y)
	var label_center := tip - dir * reach
	draw_string(font, label_center + Vector2(-text_size.x * 0.5, text_size.y * 0.3),
		target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TARGET)
