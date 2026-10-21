class_name Artifact
extends Resource
## A real object in space (Milestone 14): where it is at the scenario epoch,
## from NASA/JPL Horizons, and what surveying it gives. Data lives in
## data/artifacts/*.tres (sources and uncertainty in data/ATTRIBUTION.md).
##
## A survey sortie starts a few kilometres from the object, in its real orbit
## (about its body, or about the Sun for deep-space objects). Close in, match
## its speed and hold there with a working sensor to survey it: its record
## goes into the codex and the survey fee is paid. Real objects are heritage:
## look, don't touch — they can't be damaged, grappled or salvaged.

## Every artifact's file, in list order. Listed here (not scanned) so
## exported builds find them.
const FILES := [
	"res://data/artifacts/iss.tres",
	"res://data/artifacts/hubble.tres",
	"res://data/artifacts/lro.tres",
	"res://data/artifacts/mro.tres",
	"res://data/artifacts/odyssey.tres",
	"res://data/artifacts/roadster.tres",
	"res://data/artifacts/new_horizons.tres",
	"res://data/artifacts/voyager2.tres",
	"res://data/artifacts/pioneer11.tres",
	"res://data/artifacts/pioneer10.tres",
	"res://data/artifacts/voyager1.tres",
]
## How long the survey takes, held within range and speed (s).
const SURVEY_S := 20.0
## Close enough: this, or five times the object's size if larger (m).
const SURVEY_RANGE_M := 500.0
## Slow enough relative to it (m/s): docking-approach tolerances.
const SURVEY_SPEED_MPS := 2.0
## Where a survey sortie starts: this far behind it along its track (m).
const START_BEHIND_M := 3000.0

static var _all: Array[Artifact] = []

@export var id: String = ""
@export var display_name: String = ""
## &"station", &"telescope", &"orbiter", &"probe" or &"car" (its model).
@export var kind: StringName = &"probe"
## The central body's ephemeris id: &"earth", &"moon", &"mars" or &"sun".
@export var center: StringName = &"earth"
## Horizons state at `epoch_utc`, ICRF axes about `center` (km, km/s).
@export var epoch_utc: String = "2026-10-19T12:00:00"
@export var r_km := PackedFloat64Array([0.0, 0.0, 0.0])
@export var v_km_s := PackedFloat64Array([0.0, 0.0, 0.0])
## Horizons target id and trajectory source, as Horizons reported them.
@export var horizons_id: String = ""
@export var horizons_source: String = ""
## How far to trust the position (one line, shown with the record).
@export var uncertainty: String = ""
## Overall size (m, its longest dimension) and mass (kg).
@export var size_m: float = 5.0
@export var mass_kg: float = 1000.0
## The survey fee (credits) and the record unlocked in the codex.
@export var survey_credits: int = 200
@export var launched: String = ""
@export_multiline var lore: String = ""


static func all() -> Array[Artifact]:
	if _all.is_empty():
		for f in FILES:
			_all.append(load(f) as Artifact)
	return _all


## The artifact with this id, or null.
static func by_id(artifact_id: String) -> Artifact:
	for a in all():
		if a.id == artifact_id:
			return a
	return null


func is_deep_space() -> bool:
	return center == &"sun"


## The location it is surveyed from (a body's location), or null in deep space.
func location() -> Location:
	if is_deep_space():
		return null
	for loc in Location.all():
		if loc.body.ephemeris == center:
			return loc
	return null


