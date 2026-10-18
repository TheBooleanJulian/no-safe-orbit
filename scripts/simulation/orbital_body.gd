class_name OrbitalBody
extends Resource
## A spherical central body for two-body gravity (a = −μ r/|r|³).
## Units: m, m³/s². Data lives in data/bodies/*.tres.

@export var display_name: String = "Unnamed body"
## Standard gravitational parameter GM.
@export var mu_m3_s2: float = 3.986004418e14
## Mean radius of the solid/ocean surface.
@export var radius_m: float = 6_371_000.0
## Altitude of the entry interface. There is no drag model: any trajectory
## that crosses this altitude counts as atmospheric entry and leaves the
## orbital engagement. For Earth this is the 100 km Kármán line.
@export var entry_interface_altitude_m: float = 100_000.0


func entry_radius_m() -> float:
	return radius_m + entry_interface_altitude_m


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
