class_name SystemMap
extends Control
## The shipyard's map: every known location as its body's disc — the
## planets in a row out from the Sun, moons above their planets — the one
## the vessel is docked at ringed in gold, the course for the next launch
## ringed in cyan with a line to it, the one under the pointer in faint
## cyan. Each disc has its body's name; the docked, course and pointed-at
## places get their station, orbit, jump cost and real distance (at the
## scenario date, Location.distance_m) in the corner, so eleven places
## don't bury each other's labels. Saturn has its rings. Clicking a
## location emits `picked` (it sets the course; LAUNCH jumps). Sizes and
## spacing are not to scale.

signal picked(location_id: String)

## Location ids on the map (PlayerProfile.known_locations).
var known: Array = []
## The docked location's id.
var docked: String = ""
## Location id -> a short line under its name (the jump's cost).
var notes: Dictionary = {}
## The course: where the next launch jumps to ("" or `docked` = stay).
var target: String = ""

var _hover: String = ""

const REFERENCE_WIDTH := 360.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 340)  # two rows of discs and the info block
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true  # the Sun's glow at the left edge stays on the map
	tooltip_text = "Click a location to set the next sortie's course — LAUNCH jumps there"


func set_state(known_ids: Array, docked_id: String, note_by_id: Dictionary = {}, target_id: String = "") -> void:
	known = known_ids
	docked = docked_id
	notes = note_by_id
	target = target_id
	queue_redraw()


## Screen centre and radius of a location's disc.
func disc(loc: Location) -> Array:
	var k := clampf(size.x / REFERENCE_WIDTH, 0.6, 1.6)
	return [loc.map_position * size, loc.map_radius_px * k]


## The known location under `p`, or null.
func location_at(p: Vector2) -> Location:
	for loc in _locations():
		var d: Array = disc(loc)
		if p.distance_to(d[0]) <= float(d[1]) + 10.0:
			return loc
	return null


func _locations() -> Array[Location]:
	var out: Array[Location] = []
	for loc in Location.all():
		if loc.id in known:
			out.append(loc)
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var loc := location_at(event.position)
		var id := loc.id if loc != null else ""
		if id != _hover:
			_hover = id
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var loc := location_at(event.position)
		if loc != null:
			picked.emit(loc.id)
			accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), CyberTheme.BG)
	var font := ThemeDB.fallback_font
	var locs := _locations()
	var dock := Location.by_id(docked)
	var course := Location.by_id(target) if target != "" else dock
	var hover := Location.by_id(_hover) if _hover != "" else null
	# The Sun at the left edge, and the line of the planets' orbits.
	var row_y := size.y * 0.66
	draw_circle(Vector2(-size.y * 0.2, row_y), size.y * 0.24, Color(1.0, 0.86, 0.5, 0.25))
	draw_line(Vector2(0, row_y), Vector2(size.x, row_y), CyberTheme.TEXT_FAINT * Color(1, 1, 1, 0.35), 1.0)
	# The course: a line from the berth to where the next launch jumps.
	if course != dock and dock in locs and course in locs:
		draw_line(disc(dock)[0], disc(course)[0], CyberTheme.CYAN, 2.0, true)
	if hover != null and hover != dock and hover != course and dock in locs:
		draw_dashed_line(disc(dock)[0], disc(hover)[0], CyberTheme.TEXT_DIM, 1.0, 6.0)
	for loc in locs:
		var d: Array = disc(loc)
		var c: Vector2 = d[0]
		var r: float = d[1]
		if loc.body.has_rings():
			_draw_ring(c, r, false)
		draw_circle(c, r, loc.map_color)
		# Terminator: the night half a little darker.
		draw_arc(c, r * 0.5, -PI * 0.5, PI * 0.5, 24, loc.map_color.darkened(0.45), r, true)
		if loc.body.has_rings():
			_draw_ring(c, r, true)
		if loc.id == docked:
			draw_arc(c, r + 6.0, 0.0, TAU, 48, CyberTheme.AMBER, 2.0, true)
		if loc == course and course != dock:
			draw_arc(c, r + 10.0, 0.0, TAU, 48, CyberTheme.CYAN, 2.5, true)
		elif loc == hover and loc.id != docked:
			draw_arc(c, r + 6.0, 0.0, TAU, 48, CyberTheme.CYAN, 1.5, true)
		var col := CyberTheme.AMBER if loc.id == docked else (CyberTheme.CYAN if loc == course or loc == hover else CyberTheme.TEXT)
		var label := loc.map_name()
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, CyberTheme.SIZE_SMALL).x
		draw_string(font, c + Vector2(-w * 0.5, r + 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, CyberTheme.SIZE_SMALL, col)
	# The details, top left: the berth, the course, the place pointed at.
	var y := 18.0
	var shown := []
	for spec in [[dock, "DOCKED", CyberTheme.AMBER], [course, "COURSE", CyberTheme.CYAN], [hover, "", CyberTheme.CYAN]]:
		var loc: Location = spec[0]
		if loc == null or loc in shown or loc not in locs:
			continue
		shown.append(loc)
		var head := "%s%s · %s · %.0f km" % ["%s  " % spec[1] if spec[1] != "" else "", loc.station_name.to_upper(), loc.display_name, loc.start_altitude_m / 1000.0]
		if loc != dock:
			head += " · %s away" % distance_text(Location.distance_m(dock, loc))
		draw_string(font, Vector2(10, y), head, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, CyberTheme.SIZE_SMALL, spec[2])
		y += 15.0
		if notes.has(loc.id):
			draw_string(font, Vector2(22, y), str(notes[loc.id]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 30.0, CyberTheme.SIZE_SMALL, CyberTheme.TEXT_DIM)
			y += 15.0


## Saturn's rings round a disc: the back half under it, the front over it.
func _draw_ring(c: Vector2, r: float, front: bool) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := (PI if front else 0.0) + PI * k / 24.0
		pts.append(c + Vector2(cos(a) * r * 2.1, sin(a) * r * 0.55).rotated(-0.35))
	draw_polyline(pts, Color(0.86, 0.78, 0.62, 0.9), maxf(2.0, r * 0.18), true)


## "384 400 km", or "229 million km" past a billion metres.
static func distance_text(m: float) -> String:
	if m >= 1.0e9:
		return "%s million km" % _thousands(roundi(m / 1.0e9))
	return "%s km" % _thousands(roundi(m / 1000.0))


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
