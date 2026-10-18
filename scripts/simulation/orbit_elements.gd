class_name OrbitElements
extends RefCounted
## Osculating two-body orbit from a PCI state vector, in double precision.
## Used for the orbital HUD, the projected path and entry prediction.
##
## Eccentricity terms are kept as components (e·cos ν, e·sin ν) so nothing
## divides by e: near-circular orbits stay well defined.

var mu: float
var position: Vec3d
var velocity: Vec3d
var radius: float
var speed: float
var radial_speed: float
var specific_energy: float
## Negative for hyperbolic orbits, INF for exactly parabolic.
var semi_major_axis: float
var eccentricity: float
var semi_latus_rectum: float
var periapsis_radius: float
## INF when unbound.
var apoapsis_radius: float
## INF when unbound.
var period: float
var true_anomaly: float
var angular_momentum: float

var _e_cos: float  # e·cos ν at the current position
var _e_sin: float  # e·sin ν at the current position
var _radial_unit: Vec3d
var _along_unit: Vec3d  # in-plane, 90° ahead of the radial direction


static func from_state(p_mu: float, r: Vec3d, v: Vec3d) -> OrbitElements:
	var el := OrbitElements.new()
	el.mu = p_mu
	el.position = r.copy()
	el.velocity = v.copy()
	el.radius = r.length()
	el.speed = v.length()
	el.radial_speed = r.dot(v) / el.radius
	el.specific_energy = 0.5 * el.speed * el.speed - p_mu / el.radius
	var h_vec := r.cross(v)
	var h := h_vec.length()
	el.angular_momentum = h
	el.semi_latus_rectum = h * h / p_mu
	el._e_cos = el.semi_latus_rectum / el.radius - 1.0
	el._e_sin = el.radial_speed * h / p_mu
	el.eccentricity = sqrt(el._e_cos * el._e_cos + el._e_sin * el._e_sin)
	el.true_anomaly = fposmod(atan2(el._e_sin, el._e_cos), TAU)
	el.periapsis_radius = el.semi_latus_rectum / (1.0 + el.eccentricity)
	if el.specific_energy == 0.0:
		el.semi_major_axis = INF
	else:
		el.semi_major_axis = -p_mu / (2.0 * el.specific_energy)
	if el.is_bound():
		el.apoapsis_radius = el.semi_latus_rectum / (1.0 - el.eccentricity)
		el.period = TAU * sqrt(pow(el.semi_major_axis, 3.0) / p_mu)
	else:
		el.apoapsis_radius = INF
		el.period = INF
	el._radial_unit = r.normalized()
	el._along_unit = h_vec.normalized().cross(el._radial_unit) if h > 0.0 else Vec3d.new()
	return el


## Exact two-body propagation of a PCI state by `dt` seconds (universal
## variables; elliptic, parabolic and hyperbolic alike). Returns
## [position, velocity]. Used for rounds far from the engagement, which
## coast on their own orbits until they come back or re-enter.
static func propagate(p_mu: float, r0: Vec3d, v0: Vec3d, dt: float) -> Array[Vec3d]:
	var r0n := r0.length()
	var v0n := v0.length()
	var sqrt_mu := sqrt(p_mu)
	var vr0 := r0.dot(v0) / r0n
	var alpha := 2.0 / r0n - v0n * v0n / p_mu  # 1/a
	if alpha > 1e-12:
		dt = fmod(dt, TAU / sqrt(p_mu * alpha * alpha * alpha))  # whole orbits change nothing
	var chi := sqrt_mu * absf(alpha) * dt
	for i in 60:
		var z := alpha * chi * chi
		var c := _stumpff_c(z)
		var s := _stumpff_s(z)
		var f := r0n * vr0 / sqrt_mu * chi * chi * c + (1.0 - alpha * r0n) * chi * chi * chi * s + r0n * chi - sqrt_mu * dt
		var df := r0n * vr0 / sqrt_mu * chi * (1.0 - alpha * chi * chi * s) + (1.0 - alpha * r0n) * chi * chi * c + r0n
		var step := f / df
		chi -= step
		if absf(step) < 1e-10 * maxf(absf(chi), 1.0):
			break
	var z := alpha * chi * chi
	var c := _stumpff_c(z)
	var s := _stumpff_s(z)
	var fl := 1.0 - chi * chi / r0n * c
	var gl := dt - chi * chi * chi / sqrt_mu * s
	var r := r0.times(fl).plus(v0.times(gl))
	var rn := r.length()
	var fdot := sqrt_mu / (rn * r0n) * (alpha * chi * chi * chi * s - chi)
	var gdot := 1.0 - chi * chi / rn * c
	return [r, r0.times(fdot).plus(v0.times(gdot))]


