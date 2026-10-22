class_name Location
extends Resource
## A place to fly from: a station in orbit about one central body (the
## body's gravity is the only gravity there). Players pick one on the
## shipyard map; the sortie starts in its orbit and the jump drive brings
## the ship back to its station. Data lives in data/locations/*.tres.
## Moving between locations costs jump propellant (JumpDrive, by distance
## and mass); each station has its own shelves, prices and local traffic.

## Every location's file, in map order. Listed here (not scanned from the
## folder) so exported builds find them.
const FILES := [
	"res://data/locations/earth_orbit.tres",
	"res://data/locations/moon_orbit.tres",
	"res://data/locations/mars_orbit.tres",
	"res://data/locations/phobos_orbit.tres",
	"res://data/locations/deimos_orbit.tres",
	"res://data/locations/mercury_orbit.tres",
	"res://data/locations/venus_orbit.tres",
	"res://data/locations/jupiter_orbit.tres",
	"res://data/locations/saturn_orbit.tres",
	"res://data/locations/uranus_orbit.tres",
	"res://data/locations/neptune_orbit.tres",
]
const DEFAULT_ID := "earth"

static var _all: Array[Location] = []

@export var id: String = DEFAULT_ID
## Map label, e.g. "Earth orbit".
@export var display_name: String = ""
## The body's name under its disc on the map, e.g. "Earth".
@export var short_name: String = ""
## The station's name, e.g. "Earth Shipyard".
@export var station_name: String = ""
@export var body: OrbitalBody
## The other body drawn in this location's sky (Earth's Moon, the Moon's
## Earth; none at Mars, where Earth is a point of light).
@export var sky_body: OrbitalBody
## Circular, prograde start orbit (m above the mean radius), equatorial
## unless inclined (Saturn's 20°, to see its rings from above).
@export var start_altitude_m: float = 400_000.0
@export var start_inclination_deg: float = 0.0
## Where it sits on the map (0–1 across, 0–1 down).
@export var map_position := Vector2(0.5, 0.5)
## Map size of the body's disc (px at the map's reference width) and colour.
@export var map_radius_px: float = 24.0
@export var map_color := Color(0.5, 0.5, 0.5)
## One line for the map.
@export_multiline var blurb: String = ""

@export_group("Broker")
## What an information broker charges for the charts (credits); 0 for a
## location known from the start (PlayerProfile.STARTING_LOCATIONS).
@export var broker_price: int = 0
## The location whose charts a broker needs you to have first (Milestone
## 16: the outer planets one by one; "" for none).
@export var charts_after: String = ""
@export var broker_name: String = ""
@export_multiline var broker_pitch: String = ""

@export_group("Station")
## The quartermaster: how many items, the rarest tier stocked, and a price
## factor on the standard prices (also on hiring fees).
@export var vendor_stock_size: int = 3
@export var vendor_max_rarity: int = Rarity.Tier.EPIC
@export var price_factor: float = 1.0

@export_group("Encounters")
## Blueprint files (data/blueprints/) the local traffic is built on, and
## their weights; each ship of an encounter rolls one.
@export var enemy_templates: PackedStringArray = PackedStringArray(["frigate_mk1.json"])
@export var enemy_weights: PackedFloat32Array = PackedFloat32Array([1.0])
## Added to the mission number when arming the local traffic.
@export var threat_bonus: int = 0


## A deep-space survey's place: the Sun at the centre, no station of its
## own (the jump home goes back to `home`'s station), no local traffic.
static func deep_space(home: Location) -> Location:
	var loc := Location.new()
	loc.id = "deep_space"
	loc.display_name = "Deep space"
	loc.station_name = home.station_name
	loc.body = load("res://data/bodies/sun.tres") as OrbitalBody
	loc.enemy_templates = PackedStringArray()
	return loc


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
	for loc in all():
		if loc.id == DEFAULT_ID:
			return loc
	return all()[0]


## The map label under the disc.
func map_name() -> String:
	return short_name if short_name != "" else display_name


## Jump distance between two locations (m): their bodies' real separation
## at the scenario date (CelestialFrame, double precision).
static func distance_m(a: Location, b: Location) -> float:
	return CelestialFrame.separation_m(a.body.ephemeris, b.body.ephemeris,
		CelestialFrame.julian_date_from_iso(Main.SCENARIO_EPOCH_UTC))


## The template file for ship `index` of an encounter at `mission`
## (seeded: the same mission and slot always roll the same).
func enemy_template(mission: int, index: int) -> String:
	if enemy_templates.size() <= 1:
		return enemy_templates[0] if enemy_templates.size() == 1 else "frigate_mk1.json"
	var rng := RandomNumberGenerator.new()
	rng.seed = 92_821 * mission + 613 * index + hash(id)
	var total := 0.0
	for i in enemy_templates.size():
		total += enemy_weights[i] if i < enemy_weights.size() else 1.0
	var roll := rng.randf() * total
	for i in enemy_templates.size():
		roll -= enemy_weights[i] if i < enemy_weights.size() else 1.0
		if roll <= 0.0:
			return enemy_templates[i]
	return enemy_templates[enemy_templates.size() - 1]


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
	if enemy_templates.is_empty():
		problems.append("%s: no enemy templates" % id)
	for f in enemy_templates:
		if not FileAccess.file_exists("res://data/blueprints/" + f):
			problems.append("%s: enemy template %s missing" % [id, f])
	if vendor_stock_size < 0 or price_factor <= 0.0:
		problems.append("%s: bad quartermaster settings" % id)
	if charts_after != "" and by_id(charts_after).id != charts_after:
		problems.append("%s: its charts come after an unknown location %s" % [id, charts_after])
	return problems
