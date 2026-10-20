class_name SystemMap
extends Control
## The shipyard's map: every known location as its body's disc, the one the
## vessel is docked at ringed in gold and the one under the pointer in cyan.
## Clicking a location emits `picked`. Distances are not to scale (the Moon
## is ~384 000 km out); the line between bodies is labelled with the real
## figure.

signal picked(location_id: String)

## Location ids on the map (PlayerProfile.known_locations).
var known: Array = []
## The docked location's id.
var docked: String = ""
## Location id -> a short line under its name (the jump's cost).
var notes: Dictionary = {}

var _hover: String = ""

const REFERENCE_WIDTH := 360.0
const EARTH_MOON_KM := 384_400


func _ready() -> void:
	custom_minimum_size = Vector2(0, 320)  # discs plus three label lines
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Click a location to move the vessel to its station"


func set_state(known_ids: Array, docked_id: String, note_by_id: Dictionary = {}) -> void:
	known = known_ids
	docked = docked_id
	notes = note_by_id
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
	# Earth–Moon line, with the real distance.
	var earth := Location.by_id("earth")
	var moon := Location.by_id("moon")
	if earth in locs and moon in locs:
		var a: Vector2 = disc(earth)[0]
		var b: Vector2 = disc(moon)[0]
		draw_dashed_line(a, b, CyberTheme.TEXT_FAINT, 1.0, 6.0)
		draw_string(font, (a + b) * 0.5 + Vector2(-40, -8), "%s km" % _thousands(EARTH_MOON_KM),
			HORIZONTAL_ALIGNMENT_LEFT, -1, CyberTheme.SIZE_SMALL, CyberTheme.TEXT_DIM)
	for loc in locs:
		var d: Array = disc(loc)
		var c: Vector2 = d[0]
		var r: float = d[1]
		draw_circle(c, r, loc.map_color)
		# Terminator: the night half a little darker.
		draw_arc(c, r * 0.5, -PI * 0.5, PI * 0.5, 24, loc.map_color.darkened(0.45), r, true)
		if loc.id == docked:
			draw_arc(c, r + 6.0, 0.0, TAU, 48, CyberTheme.AMBER, 2.0, true)
		elif loc.id == _hover:
			draw_arc(c, r + 6.0, 0.0, TAU, 48, CyberTheme.CYAN, 1.5, true)
		var label := loc.station_name.to_upper()
		var col := CyberTheme.AMBER if loc.id == docked else CyberTheme.TEXT
		draw_string(font, c + Vector2(-r, r + 20.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, CyberTheme.SIZE_SMALL, col)
		draw_string(font, c + Vector2(-r, r + 34.0), "%s · %.0f km" % [loc.display_name, loc.start_altitude_m / 1000.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, CyberTheme.SIZE_SMALL, CyberTheme.TEXT_DIM)
		if notes.has(loc.id):
			draw_string(font, c + Vector2(-r, r + 48.0), str(notes[loc.id]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, CyberTheme.SIZE_SMALL, CyberTheme.CYAN if loc.id == _hover else CyberTheme.TEXT_DIM)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
