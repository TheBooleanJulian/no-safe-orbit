class_name HudOverlay
extends Control
## World-space markers drawn in screen space: heading reticle, orbital
## prograde / retrograde (velocity is NOT heading in space), projected orbit
## path with apsis and entry markers, target bracket with an edge arrow when
## off-screen, the lead (fire-control) pip, and the mouse aim cursor.

const COLOR_HEADING := Color(0.0, 0.94, 1.0, 0.9)
const COLOR_PROGRADE := Color(0.35, 1.0, 0.55, 0.95)
## Prograde/retrograde relative to the target (match-velocity mode).
const COLOR_TARGET_RELATIVE := Color(1.0, 0.86, 0.2, 0.95)
const COLOR_PATH := Color(0.35, 1.0, 0.55, 0.45)
const COLOR_TARGET := Color(1.0, 0.17, 0.84, 0.95)
const COLOR_LEAD := Color(1.0, 0.8, 0.35, 0.95)
const COLOR_AIM := Color(0.0, 0.94, 1.0, 0.75)
const MARKER_DISTANCE_M := 5000.0
const EDGE_MARGIN := 48.0
const MIN_PROGRADE_SPEED := 0.5

var camera: Camera3D
var ship_render_pos := Vector3.ZERO
var ship_forward := Vector3.FORWARD
## Direction the ship is actually moving (orbital velocity when in orbit).
var ship_velocity := Vector3.ZERO
## True: ship_velocity is relative to the target (match-velocity mode) and
## the markers are yellow and labelled TGT.
var velocity_relative_to_target := false
var has_target := false
var target_render_pos := Vector3.ZERO
var target_label := ""
## The bracket marks a dead-reckoned estimate, not a measurement: dashed, dim.
var target_estimated := false
## Lead markers for the ship's other gun types: {pos (render space), label}.
var extra_leads: Array[Dictionary] = []
var has_lead := false
var lead_render_pos := Vector3.ZERO
var lead_label := ""
## Where the mouse aims (screen px); the turrets train on it.
var aim_point := Vector2.ZERO
## Craft in sensor range: {pos (render), label, hostile, selected}.
var craft_markers: Array[Dictionary] = []
## One per gun: {pos: Vector3 (render space), status: ShipState.Turret, label}.
var gun_reticles: Array[Dictionary] = []
## Projected orbit, render space; occluded where the planet is in the way.
var orbit_path := PackedVector3Array()
## Labelled points on the path: [{pos: Vector3, text: String, color: Color}].
var orbit_markers: Array[Dictionary] = []
## Incoming threats (Pass A): {dir (world, unit, from the ship), label,
## danger} — a chevron where it is, or at the screen edge towards it.
var threats: Array[Dictionary] = []
## Added to every orbit_path point and marker: the path is computed a few
## times a second, relative to where the render origin was then.
var orbit_offset := Vector3.ZERO
var planet_center := Vector3.ZERO
var planet_radius := 0.0


