class_name RadarDisplay
extends Control
## Flat radar: the player's own horizontal plane seen from above, ahead = up.
## A contact sits at its bearing and horizontal range; a stalk rises or drops
## to show height above/below the plane; a short tail shows its motion
## relative to the player; the label gives range, elevation and closure.

const COLOR_BG := Color(0.03, 0.05, 0.08, 0.72)
const COLOR_RING := Color(0.35, 0.65, 0.9, 0.5)
const COLOR_SELF := Color(0.85, 0.9, 1.0, 0.9)
## Tail length = this many seconds of relative motion (clamped).
const TAIL_SECONDS := 20.0

## Each: {rel_body: Vector3, rel_vel_body: Vector3, range_rate: float, color: Color}
var contacts: Array[Dictionary] = []
var scale_m: float = 5000.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r, COLOR_BG)
	draw_arc(c, r, 0.0, TAU, 64, COLOR_RING, 1.5)
	draw_arc(c, r * 0.5, 0.0, TAU, 48, COLOR_RING * Color(1, 1, 1, 0.6), 1.0)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), COLOR_RING * Color(1, 1, 1, 0.4), 1.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), COLOR_RING * Color(1, 1, 1, 0.4), 1.0)
	draw_string(font, c + Vector2(-r + 4, -r + 14), HudFormat.distance(scale_m),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_RING)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(-5, 5)]), COLOR_SELF)

	for contact in contacts:
		var rel: Vector3 = contact.rel_body
		var color: Color = contact.color
		var base := c + RadarMath.plot(rel, scale_m) * r
		var tip := base + Vector2(0, -clampf(rel.y / scale_m, -1.0, 1.0) * r)
		draw_line(base, tip, color * Color(1, 1, 1, 0.6), 1.5)
		draw_circle(base, 1.5, color * Color(1, 1, 1, 0.6))
		var v: Vector3 = contact.rel_vel_body
		var tail := (Vector2(v.x, v.z) / scale_m * r * TAIL_SECONDS).limit_length(r * 0.35)
		draw_line(tip, tip + tail, color * Color(1, 1, 1, 0.8), 1.0)
		if rel.y >= 0.0:
			draw_circle(tip, 4.0, color)
		else:
			draw_arc(tip, 4.0, 0.0, TAU, 12, color, 1.5)  # hollow = below the plane
		var rr: float = contact.range_rate
		var text := "%s %+.0f° %s" % [HudFormat.distance(rel.length()), RadarMath.elevation_deg(rel),
			"▼" if rr < -0.05 else ("▲" if rr > 0.05 else "■")]
		draw_string(font, tip + Vector2(7, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
