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
## The Almanac's lunar parallax is against this radius.
const EARTH_EQUATORIAL_RADIUS_M := 6_378_140.0
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
## Where the central body is (OrbitalBody.ephemeris), for placing others.
var central_ephemeris: StringName = &"earth"


## `sun_angle_from_up_deg`: where the Sun's projection on the orbit plane
## should sit, measured from the start point's zenith (+Y) towards +Z
## (i.e. behind a ship flying prograde).
## `body`: the central body whose pole and rotation to use (Earth if null).
static func for_scenario(p_epoch_jd: float, sun_angle_from_up_deg: float, body: OrbitalBody = null) -> CelestialFrame:
	var frame := CelestialFrame.new()
	frame.epoch_jd = p_epoch_jd
	if body != null:
		var o := orientation(body, p_epoch_jd)
		frame.pole_icrs = o[0]
		frame.node_icrs = o[1]
		frame.prime_meridian_deg = o[2]
		frame.rotation_deg_per_day = body.rotation_deg_per_day
		frame.central_ephemeris = body.ephemeris
	var s := frame.icrs_to_pci(sun_direction_icrs(p_epoch_jd))
	frame.twist = deg_to_rad(sun_angle_from_up_deg) - atan2(s.z, s.y)
	return frame


## A body's orientation at `jd` (its largest periodic term evaluated there):
## [north pole (ICRS), its equator's ascending node on the ICRS equator
## (ICRS), prime meridian W0 (deg)].
static func orientation(body: OrbitalBody, jd: float) -> Array:
	var e := deg_to_rad(body.term_e0_deg + body.term_deg_per_day * (jd - J2000_JD))
	var amp := body.term_amplitudes_deg
	var ra := body.pole_ra_deg + amp.x * sin(e)
	var node_ra := deg_to_rad(ra + 90.0)
	return [radec_to_icrs(ra, body.pole_dec_deg + amp.y * cos(e)), Vector3(cos(node_ra), sin(node_ra), 0.0),
		body.prime_meridian_deg + amp.z * sin(e)]


## Geocentric position of the Moon (ICRS axes, m). Astronomical Almanac
## low-precision series: ~0.3° in longitude, ~0.2° in latitude, ~0.1 % in
## distance; light time and the geocentre's own wobble are ignored.
static func moon_geocentric_icrs(jd: float) -> Vector3:
	var t := (jd - J2000_JD) / 36525.0
	var lon := 218.32 + 481267.881 * t \
		+ 6.29 * _sin_deg(135.0 + 477198.87 * t) - 1.27 * _sin_deg(259.3 - 413335.36 * t) \
		+ 0.66 * _sin_deg(235.7 + 890534.22 * t) + 0.21 * _sin_deg(269.9 + 954397.74 * t) \
		- 0.19 * _sin_deg(357.5 + 35999.05 * t) - 0.11 * _sin_deg(186.5 + 966404.03 * t)
	var lat := 5.13 * _sin_deg(93.3 + 483202.02 * t) + 0.28 * _sin_deg(228.2 + 960400.89 * t) \
		- 0.28 * _sin_deg(318.3 + 6003.15 * t) - 0.17 * _sin_deg(217.6 - 407332.21 * t)
	var parallax := 0.9508 + 0.0518 * _cos_deg(135.0 + 477198.87 * t) + 0.0095 * _cos_deg(259.3 - 413335.36 * t) \
		+ 0.0078 * _cos_deg(235.7 + 890534.22 * t) + 0.0028 * _cos_deg(269.9 + 954397.74 * t)
	var distance := EARTH_EQUATORIAL_RADIUS_M / _sin_deg(parallax)
	var ecl := Vector3(_cos_deg(lat) * _cos_deg(lon), _cos_deg(lat) * _sin_deg(lon), _sin_deg(lat))
	var eps := deg_to_rad(23.439 - 0.0000004 * (jd - J2000_JD))
	return Vector3(ecl.x, cos(eps) * ecl.y - sin(eps) * ecl.z, sin(eps) * ecl.y + cos(eps) * ecl.z) * distance


## Sunlight reflected by `body` onto an observer, as a fraction of direct
## sunlight: geometric albedo × (radius / distance)² × phase function.
## `body_from_observer`: observer → body (m); `sun_dir`: towards the Sun
## (the Sun is far enough that the body and the observer see it alike).
## Full Moon from Earth: ~2.4e-6 (~0.3 lux against ~127,000 lux of sun).
static func reflected_fraction(body: OrbitalBody, body_from_observer: Vector3, sun_dir: Vector3) -> float:
	var d := body_from_observer.length()
	if d <= body.radius_m:
		return 0.0
	# Phase angle: Sun – body – observer.
	var alpha := sun_dir.angle_to(-body_from_observer)
	var r := body.radius_m / d
	return body.geometric_albedo * r * r * phase_function(body, alpha)


## Brightness at phase angle `alpha` (rad) relative to full phase.
static func phase_function(body: OrbitalBody, alpha: float) -> float:
	match body.phase_law:
		&"lunar":
			# The Moon's visual magnitude against phase (Allen's Astrophysical
			# Quantities): +0.026 mag/° and +4e-9 mag/°⁴; a half moon is ~1/9
			# of a full one, not the 1/π of a diffuse sphere.
			var deg := rad_to_deg(alpha)
			return pow(10.0, -0.4 * (0.026 * deg + 4.0e-9 * pow(deg, 4.0)))
	# Lambert sphere.
	return (sin(alpha) + (PI - alpha) * cos(alpha)) / PI


## Geocentric position (ICRS, m) of a body by its ephemeris id.
static func geocentric_icrs(ephemeris: StringName, jd: float) -> Vector3:
	match ephemeris:
		&"moon":
			return moon_geocentric_icrs(jd)
	return Vector3.ZERO  # Earth (and anything unknown) at the geocentre


static func _sin_deg(d: float) -> float:
	return sin(deg_to_rad(d))


static func _cos_deg(d: float) -> float:
	return cos(deg_to_rad(d))


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
	return _to_fixed(pole_icrs, node_icrs, prime_meridian_deg, rotation_deg_per_day, sim_time)


## Another body seen from here: its centre relative to the central body's
## (PCI axes, m), e.g. the Moon from Earth orbit or Earth from lunar orbit.
func position_of(body: OrbitalBody, sim_time: float) -> Vector3:
	var jd := julian_date(sim_time)
	return icrs_to_pci(geocentric_icrs(body.ephemeris, jd) - geocentric_icrs(central_ephemeris, jd))


## Basis taking PCI vectors to `body`'s own fixed axes (for drawing its map).
func body_fixed_of(body: OrbitalBody, sim_time: float) -> Basis:
	var o := orientation(body, epoch_jd)
	return _to_fixed(o[0], o[1], o[2], body.rotation_deg_per_day, sim_time)


func _to_fixed(pole: Vector3, node: Vector3, w0_deg: float, rate_deg_per_day: float, sim_time: float) -> Basis:
	var w := deg_to_rad(fposmod(w0_deg + rate_deg_per_day * (julian_date(sim_time) - J2000_JD), 360.0))
	var east := pole.cross(node)
	var cols: Array[Vector3] = []
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var i := pci_to_icrs(axis)
		var e := Vector3(i.dot(node), i.dot(east), i.dot(pole))
		# Body-fixed = Rz(−W) · body equatorial
		cols.append(Vector3(e.x * cos(w) + e.y * sin(w), -e.x * sin(w) + e.y * cos(w), e.z))
	return Basis(cols[0], cols[1], cols[2])
