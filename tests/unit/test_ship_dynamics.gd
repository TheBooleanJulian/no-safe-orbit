extends TestCase
## Measures: 6DoF translation/rotation response, inertia, thrust limits and
## flight-assist behaviour of ShipDynamics.

const DT := 1.0 / 60.0
const CONFIG := preload("res://data/ships/placeholder_frigate.tres")


func _ship(velocity := Vector3.ZERO, orientation := Quaternion.IDENTITY) -> ShipState:
	return ShipState.create(&"t", "test", CONFIG, Vector3.ZERO, velocity, orientation)


func _run(ship: ShipState, input: ShipControlInput, seconds: float) -> void:
	var steps := roundi(seconds / DT)
	for i in steps:
		ship.snapshot_previous()
		ShipDynamics.step(ship, input, DT)


func test_coasting_preserves_velocity_and_moves_linearly() -> void:
	# No thrust, no assist: Newton's first law over 10 s.
	var ship := _ship(Vector3(3.0, -2.0, 5.0))
	_run(ship, ShipControlInput.neutral(), 10.0)
	assert_vec_near(ship.velocity, Vector3(3.0, -2.0, 5.0), 1e-5, "coast velocity")
	assert_vec_near(ship.position, Vector3(30.0, -20.0, 50.0), 1e-3, "coast position after 10 s")
	assert_near(ship.delta_v_expended, 0.0, 1e-9, "delta-v spent while coasting")


func test_forward_thrust_accelerates_along_nose() -> void:
	# Full forward thrust for 2 s: a = F/m along -Z.
	var ship := _ship()
	var input := ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, false)
	_run(ship, input, 2.0)
	var a := CONFIG.thrust_forward_n / CONFIG.mass_kg
	assert_vec_near(ship.velocity, Vector3(0, 0, -a * 2.0), 1e-3, "velocity after 2 s forward burn")
	assert_near(ship.delta_v_expended, a * 2.0, 1e-3, "delta-v expended equals a·t")


func test_thrust_follows_ship_orientation() -> void:
	# Nose yawed 90° left (towards -X): forward thrust must accelerate along -X.
	var yawed := Quaternion(Vector3.UP, PI / 2.0)
	var ship := _ship(Vector3.ZERO, yawed)
	_run(ship, ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, false), 1.0)
	var a := CONFIG.thrust_forward_n / CONFIG.mass_kg
	assert_vec_near(ship.velocity, Vector3(-a, 0, 0), 1e-3, "world velocity of yawed ship")
	assert_vec_near(ship.forward(), Vector3(-1, 0, 0), 1e-5, "forward vector of yawed ship")


func test_manual_mode_has_no_damping() -> void:
	# Manual, no input: drift and spin persist.
	var ship := _ship(Vector3(0, 0, -50.0))
	ship.angular_velocity = Vector3(0.1, 0, 0)
	_run(ship, ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, false), 5.0)
	assert_vec_near(ship.velocity, Vector3(0, 0, -50.0), 1e-4, "manual drift velocity")
	assert_vec_near(ship.angular_velocity, Vector3(0.1, 0, 0), 1e-6, "manual spin rate")


func test_assist_nulls_drift_within_thrust_limits() -> void:
	# 20 m/s lateral drift, assist on, no input. Lateral RCS gives 2 m/s²,
	# so expected stop time is 10 s; per-tick Δv must never exceed a_max·dt.
	var ship := _ship(Vector3(20.0, 0, 0))
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	var a_max := CONFIG.thrust_lateral_n / CONFIG.mass_kg
	var worst_step_dv := 0.0
	var stop_time := -1.0
	for i in roundi(12.0 / DT):
		var before := ship.velocity
		ShipDynamics.step(ship, input, DT)
		worst_step_dv = maxf(worst_step_dv, (ship.velocity - before).length())
		if stop_time < 0.0 and ship.velocity.length() < 1e-6:
			stop_time = (i + 1) * DT
	assert_less_equal(worst_step_dv, a_max * DT + 1e-6, "largest per-tick Δv under assist")
	assert_near(stop_time, 20.0 / a_max, 2.0 * DT, "time for assist to null 20 m/s drift")
	assert_vec_near(ship.velocity, Vector3.ZERO, 1e-6, "velocity after assist settles")


func test_assist_uses_weaker_reverse_thrust_to_stop_forward_motion() -> void:
	# Moving forward at 10 m/s: stopping needs reverse thrusters (2 m/s²) → 5 s,
	# not the main engine. Checks thrust budgets are direction-specific.
	var ship := _ship(Vector3(0, 0, -10.0))
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	_run(ship, input, 2.5)
	assert_near(ship.velocity.z, -5.0, 1e-3, "forward speed after 2.5 s of assisted braking")


func test_assist_does_not_fight_commanded_axis() -> void:
	# Commanding forward while drifting sideways: forward accelerates at full
	# main-engine thrust while the lateral drift is still being nulled.
	var ship := _ship(Vector3(5.0, 0, 0))
	_run(ship, ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, true), 1.0)
	var a_fwd := CONFIG.thrust_forward_n / CONFIG.mass_kg
	var a_lat := CONFIG.thrust_lateral_n / CONFIG.mass_kg
	assert_near(ship.velocity.z, -a_fwd, 1e-3, "forward speed after 1 s")
	assert_near(ship.velocity.x, 5.0 - a_lat, 1e-3, "lateral speed after 1 s of nulling")


func test_manual_torque_gives_expected_angular_acceleration() -> void:
	# Full manual pitch for 1 s: ω = τ/I · t about +X.
	var ship := _ship()
	_run(ship, ShipControlInput.create(Vector3.ZERO, Vector3(1, 0, 0), false), 1.0)
	var expected := CONFIG.max_torque_nm.x / CONFIG.inertia_kgm2.x
	assert_near(ship.angular_velocity.x, expected, 1e-4, "pitch rate after 1 s manual torque")
	assert_true(ship.forward().y > 0.0, "positive pitch raises the nose (forward.y > 0)")


func test_assist_holds_requested_rate_then_stops_rotation() -> void:
	# Full yaw-left request reaches the assist rate cap; releasing stops spin.
	var ship := _ship()
	_run(ship, ShipControlInput.create(Vector3.ZERO, Vector3(0, 1, 0), true), 5.0)
	assert_near(ship.angular_velocity.y, CONFIG.assist_max_rate_rad_s.y, 1e-5, "held yaw rate")
	_run(ship, ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true), 5.0)
	assert_vec_near(ship.angular_velocity, Vector3.ZERO, 1e-6, "angular velocity after release")


func test_orientation_stays_normalized_under_long_tumble() -> void:
	# 10 minutes of three-axis tumble: quaternion must stay unit length.
	var ship := _ship()
	ship.angular_velocity = Vector3(0.31, -0.47, 1.3)
	_run(ship, ShipControlInput.neutral(), 600.0)
	assert_near(ship.orientation.length(), 1.0, 1e-5, "orientation quaternion length")