func _draw() -> void:
	if camera == null:
		return
	var font := ThemeDB.fallback_font
	var center := size * 0.5

	_draw_orbit_path(font)

	# Aim cursor: an open ring with four ticks.
	draw_arc(aim_point, 11.0, 0.0, TAU, 32, COLOR_AIM, 1.5)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(aim_point + d * 15.0, aim_point + d * 22.0, COLOR_AIM, 1.5)
	_draw_gun_reticles(font)

	# Heading: where the nose points.
	var heading_pt := ship_render_pos + ship_forward * MARKER_DISTANCE_M
	if not camera.is_position_behind(heading_pt):
		var p := camera.unproject_position(heading_pt)
		draw_line(p + Vector2(-18, 0), p + Vector2(-6, 0), COLOR_HEADING, 2.0)
		draw_line(p + Vector2(6, 0), p + Vector2(18, 0), COLOR_HEADING, 2.0)
		draw_line(p + Vector2(0, 6), p + Vector2(0, 14), COLOR_HEADING, 2.0)
		draw_circle(p, 2.0, COLOR_HEADING)

	# Prograde / retrograde: where the ship is actually going — along its
	# orbit (green), or relative to the target in match-velocity mode (yellow).
	var pro_color := COLOR_TARGET_RELATIVE if velocity_relative_to_target else COLOR_PROGRADE
	var min_speed := 0.05 if velocity_relative_to_target else MIN_PROGRADE_SPEED
	if ship_velocity.length() > min_speed:
		var dir := ship_velocity.normalized()
		var pro := ship_render_pos + dir * MARKER_DISTANCE_M
		var retro := ship_render_pos - dir * MARKER_DISTANCE_M
		if not camera.is_position_behind(pro):
			var p := camera.unproject_position(pro)
			draw_arc(p, 9.0, 0.0, TAU, 24, pro_color, 2.0)
			draw_line(p + Vector2(9, 0), p + Vector2(17, 0), pro_color, 2.0)
			draw_line(p + Vector2(-9, 0), p + Vector2(-17, 0), pro_color, 2.0)
			draw_line(p + Vector2(0, -9), p + Vector2(0, -17), pro_color, 2.0)
			if velocity_relative_to_target:
				draw_string(font, p + Vector2(12, 18), "TGT %.1f m/s" % ship_velocity.length(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pro_color)
		if not camera.is_position_behind(retro):
			var q := camera.unproject_position(retro)
			draw_arc(q, 9.0, 0.0, TAU, 24, pro_color, 2.0)
			draw_line(q + Vector2(-6, -6), q + Vector2(6, 6), pro_color, 2.0)
			draw_line(q + Vector2(-6, 6), q + Vector2(6, -6), pro_color, 2.0)

	# Target bracket or edge arrow (line of sight).
	if has_target:
		var on_screen := false
		var tp := Vector2.ZERO
		if not camera.is_position_behind(target_render_pos):
			tp = camera.unproject_position(target_render_pos)
			on_screen = _inner_rect().has_point(tp)
		if on_screen and target_estimated:
			# Estimate: a dashed ring and a "?" — not where the sensors see it.
			var dim := COLOR_TARGET * Color(1, 1, 1, 0.55)
			for k in 8:
				draw_arc(tp, 18.0, TAU * k / 8.0, TAU * (k + 0.5) / 8.0, 6, dim, 1.5)
			draw_string(font, tp + Vector2(22, -6), target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, dim)
		elif on_screen:
			_draw_bracket(tp, 16.0)
			draw_string(font, tp + Vector2(22, -6), target_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TARGET)
		else:
			_draw_edge_arrow(center, font)

	_draw_craft_markers(font)
	_draw_threats(font, center)

	# Lead pip: where to point the nose so rounds meet the target.
	if has_lead:
		for extra in extra_leads:
			var ep: Vector3 = extra.pos
			if camera.is_position_behind(ep):
				continue
			var xp := camera.unproject_position(ep)
			var d2 := 5.0
			draw_polyline(PackedVector2Array([xp + Vector2(0, -d2), xp + Vector2(d2, 0), xp + Vector2(0, d2),
				xp + Vector2(-d2, 0), xp + Vector2(0, -d2)]), COLOR_LEAD * Color(1, 1, 1, 0.75), 1.5)
			draw_string(font, xp + Vector2(7, 4), str(extra.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_LEAD)
	if has_lead and not camera.is_position_behind(lead_render_pos):
		var lp := camera.unproject_position(lead_render_pos)
		if _inner_rect().has_point(lp):
			var d := 8.0
			draw_polyline(PackedVector2Array([lp + Vector2(0, -d), lp + Vector2(d, 0), lp + Vector2(0, d),
				lp + Vector2(-d, 0), lp + Vector2(0, -d)]), COLOR_LEAD, 2.0)
			draw_circle(lp, 1.5, COLOR_LEAD)
			# Below-left, clear of the target bracket and its range label.
			var text_w := font.get_string_size(lead_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, lp + Vector2(-text_w - 12, 24), lead_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_LEAD)


## Threat chevrons: on the threat if it is in view (a ring of four ticks),
## else at the screen edge pointing at it, with its alert line.
func _draw_threats(font: Font, center: Vector2) -> void:
	for t in threats:
		var col := CyberTheme.RED if t.danger else CyberTheme.AMBER
		var world_pt := ship_render_pos + (t.dir as Vector3) * MARKER_DISTANCE_M * 4.0
		var label: String = t.label
		if not camera.is_position_behind(world_pt):
			var p := camera.unproject_position(world_pt)
			if _inner_rect().has_point(p):
				for k in 4:
					var a := TAU * k / 4.0 + PI * 0.25
					var d := Vector2(cos(a), sin(a))
					draw_line(p + d * 12.0, p + d * 22.0, col, 2.5)
				draw_string(font, p + Vector2(24, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
				continue
		var local := camera.global_transform.affine_inverse() * world_pt
		var dir := Vector2(local.x, -local.y)
		dir = dir.normalized() if dir.length() > 1e-3 else Vector2.DOWN
		var half := _inner_rect().size * 0.5 - Vector2(24, 24)
		var reach := minf(half.x / maxf(absf(dir.x), 1e-6), half.y / maxf(absf(dir.y), 1e-6))
		var tip := center + dir * reach
		var side := Vector2(-dir.y, dir.x)
		for k in 2:
			var back := tip - dir * (10.0 + 9.0 * k)
			draw_polyline(PackedVector2Array([back + side * 11.0 - dir * 8.0, back, back - side * 11.0 - dir * 8.0]), col, 3.0)
		var size_t := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var lc := tip - dir * (40.0 + size_t.x * 0.5 * absf(dir.x) + size_t.y * 0.5 * absf(dir.y))
		draw_string(font, lc + Vector2(-size_t.x * 0.5, size_t.y * 0.3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## Craft: a small diamond (magenta hostile, cyan ours) and its range; the
## selected one (U) gets a bracket.
func _draw_craft_markers(font: Font) -> void:
	for m in craft_markers:
		var pos: Vector3 = m.pos
		if camera.is_position_behind(pos):
			continue
		var p := camera.unproject_position(pos)
		if not _inner_rect().has_point(p):
			continue
		var col := COLOR_TARGET if m.hostile else COLOR_AIM
		if m.get("wreck", false):
			col = CyberTheme.TEXT_DIM
		# Our own missiles: small, dim and unlabelled, so a swarm doesn't bury the view.
		var minor: bool = m.get("minor", false)
		var d := 3.5 if minor else 7.0
		if minor:
			col = Color(col, 0.55)
		draw_polyline(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0), p + Vector2(0, -d)]), col, 1.5)
		if m.selected:
			_draw_bracket(p, 12.0)
		if not minor:
			draw_string(font, p + Vector2(10, -8), str(m.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## Each gun's own reticle: a small ring where its barrel points. On target:
## solid cyan; training: dim; blocked by the hull, out of arc, locked or
## offline: grey with a slash (that gun holds fire).
func _draw_gun_reticles(font: Font) -> void:
	for r in gun_reticles:
		var pos: Vector3 = r.pos
		if camera.is_position_behind(pos):
			continue
		var p := camera.unproject_position(pos)
		var status: int = r.status
		var col := COLOR_AIM
		var holding := false
		match status:
			ShipState.Turret.READY:
				col = CyberTheme.CYAN
			ShipState.Turret.SLEWING:
				col = CyberTheme.CYAN * Color(1, 1, 1, 0.45)
			_:
				col = CyberTheme.TEXT_FAINT
				holding = true
		draw_arc(p, 6.0, 0.0, TAU, 20, col, 1.5)
		if holding:
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), col, 1.5)
		else:
			draw_circle(p, 1.5, col)
		draw_string(font, p + Vector2(7, -6), str(r.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _draw_orbit_path(font: Font) -> void:
	var cam := camera.global_position
	var prev := Vector2.ZERO
	var prev_ok := false
	for p0 in orbit_path:
		var point := p0 + orbit_offset
		var ok := _visible(point, cam)
		var sp := camera.unproject_position(point) if ok else Vector2.ZERO
		if ok and prev_ok and prev.distance_to(sp) < size.length():
			draw_line(prev, sp, COLOR_PATH, 1.5, true)
		prev = sp
		prev_ok = ok
	for marker in orbit_markers:
		var pos: Vector3 = marker.pos + orbit_offset
		if not _visible(pos, cam):
			continue
		var p := camera.unproject_position(pos)
		var color: Color = marker.color
		draw_circle(p, 3.5, color)
		draw_string(font, p + Vector2(7, -5), marker.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


## In front of the camera and not hidden behind the planet.
func _visible(point: Vector3, cam: Vector3) -> bool:
	if camera.is_position_behind(point):
		return false
	if planet_radius <= 0.0:
		return true
	var d := point - cam
	var dist := d.length()
	var dir := d / dist
	var oc := cam - planet_center
	var b := oc.dot(dir)
	var disc := b * b - (oc.dot(oc) - planet_radius * planet_radius)
	if disc <= 0.0:
		return true
	var t_hit := -b - sqrt(disc)
	return t_hit <= 0.0 or t_hit >= dist


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
