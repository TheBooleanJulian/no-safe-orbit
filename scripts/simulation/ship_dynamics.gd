class_name ShipDynamics
extends RefCounted
## 6DoF rigid-body integration for a ship, including flight assist.
##
## Simplifications (documented in docs/ARCHITECTURE.md):
## - Diagonal inertia tensor; the gyroscopic term (ω × Iω) is ignored.
## - Thrust and torque are independent budgets (no thruster coupling yet).
## - Translation: kick-drift-kick leapfrog at a fixed timestep, thrust held
##   constant over the tick. Rotation: semi-implicit Euler.
## - Gravity enters only through `frame` (a free-falling LocalFrame), as the
##   tidal term; without a frame the local space is inertial.

const INPUT_DEADZONE := 0.001


## Advance `state` by `dt` seconds under `input`. `frame` (optional) must
## already have been stepped to the end of this tick.
static func step(state: ShipState, input: ShipControlInput, dt: float, frame: LocalFrame = null) -> void:
	assert(dt > 0.0, "ShipDynamics.step requires dt > 0")
	var cfg := state.config
	var thrust_body := compute_body_thrust(state, input, dt)
	var torque_body := compute_body_torque(state, input, dt)

	# Translation (leapfrog: tidal term sampled at start and end positions).
	var accel_body := thrust_body / cfg.mass_kg
	var accel_thrust := state.orientation * accel_body
	var half_dt := dt * 0.5
	var tidal_start := frame.tidal_acceleration(state.position, true) if frame else Vector3.ZERO
	state.velocity += (accel_thrust + tidal_start) * half_dt
	state.position += state.velocity * dt
	var tidal_end := frame.tidal_acceleration(state.position, false) if frame else Vector3.ZERO
	state.velocity += (accel_thrust + tidal_end) * half_dt
	state.delta_v_expended += (absf(accel_body.x) + absf(accel_body.y) + absf(accel_body.z)) * dt

	# Rotation (body frame).
	var alpha := Vector3(
		torque_body.x / cfg.inertia_kgm2.x,
		torque_body.y / cfg.inertia_kgm2.y,
		torque_body.z / cfg.inertia_kgm2.z)
	state.angular_velocity += alpha * dt
	var w := state.angular_velocity
	var angle := w.length() * dt
	if angle > 1e-12:
		state.orientation = (state.orientation * Quaternion(w / w.length(), angle)).normalized()

	state.last_thrust_body = thrust_body
	state.last_torque_body = torque_body


## Thrust (N, body frame) the ship applies this tick.
## Commanded axes get the commanded fraction of their thrust budget. With
## flight assist and a translation hold, uncommanded axes thrust against
## velocity relative to `input.hold_velocity` — never beyond that axis's
## thrust limit, and never past the hold (no overshoot).
static func compute_body_thrust(state: ShipState, input: ShipControlInput, dt: float) -> Vector3:
	var cfg := state.config
	var v_body := state.orientation.inverse() * (state.velocity - input.hold_velocity)
	var thrust := Vector3.ZERO
	for axis in 3:
		var cmd := clampf(input.translation[axis], -1.0, 1.0)
		var pos_max := cfg.max_thrust(axis, true)
		var neg_max := cfg.max_thrust(axis, false)
		if absf(cmd) > INPUT_DEADZONE:
			thrust[axis] = cmd * (pos_max if cmd > 0.0 else neg_max)
		elif input.flight_assist and input.hold_translation:
			var force_to_stop := -v_body[axis] * cfg.mass_kg / dt
			thrust[axis] = clampf(force_to_stop, -neg_max, pos_max)
	return thrust


## Torque (N·m, body frame) the ship applies this tick.
## Assist treats input as a target angular rate and drives towards it;
## manual applies input directly as a fraction of available torque.
static func compute_body_torque(state: ShipState, input: ShipControlInput, dt: float) -> Vector3:
	var cfg := state.config
	var torque := Vector3.ZERO
	for axis in 3:
		var cmd := clampf(input.rotation[axis], -1.0, 1.0)
		var t_max := cfg.max_torque_nm[axis]
		if input.flight_assist:
			var target_rate := cmd * cfg.assist_max_rate_rad_s[axis]
			var wanted := (target_rate - state.angular_velocity[axis]) * cfg.inertia_kgm2[axis] / dt
			torque[axis] = clampf(wanted, -t_max, t_max)
		else:
			torque[axis] = cmd * t_max
	return torque