## Its orbit in a line (play-test batch 9), once surveyed: "427 × 418 km,
## 51.6° incl, Earth orbit"; about the Sun in AU against the ecliptic;
## an object on its way out of the solar system as escaping.
func orbit_summary() -> String:
	var st := state_icrs()
	var body: OrbitalBody
	var pole: Vector3
	var where := ""
	if is_deep_space():
		body = load("res://data/bodies/sun.tres") as OrbitalBody
		var eps := deg_to_rad(CelestialFrame.OBLIQUITY_J2000_DEG)
		pole = Vector3(0.0, -sin(eps), cos(eps))
		where = "solar orbit"
	else:
		body = location().body
		pole = CelestialFrame.orientation(body, CelestialFrame.julian_date_from_iso(epoch_utc))[0]
		where = "%s orbit" % body.display_name
	var el := OrbitElements.from_state(body.mu_m3_s2, st[0], st[1])
	var inc := rad_to_deg(st[0].cross(st[1]).normalized().to_vector3().angle_to(pole))
	if is_deep_space():
		if not el.is_bound():
			return "escaping, perihelion %.2f AU · %.1f° incl · %s" % [el.periapsis_radius / CelestialFrame.AU_M, inc, where]
		return "%.2f × %.2f AU · %.1f° incl · %s" % [el.apoapsis_radius / CelestialFrame.AU_M, el.periapsis_radius / CelestialFrame.AU_M, inc, where]
	return "%.0f × %.0f km · %.1f° incl · %s" % [(el.apoapsis_radius - body.radius_m) / 1000.0, (el.periapsis_radius - body.radius_m) / 1000.0, inc, where]


## Before a survey: what the record will hold, unknown.
func orbit_unknown() -> String:
	if is_deep_space():
		return "??? × ??? AU · ???° incl · solar orbit"
	return "??? × ??? km · ???° incl · %s orbit" % location().body.display_name


## Position and velocity about its central body (ICRS axes, m and m/s).
func state_icrs() -> Array[Vec3d]:
	return [Vec3d.new(r_km[0], r_km[1], r_km[2]).times(1000.0), Vec3d.new(v_km_s[0], v_km_s[1], v_km_s[2]).times(1000.0)]


## Its heliocentric position at the epoch (m, double precision).
func heliocentric_icrs() -> Vec3d:
	var jd := CelestialFrame.julian_date_from_iso(epoch_utc)
	return CelestialFrame.heliocentric_icrs(center, jd).plus(state_icrs()[0])


## Jump distance (m) from a location's body to it: zero within its own
## location (a survey there is an ordinary sortie).
func distance_from(loc: Location) -> float:
	if not is_deep_space() and loc.body.ephemeris == center:
		return 0.0
	var jd := CelestialFrame.julian_date_from_iso(epoch_utc)
	return heliocentric_icrs().minus(CelestialFrame.heliocentric_icrs(loc.body.ephemeris, jd)).length()


func survey_range_m() -> float:
	return maxf(SURVEY_RANGE_M, 5.0 * size_m)


## A craft-like config for the world: its size and mass, no engines, and
## no hull points (it can't be damaged).
func ship_config() -> ShipConfig:
	var c := ShipConfig.new()
	c.display_name = display_name
	c.mass_kg = mass_kg
	c.hull_hp = 0.0
	var h := size_m * 0.5
	c.hit_box_center = Vector3.ZERO
	c.hit_box_half_extents = Vector3(h, h * 0.5, h) if kind == &"station" else Vector3(h * 0.5, h * 0.5, h)
	var i := mass_kg * h * h / 3.0
	c.inertia_kgm2 = Vector3(i, i, i)
	c.thrust_forward_n = 0.0
	c.thrust_reverse_n = 0.0
	c.thrust_lateral_n = 0.0
	c.thrust_vertical_n = 0.0
	c.max_torque_nm = Vector3.ZERO
	c.cannon_muzzles_body = PackedVector3Array()
	c.unlimited_propellant = true
	return c


## Problems with the data ([] when good).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == "" or display_name == "" or lore == "":
		problems.append("%s: id, name and record are required" % id)
	if r_km.size() != 3 or v_km_s.size() != 3:
		problems.append("%s: state vector must have three components each" % id)
	if center not in [&"earth", &"moon", &"mars", &"sun"]:
		problems.append("%s: unknown central body %s" % [id, center])
	if horizons_source == "" or uncertainty == "":
		problems.append("%s: source and uncertainty must be recorded" % id)
	if size_m <= 0.0 or mass_kg <= 0.0 or survey_credits < 0:
		problems.append("%s: bad size, mass or fee" % id)
	return problems
