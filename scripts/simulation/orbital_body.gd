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
## Surface colour map: equirectangular, left edge 180° W, top edge 90° N.
@export var surface_map: Texture2D


func entry_radius_m() -> float:
	return radius_m + entry_interface_altitude_m


## What crossing the entry interface is called ("atmospheric entry" / "terrain impact").
func entry_word() -> String:
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
