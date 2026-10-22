class_name OrbitalBody
extends Resource
## A spherical central body for two-body gravity (a = −μ r/|r|³), how it
## turns (for drawing its surface) and how it looks.
## Units: m, m³/s², degrees, days. Data lives in data/bodies/*.tres.

@export var display_name: String = "Unnamed body"
## Standard gravitational parameter GM.
@export var mu_m3_s2: float = 3.986004418e14
## Mean radius of the solid/ocean surface.
@export var radius_m: float = 6_371_000.0
## Altitude of the entry interface. There is no drag model: any trajectory
## that crosses this altitude counts as atmospheric entry and leaves the
## orbital engagement. For Earth this is the 100 km Kármán line; for an
## airless body, the highest terrain plus a margin (crossing it is a crash).
@export var entry_interface_altitude_m: float = 100_000.0
## An atmosphere: limb glow, haze, clouds and sea glint are drawn, and the
## entry interface is atmospheric entry. Off: bare rock, and terrain.
@export var has_atmosphere: bool = true
## Rotation, IAU style (Archinal et al. 2018, mean values): the north pole's
## J2000 right ascension and declination, and the prime meridian's angle W
## = prime_meridian_deg + rotation_deg_per_day · (days since J2000), measured
## along the equator from its ascending node on the ICRS equator.
@export var pole_ra_deg: float = 0.0
@export var pole_dec_deg: float = 90.0
@export var prime_meridian_deg: float = 190.46061837
@export var rotation_deg_per_day: float = 360.98564736629
## The largest periodic term, if any (the Moon's E1, its node's 18.6-year
## cycle): amplitudes added to right ascension (× sin E), declination
## (× cos E) and W (× sin E), with E = term_e0_deg + term_deg_per_day · d.
## Evaluated at the scenario epoch (it barely moves within a sortie).
@export var term_amplitudes_deg := Vector3.ZERO
@export var term_e0_deg: float = 0.0
@export var term_deg_per_day: float = 0.0
## Reflected light (CelestialFrame.reflected_fraction): geometric albedo
## (brightness at full phase relative to a white disc), and how it fades
## with phase angle: &"lambert" (a diffuse sphere) or &"lunar" (the Moon's
## measured curve, with its opposition surge).
@export var geometric_albedo: float = 0.3
@export var phase_law: StringName = &"lambert"
## Where it is (CelestialFrame.heliocentric_icrs): &"earth", &"moon", a
## planet with Keplerian elements (&"mars", &"jupiter"…) or a moon on a
## two-body orbit about one (&"phobos", &"deimos").
@export var ephemeris: StringName = &"earth"
## The air's colour (limb glow and haze) and whether it carries Earth-like
## clouds over seas (sea glint); Mars has thin, dusty air and neither.
@export var air_color := Color(0.32, 0.56, 1.0)
@export var clouds_and_seas: bool = true
## The Sun as a central body (deep-space surveys): it casts no shadow on
## what orbits it and is drawn as the sky's Sun, not as a planet.
@export var is_star: bool = false
## Surface colour map: equirectangular, left edge 180° W, top edge 90° N.
@export var surface_map: Texture2D
## A real surface to meet (play-test batch 10): an elevation map
## (TerrainMap) — no instant loss at the entry interface; touching down
## slower than `safe_landing_mps` lands, faster crashes. Empty: the entry
## interface is the end, as before (Earth's atmosphere).
@export_file var elevation_map: String = ""
@export var safe_landing_mps: float = 4.0
## Airless, with no elevation map, but still ground to land on (Milestone
## 16: Mercury, Phobos, Deimos): the mean-radius sphere with fine seeded
## relief (TerrainMap.bare). Without it, the entry interface is a crash.
@export var landable: bool = false
## How fast the air thins (m): the limb glow's height.
@export var air_scale_height_m: float = 9000.0
## How much fine rocky detail the sky shader adds over the map (1 for rock;
## low for cloud tops, which have none).
@export var surface_detail: float = 1.0
## Rings (Saturn): [inner km, outer km, opacity] per band, in the
## equatorial plane; empty for none.
@export var ring_bands_km: PackedFloat32Array = PackedFloat32Array()
@export var ring_color := Color(0.84, 0.76, 0.62)


## The surface heights, or null for a body without an elevation map.
func terrain() -> TerrainMap:
	var map := TerrainMap.load_map(elevation_map) if elevation_map != "" else (TerrainMap.bare(radius_m) if landable else null)
	if map != null:
		map.radius_m = radius_m
	return map


func has_rings() -> bool:
	return ring_bands_km.size() >= 3


## Inner and outer ring radii (m).
func ring_span_m() -> Vector2:
	if not has_rings():
		return Vector2.ZERO
	var inner := INF
	var outer := 0.0
	for i in range(0, ring_bands_km.size() - 2, 3):
		inner = minf(inner, ring_bands_km[i])
		outer = maxf(outer, ring_bands_km[i + 1])
	return Vector2(inner, outer) * 1000.0


## Ring opacity at `radius_m` (0 outside the bands).
func ring_opacity(at_radius_m: float) -> float:
	var km := at_radius_m / 1000.0
	for i in range(0, ring_bands_km.size() - 2, 3):
		if km >= ring_bands_km[i] and km < ring_bands_km[i + 1]:
			return ring_bands_km[i + 2]
	return 0.0


func entry_radius_m() -> float:
	return radius_m + entry_interface_altitude_m


## The radius that shades what orbits it (0 for a star).
func shadow_radius_m() -> float:
	return 0.0 if is_star else radius_m


## The radius drawn as a planet's disc in the sky (0 for a star, which the
## sky draws as its Sun).
func disc_radius_m() -> float:
	return 0.0 if is_star else radius_m


## What crossing the entry interface is called ("atmospheric entry" / "terrain impact").
func entry_word() -> String:
	if is_star:
		return "fall into the Sun"
	return "atmospheric entry" if has_atmosphere else "terrain impact"


func circular_speed(radius: float) -> float:
	return sqrt(mu_m3_s2 / radius)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if mu_m3_s2 <= 0.0:
		problems.append("mu_m3_s2 must be positive")
	if radius_m <= 0.0:
		problems.append("radius_m must be positive")
	if entry_interface_altitude_m < 0.0:
		problems.append("entry_interface_altitude_m must not be negative")
	return problems
