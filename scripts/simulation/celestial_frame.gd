class_name CelestialFrame
extends RefCounted
## Ties the simulation's planet-centred inertial (PCI) axes to the real sky
## for a scenario epoch, so the stars, the Sun and the central body's
## surface are mutually consistent (stars and Sun as seen from the Solar
## System).
##
## Axes: the body's equatorial frame (its north pole, and the ascending node
## of its equator on the ICRS equator) maps to PCI with the body's north
## along PCI −X, then a twist about that pole chosen so the Sun sits where
## the scenario wants it relative to the start point (PCI +Y, moving −Z).
## The start orbit is therefore a prograde equatorial orbit, like a real LEO
## station's. For Earth the pole is ICRS +Z and the node the ICRS +Y axis.
## Low-precision formulas (Astronomical Almanac): Sun ~0.01°, GMST ~0.1 s.
## Precession, nutation and aberration are ignored (< 0.4° since J2000).
## The Moon: the IAU pole and rotation with only their largest periodic
## term (E1; the rest add up to ~0.3°), and the Sun's direction is Earth's
## (≤ 0.15° off at the Moon's distance).

const EARTH_ROTATION_RAD_S := 7.2921159e-5  # sidereal
const J2000_JD := 2451545.0
const UNIX_EPOCH_JD := 2440587.5

var epoch_jd: float
## Rotation about PCI +X applied after the fixed axis mapping (rad).
var twist: float = 0.0
## The body's north pole and its equator's ascending node on the ICRS
## equator (ICRS unit vectors), and its prime meridian (OrbitalBody).
var pole_icrs := Vector3(0, 0, 1)
var node_icrs := Vector3(0, 1, 0)
var prime_meridian_deg := 190.46061837
var rotation_deg_per_day := 360.98564736629


## `sun_angle_from_up_deg`: where the Sun's projection on the orbit plane
## should sit, measured from the start point's zenith (+Y) towards +Z
## (i.e. behind a ship flying prograde).
## `body`: the central body whose pole and rotation to use (Earth if null).
static func for_scenario(p_epoch_jd: float, sun_angle_from_up_deg: float, body: OrbitalBody = null) -> CelestialFrame:
	var frame := CelestialFrame.new()
	frame.epoch_jd = p_epoch_jd
	if body != null:
		var e := deg_to_rad(body.term_e0_deg + body.term_deg_per_day * (p_epoch_jd - J2000_JD))
		var amp := body.term_amplitudes_deg
		var ra := body.pole_ra_deg + amp.x * sin(e)
		frame.pole_icrs = radec_to_icrs(ra, body.pole_dec_deg + amp.y * cos(e))
		var node_ra := deg_to_rad(ra + 90.0)
		frame.node_icrs = Vector3(cos(node_ra), sin(node_ra), 0.0)
		frame.prime_meridian_deg = body.prime_meridian_deg + amp.z * sin(e)
		frame.rotation_deg_per_day = body.rotation_deg_per_day
	var s := frame.icrs_to_pci(sun_direction_icrs(p_epoch_jd))
	frame.twist = deg_to_rad(sun_angle_from_up_deg) - atan2(s.z, s.y)
	return frame


static func julian_date_from_unix(unix_seconds: float) -> float:
	return unix_seconds / 86400.0 + UNIX_EPOCH_JD


## Julian date of an ISO 8601 UTC timestamp, e.g. "2026-10-19T12:00:00".
static func julian_date_from_iso(utc: String) -> float:
	return julian_date_from_unix(Time.get_unix_time_from_datetime_string(utc))


## Unit vector of a J2000 right ascension / declination in ICRS axes.
static func radec_to_icrs(ra_deg: float, dec_deg: float) -> Vector3:
	var ra := deg_to_rad(ra_deg)
	var dec := deg_to_rad(dec_deg)
	return Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))


## Geocentric direction to the Sun (ICRS axes), unit vector.
static func sun_direction_icrs(jd: float) -> Vector3:
	var n := jd - J2000_JD
	var mean_longitude := deg_to_rad(fposmod(280.460 + 0.9856474 * n, 360.0))
	var anomaly := deg_to_rad(fposmod(357.528 + 0.9856003 * n, 360.0))
	var ecliptic_longitude := mean_longitude + deg_to_rad(1.915) * sin(anomaly) + deg_to_rad(0.020) * sin(2.0 * anomaly)
	var obliquity := deg_to_rad(23.439 - 0.0000004 * n)
	return Vector3(cos(ecliptic_longitude),
		cos(obliquity) * sin(ecliptic_longitude),
		sin(obliquity) * sin(ecliptic_longitude))