static func _stumpff_c(z: float) -> float:
	if z > 1e-8:
		return (1.0 - cos(sqrt(z))) / z
	if z < -1e-8:
		return (cosh(sqrt(-z)) - 1.0) / -z
	return 0.5 - z / 24.0


static func _stumpff_s(z: float) -> float:
	if z > 1e-8:
		var sz := sqrt(z)
		return (sz - sin(sz)) / (sz * sz * sz)
	if z < -1e-8:
		var sz := sqrt(-z)
		return (sinh(sz) - sz) / (sz * sz * sz)
	return 1.0 / 6.0 - z / 120.0


func is_bound() -> bool:
	return eccentricity < 1.0 and specific_energy < 0.0


## PCI point on the orbit `angle` radians ahead of the current position
## (prograde), or null where the conic does not reach (hyperbola asymptote).
func point_at_angle(angle: float) -> Vec3d:
	var denom := 1.0 + _e_cos * cos(angle) - _e_sin * sin(angle)
	if denom <= 1e-9:
		return null
	var r := semi_latus_rectum / denom
	return _radial_unit.times(r * cos(angle)).plus(_along_unit.times(r * sin(angle)))


## Seconds until the orbit next reaches true anomaly `nu` (bound orbits only;
## NAN otherwise).
func time_to_true_anomaly(nu: float) -> float:
	if not is_bound():
		return NAN
	var n := sqrt(mu / pow(semi_major_axis, 3.0))
	var dm := fposmod(_mean_anomaly(nu) - _mean_anomaly(true_anomaly), TAU)
	return dm / n


## Seconds until the orbit reaches the point `angle` radians ahead (bound only).
func time_to_angle(angle: float) -> float:
	return time_to_true_anomaly(fposmod(true_anomaly + angle, TAU))


func time_to_periapsis() -> float:
	return time_to_true_anomaly(0.0)


func time_to_apoapsis() -> float:
	return time_to_true_anomaly(PI)


## Seconds until the radius next falls to `r_target` while descending:
## 0 if already at or below it, NAN if the trajectory never gets that low
## (or is escaping).
func time_to_radius_descending(r_target: float) -> float:
	if radius <= r_target:
		return 0.0
	if periapsis_radius >= r_target or eccentricity < 1e-12:
		return NAN
	var cos_nu := clampf((semi_latus_rectum / r_target - 1.0) / eccentricity, -1.0, 1.0)
	if is_bound():
		# Descending branch: between apoapsis (π) and periapsis (2π).
		return time_to_true_anomaly(TAU - acos(cos_nu))
	if radial_speed >= 0.0:
		return NAN  # past periapsis on an escape trajectory
	var nu_now := true_anomaly - TAU if true_anomaly > PI else true_anomaly
	var n := sqrt(mu / pow(-semi_major_axis, 3.0))
	return (_hyperbolic_mean_anomaly(-acos(cos_nu)) - _hyperbolic_mean_anomaly(nu_now)) / n


## True if the current trajectory reaches radius `r_target` before periapsis.
func intersects_radius(r_target: float) -> bool:
	return not is_nan(time_to_radius_descending(r_target))


func _mean_anomaly(nu: float) -> float:
	var e := eccentricity
	var ecc_anomaly := 2.0 * atan2(sqrt(1.0 - e) * sin(nu * 0.5), sqrt(1.0 + e) * cos(nu * 0.5))
	return ecc_anomaly - e * sin(ecc_anomaly)


## Hyperbolic mean anomaly for −π < ν < π inside the asymptotes.
func _hyperbolic_mean_anomaly(nu: float) -> float:
	var e := eccentricity
	var f := 2.0 * atanh(sqrt((e - 1.0) / (e + 1.0)) * tan(nu * 0.5))
	return e * sinh(f) - f
