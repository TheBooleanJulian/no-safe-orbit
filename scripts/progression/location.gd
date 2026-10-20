class_name Location
extends Resource
## A place to fly from: a station in orbit about one central body (the
## body's gravity is the only gravity there). Players pick one on the
## shipyard map; the sortie starts in its orbit and the jump drive brings
## the ship back to its station. Data lives in data/locations/*.tres.
## Jump costs, brokers that unlock locations and per-station stock are
## Milestone 13; for now moving between known locations is free.

## Every location's file, in map order. Listed here (not scanned from the
## folder) so exported builds find them.
const FILES := [
	"res://data/locations/earth_orbit.tres",
	"res://data/locations/moon_orbit.tres",
]
const DEFAULT_ID := "earth"

static var _all: Array[Location] = []

@export var id: String = DEFAULT_ID
## Map label, e.g. "Earth orbit".
@export var display_name: String = ""
## The station's name, e.g. "Earth Shipyard".
@export var station_name: String = ""
@export var body: OrbitalBody
## Circular, prograde, equatorial start orbit (m above the mean radius).
@export var start_altitude_m: float = 400_000.0
## Where it sits on the map (0–1 across, 0–1 down).
@export var map_position := Vector2(0.5, 0.5)
## Map size of the body's disc (px at the map's reference width) and colour.
@export var map_radius_px: float = 24.0
@export var map_color := Color(0.5, 0.5, 0.5)
## One line for the map.
@export_multiline var blurb: String = ""


## Every location, in map order.
static func all() -> Array[Location]:
	if _all.is_empty():
		for f in FILES:
			_all.append(load(f) as Location)
	return _all


## The location with this id (Earth's if unknown).
static func by_id(location_id: String) -> Location:
	for loc in all():
		if loc.id == location_id:
			return loc
	return all()[0]


func start_radius_m() -> float:
	return body.radius_m + start_altitude_m


## Problems with the data ([] when good).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == "" or station_name == "" or display_name == "":
		problems.append("%s: id, display name and station name are required" % id)
	if body == null:
		problems.append("%s: no central body" % id)
		return problems
	problems.append_array(body.validate())
	if start_altitude_m <= body.entry_interface_altitude_m:
		problems.append("%s: the start orbit is below the entry interface" % id)
	return problems