## Greenwich mean sidereal time (rad, 0–2π).
static func gmst_rad(jd: float) -> float:
	return deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - J2000_JD), 360.0))


## ICRS direction → PCI direction.
func icrs_to_pci(v: Vector3) -> Vector3:
	# Body equatorial components (node, pole × node, pole), then north → −X.
	var m := -Vector3(v.dot(pole_icrs), v.dot(pole_icrs.cross(node_icrs)), v.dot(node_icrs))
	var c := cos(twist)
	var s := sin(twist)
	return Vector3(m.x, m.y * c - m.z * s, m.y * s + m.z * c)


func pci_to_icrs(v: Vector3) -> Vector3:
	var c := cos(twist)
	var s := sin(twist)
	var m := Vector3(v.x, v.y * c + v.z * s, -v.y * s + v.z * c)
	return node_icrs * -m.z + pole_icrs.cross(node_icrs) * -m.y + pole_icrs * -m.x


func julian_date(sim_time: float) -> float:
	return epoch_jd + sim_time / 86400.0


func sun_direction_pci(sim_time: float) -> Vector3:
	return icrs_to_pci(sun_direction_icrs(julian_date(sim_time))).normalized()


## Fraction of the Sun visible from PCI position `r`: 1 in sunlight, 0 in the
## planet's shadow (cylindrical shadow, softened over ±10 km at the edge).
static func sunlight_fraction(r: Vec3d, sun_dir: Vector3, radius: float) -> float:
	var s := Vec3d.from_vector3(sun_dir.normalized())
	var along := r.dot(s)
	if along >= 0.0:
		return 1.0
	var perp := r.minus(s.times(along)).length()
	return smoothstep(radius - 10_000.0, radius + 10_000.0, perp)


## Next sunset or sunrise along an orbit: {time (s), sunlit_after (bool)},
## or {} if the lighting never changes (e.g. a sun-synchronous terminator
## orbit). Coarse 2° search, then bisection to ~0.1 s.
static func next_light_change(orbit: OrbitElements, sun_dir: Vector3, radius: float) -> Dictionary:
	if not orbit.is_bound():
		return {}
	var lit_now := sunlight_fraction(orbit.position, sun_dir, radius) >= 0.5
	var prev := 0.0
	for step in range(1, 181):
		var angle := deg_to_rad(2.0 * step)
		if (sunlight_fraction(orbit.point_at_angle(angle), sun_dir, radius) >= 0.5) != lit_now:
			var lo := prev
			var hi := angle
			for i in 20:
				var mid := (lo + hi) * 0.5
				if (sunlight_fraction(orbit.point_at_angle(mid), sun_dir, radius) >= 0.5) == lit_now:
					lo = mid
				else:
					hi = mid
			return {"time": orbit.time_to_angle(hi), "sunlit_after": not lit_now}
		prev = angle
	return {}


## The central body's north pole in PCI.
func north_pole_pci() -> Vector3:
	return icrs_to_pci(pole_icrs)


## Basis taking PCI vectors to body-fixed axes (x → prime meridian on the
## equator, z → north pole; for Earth, ECEF), for drawing real geography.
## For Earth W = GMST − 90° (the IAU angle counts from the node at RA 90°).
func pci_to_body_fixed(sim_time: float) -> Basis:
	var w := deg_to_rad(fposmod(prime_meridian_deg + rotation_deg_per_day * (julian_date(sim_time) - J2000_JD), 360.0))
	var east := pole_icrs.cross(node_icrs)
	var cols: Array[Vector3] = []
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var i := pci_to_icrs(axis)
		var e := Vector3(i.dot(node_icrs), i.dot(east), i.dot(pole_icrs))
		# Body-fixed = Rz(−W) · body equatorial
		cols.append(Vector3(e.x * cos(w) + e.y * sin(w), -e.x * sin(w) + e.y * cos(w), e.z))
	return Basis(cols[0], cols[1], cols[2])
