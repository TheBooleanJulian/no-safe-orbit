class_name ShipDynamics
extends RefCounted
## 6DoF rigid-body integration for a ship, including flight assist and
## propellant use.
##
## - Translation: kick-drift-kick leapfrog at a fixed timestep, thrust held
##   constant over the tick, divided by the ship's current (wet) mass.
## - Rotation: Euler's equations with the gyroscopic term,
##   I·dω/dt = τ − ω × (I·ω), integrated with RK4 (diagonal inertia).
## - Main engines mounted off the centre of mass add torque in proportion to
##   their thrust; flight assist fights it with RCS.
## - Propellant: main thrust burns at F/(Isp_main·g0); RCS translation and
##   rotation at the RCS Isp. With empty tanks nothing fires.
## - Gravity enters only through `frame` (a free-falling LocalFrame), as the
##   tidal term; without a frame the local space is inertial.

const INPUT_DEADZONE := 0.001
const G0 := 9.80665


## Advance `state` by `dt` seconds under `input`. `frame` (optional) must
## already have been stepped to the end of this tick.
static func step(state: ShipState, input: ShipControlInput, dt: float, frame: LocalFrame = null) -> void:
	assert(dt > 0.0, "ShipDynamics.step requires dt > 0")
	var cfg := state.config
	var mass := state.mass_kg()
	var inertia := state.inertia_kgm2()
	var thrust_body := compute_body_thrust(state, input, dt, mass)
	var engine_torque := cfg.thrust_torque_body * main_thrust_fraction(cfg, thrust_body)
	var rcs_torque := compute_body_torque(state, input, dt, inertia, engine_torque)

	var available := _burn_propellant(state, thrust_body, rcs_torque, dt)
	thrust_body *= available
	engine_torque *= available
	rcs_torque *= available

	# Translation (leapfrog: tidal term sampled at start and end positions).
	var accel_body := thrust_body / mass
	var accel_thrust := state.orientation * accel_body
	var half_dt := dt * 0.5
	var tidal_start := frame.tidal_acceleration(state.position, true) if frame else Vector3.ZERO
	state.velocity += (accel_thrust + tidal_start) * half_dt
	state.position += state.velocity * dt
	var tidal_end := frame.tidal_acceleration(state.position, false) if frame else Vector3.ZERO
	state.velocity += (accel_thrust + tidal_end) * half_dt
	state.delta_v_expended += (absf(accel_body.x) + absf(accel_body.y) + absf(accel_body.z)) * dt

	# Rotation (body frame): RK4 on Euler's equations, then turn the attitude
	# by the mean rate over the tick.
	var torque := rcs_torque + engine_torque
	var w0 := state.angular_velocity
	var k1 := angular_acceleration(w0, torque, inertia)
	var k2 := angular_acceleration(w0 + k1 * half_dt, torque, inertia)
	var k3 := angular_acceleration(w0 + k2 * half_dt, torque, inertia)
	var k4 := angular_acceleration(w0 + k3 * dt, torque, inertia)
	state.angular_velocity = w0 + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * (dt / 6.0)
	var w := (w0 + state.angular_velocity) * 0.5
	var angle := w.length() * dt
	if angle > 1e-12:
		state.orientation = (state.orientation * Quaternion(w / w.length(), angle)).normalized()

	state.last_thrust_body = thrust_body
	state.last_torque_body = torque


## dω/dt for a diagonal inertia tensor (body frame).
static func angular_acceleration(w: Vector3, torque: Vector3, inertia: Vector3) -> Vector3:
	return (torque - w.cross(inertia * w)) / inertia


## Fraction (0–1) of full main-engine thrust in a body thrust vector.
static func main_thrust_fraction(cfg: ShipConfig, thrust_body: Vector3) -> float:
	if cfg.thrust_forward_n <= 0.0:
		return 0.0
	return clampf(-thrust_body.z / cfg.thrust_forward_n, 0.0, 1.0)


## Thrust (N, body frame) the ship applies this tick.
## Commanded axes get the commanded fraction of their thrust budget. With
## flight assist and a translation hold, uncommanded axes thrust against
## velocity relative to `input.hold_velocity` — never beyond that axis's
## thrust limit, and never past the hold (no overshoot).
static func compute_body_thrust(state: ShipState, input: ShipControlInput, dt: float, mass: float = -1.0) -> Vector3:
	var cfg := state.config
	if mass <= 0.0:
		mass = state.mass_kg()
	var v_body := state.orientation.inverse() * (state.velocity - input.hold_velocity)
	var thrust := Vector3.ZERO
	for axis in 3:
		var cmd := clampf(input.translation[axis], -1.0, 1.0)
		var pos_max := cfg.max_thrust(axis, true)
		var neg_max := cfg.max_thrust(axis, false)
		if absf(cmd) > INPUT_DEADZONE:
			thrust[axis] = cmd * (pos_max if cmd > 0.0 else neg_max)
		elif input.flight_assist and input.hold_translation:
			var force_to_stop := -v_body[axis] * mass / dt
			thrust[axis] = clampf(force_to_stop, -neg_max, pos_max)
	return thrust


## RCS torque (N·m, body frame) the ship applies this tick.
## Assist treats input as a target angular rate and drives towards it,
## cancelling the gyroscopic term and any main-engine torque within RCS
## limits; manual applies input directly as a fraction of available torque.
static func compute_body_torque(state: ShipState, input: ShipControlInput, dt: float,
		inertia: Vector3 = Vector3.ZERO, engine_torque: Vector3 = Vector3.ZERO) -> Vector3:
	var cfg := state.config
	if inertia == Vector3.ZERO:
		inertia = state.inertia_kgm2()
	var w := state.angular_velocity
	var gyro := w.cross(inertia * w)
	var torque := Vector3.ZERO
	for axis in 3:
		var cmd := clampf(input.rotation[axis], -1.0, 1.0)
		var t_max := cfg.max_torque_nm[axis]
		if input.flight_assist:
			var target_rate := cmd * cfg.assist_max_rate_rad_s[axis]
			var wanted := (target_rate - w[axis]) * inertia[axis] / dt + gyro[axis] - engine_torque[axis]
			torque[axis] = clampf(wanted, -t_max, t_max)
		else:
			torque[axis] = cmd * t_max
	return torque


## Takes this tick's propellant; returns the fraction of the requested
## thrust/torque that could actually be produced (1 unless tanks run dry).
static func _burn_propellant(state: ShipState, thrust_body: Vector3, rcs_torque: Vector3, dt: float) -> float:
	var cfg := state.config
	if cfg.unlimited_propellant:
		return 1.0
	var main_n := maxf(-thrust_body.z, 0.0)
	var rcs_n := absf(thrust_body.x) + absf(thrust_body.y) + maxf(thrust_body.z, 0.0)
	# Rotation: thrust the RCS needs for this torque at its effective lever arm.
	if cfg.thrust_lateral_n > 0.0:
		for axis in 3:
			if cfg.max_torque_nm[axis] > 0.0:
				rcs_n += absf(rcs_torque[axis]) * cfg.thrust_lateral_n / cfg.max_torque_nm[axis]
	var flow := 0.0
	if cfg.main_isp_s > 0.0:
		flow += main_n / (cfg.main_isp_s * G0)
	if cfg.rcs_isp_s > 0.0:
		flow += rcs_n / (cfg.rcs_isp_s * G0)
	var needed := flow * dt
	if needed <= 0.0:
		return 1.0
	if needed <= state.propellant_kg:
		state.propellant_kg -= needed
		return 1.0
	var fraction := state.propellant_kg / needed
	state.propellant_kg = 0.0
	return fraction
