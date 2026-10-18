class_name CelestialFrame
extends RefCounted
## Ties the simulation's planet-centred inertial (PCI) axes to the real sky
## for a scenario epoch, so the stars, the Sun and Earth's surface are
## mutually consistent (stars and Sun as seen from the Solar System).
##
## Axes: ICRS/J2000 equatorial (x → vernal equinox, z → celestial north)
## maps to PCI with celestial north along PCI −X, then a twist about that
## pole chosen so the Sun sits where the scenario wants it relative to the
## start point (PCI +Y, moving −Z). That start orbit is therefore a prograde
## equatorial orbit, like a real LEO station's.
## Low-precision formulas (Astronomical Almanac): Sun ~0.01°, GMST ~0.1 s.
## Precession, nutation and aberration are ignored (< 0.4° since J2000).

const EARTH_ROTATION_RAD_S := 7.2921159e-5  # sidereal
const J2000_JD := 2451545.0
const UNIX_EPOCH_JD := 2440587.5

var epoch_jd: float
## Rotation about PCI +X applied after the fixed axis mapping (rad).
var twist: float = 0.0


## `sun_angle_from_up_deg`: where the Sun's projection on the orbit plane
## should sit, measured from the start point's zenith (+Y) towards +Z
## (i.e. behind a ship flying prograde).
static func for_scenario(p_epoch_jd: float, sun_angle_from_up_deg: float) -> CelestialFrame:
	var frame := CelestialFrame.new()
	frame.epoch_jd = p_epoch_jd
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
	var m := Vector3(-v.z, v.x, -v.y)  # north → −X, equinox → +Y
	var c := cos(twist)
	var s := sin(twist)
	return Vector3(m.x, m.y * c - m.z * s, m.y * s + m.z * c)


func pci_to_icrs(v: Vector3) -> Vector3:
	var c := cos(twist)
	var s := sin(twist)
	var m := Vector3(v.x, v.y * c + v.z * s, -v.y * s + v.z * c)
	return Vector3(m.y, -m.z, -m.x)


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


## Earth's north pole in PCI.
func north_pole_pci() -> Vector3:
	return icrs_to_pci(Vector3(0, 0, 1))


## Basis taking PCI vectors to Earth-fixed (ECEF: x → Greenwich meridian on
## the equator, z → north pole), for drawing real geography.
func pci_to_ecef(sim_time: float) -> Basis:
	var g := gmst_rad(julian_date(sim_time))
	var cols: Array[Vector3] = []
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var i := pci_to_icrs(axis)
		# ECEF = Rz(−GMST) · ICRS
		cols.append(Vector3(i.x * cos(g) + i.y * sin(g), -i.x * sin(g) + i.y * cos(g), i.z))
	return Basis(cols[0], cols[1], cols[2])
