extends TestCase
## Measures: two-body gravity through the free-falling local frame, orbit
## stability and energy drift, burn response, ellipse-vs-entry rule at the
## 100 km entry interface, orbital elements, assist under gravity, rebasing.

const EARTH := preload("res://data/bodies/earth.tres")
const CONFIG := preload("res://data/ships/placeholder_frigate.tres")
const ALT_400 := 400_000.0


func _r0() -> float:
	return EARTH.radius_m + ALT_400


## World whose frame origin is on a circular 400 km orbit: +Y radial, −Z prograde.
func _orbit_world(dt: float = WorldSimulation.DEFAULT_FIXED_DT) -> WorldSimulation:
	var world := WorldSimulation.new(dt)
	world.set_central_body(EARTH, Vec3d.new(0, _r0(), 0), Vec3d.new(0, 0, -EARTH.circular_speed(_r0())))
	return world


func _add(world: WorldSimulation, id: StringName, pos := Vector3.ZERO, vel := Vector3.ZERO) -> ShipState:
	var ship := ShipState.create(id, String(id), CONFIG, pos, vel)
	world.add_ship(ship)
	return ship


func _energy(world: WorldSimulation, ship: ShipState) -> float:
	return world.orbit_of(ship).specific_energy


func _period(r: float) -> float:
	return TAU * sqrt(r * r * r / EARTH.mu_m3_s2)


func test_earth_data() -> void:
	assert_near(EARTH.mu_m3_s2, 3.986004418e14, 1.0, "Earth μ (m³/s²)")
	assert_near(EARTH.radius_m, 6_371_000.0, 0.0, "Earth mean radius (m)")
	assert_near(EARTH.entry_interface_altitude_m, 100_000.0, 0.0, "entry interface = Kármán line (m)")
	assert_true(EARTH.validate().is_empty(), "earth.tres validates")


func test_circular_orbit_bounded_over_ten_orbits() -> void:
	# A ship 2 km above the frame origin on its own circular orbit drifts away
	# from the origin (different period), so this also exercises rebasing.
	# 10 orbits at dt = 1 s (energy error of leapfrog scales with dt²).
	var world := _orbit_world(1.0)
	var r_ship := _r0() + 2000.0
	var v_rel := Vector3(0, 0, -(EARTH.circular_speed(r_ship) - EARTH.circular_speed(_r0())))
	var ship := _add(world, &"s", Vector3(0, 2000, 0), v_rel)
	world.anchor_id = &"s"
	var e0 := _energy(world, ship)
	var r_min := INF
	var r_max := 0.0
	var max_drift := 0.0
	for i in ceili(10.0 * _period(r_ship)):
		world.step()
		var r := world.pci_position(ship.position).length()
		r_min = minf(r_min, r)
		r_max = maxf(r_max, r)
		max_drift = maxf(max_drift, absf((_energy(world, ship) - e0) / e0))
	assert_less_equal(r_max / r_ship - 1.0, 0.001, "max radius deviation over 10 orbits (fraction)")
	assert_less_equal(1.0 - r_min / r_ship, 0.001, "min radius deviation over 10 orbits (fraction)")
	assert_less_equal(max_drift, 1e-4, "relative specific-energy drift over 10 orbits")
	assert_true(ship.is_active(), "ship still in orbit")


func test_one_orbit_at_game_timestep() -> void:
	# Same check at the real 60 Hz tick, one full orbit, ship offset 1 km
	# along-track so the tidal term is exercised.
	var world := _orbit_world()
	var ship := _add(world, &"s", Vector3(0, 0, -1000))
	world.anchor_id = &"s"
	var e0 := _energy(world, ship)
	var r0 := world.pci_position(ship.position).length()
	var worst_r := 0.0
	for i in ceili(_period(_r0()) / world.fixed_dt):
		world.step()
		worst_r = maxf(worst_r, absf(world.pci_position(ship.position).length() / r0 - 1.0))
	assert_less_equal(worst_r, 0.001, "radius deviation over one orbit at 60 Hz (fraction)")
	assert_less_equal(absf((_energy(world, ship) - e0) / e0), 1e-6, "energy drift over one orbit at 60 Hz")


func test_prograde_burn_raises_opposite_apsis() -> void:
	# 5 s of main engine along the velocity vector (nose is −Z = prograde).
	var world := _orbit_world(0.1)
	var ship := _add(world, &"s")
	world.anchor_id = &"s"
	world.set_input(&"s", ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, false))
	for i in 50:
		world.step()
	world.set_input(&"s", ShipControlInput.neutral())
	var el := world.orbit_of(ship)
	assert_true(el.apoapsis_radius - _r0() > 100_000.0,
		"apoapsis raised by %.1f km (expected > 100 km for ≈50 m/s)" % ((el.apoapsis_radius - _r0()) / 1000.0))
	assert_near(el.periapsis_radius, _r0(), 2000.0, "periapsis stays at burn altitude (m)")
	# Coast to the far side and measure the actual radius there.
	var t_apo := el.time_to_apoapsis()
	for i in roundi(t_apo / world.fixed_dt):
		world.step()
	var r_far := world.pci_position(ship.position).length()
	assert_near(r_far, el.apoapsis_radius, el.apoapsis_radius * 1e-4, "radius half an orbit later = predicted apoapsis (m)")


func test_retrograde_burn_lowers_opposite_apsis() -> void:
	var world := _orbit_world(0.1)
	var ship := _add(world, &"s")
	world.anchor_id = &"s"
	world.set_input(&"s", ShipControlInput.create(Vector3(0, 0, 1), Vector3.ZERO, false))  # reverse thrusters
	for i in 100:  # 10 s × 2 m/s² = 20 m/s
		world.step()
	var el := world.orbit_of(ship)
	assert_true(el.periapsis_radius < _r0() - 50_000.0,
		"periapsis lowered by %.1f km (expected > 50 km)" % ((_r0() - el.periapsis_radius) / 1000.0))
	assert_near(el.apoapsis_radius, _r0(), 2000.0, "apoapsis stays at burn altitude (m)")


func test_below_circular_speed_is_an_ellipse_not_an_entry() -> void:
	# Spec rule: dropping below circular speed does not by itself end the orbit.
	# −50 m/s at 400 km → periapsis ≈ 230 km, above the 100 km interface.
	var world := _orbit_world(1.0)
	var ship := _add(world, &"s", Vector3.ZERO, Vector3(0, 0, 50.0))
	world.anchor_id = &"s"
	var el := world.orbit_of(ship)
	assert_true(world.pci_velocity(ship.velocity).length() < EARTH.circular_speed(_r0()), "speed below local circular speed")
	assert_true(el.periapsis_radius > EARTH.entry_radius_m(), "periapsis %.1f km is above the entry interface" % ((el.periapsis_radius - EARTH.radius_m) / 1000.0))
	assert_true(not el.intersects_radius(EARTH.entry_radius_m()), "predictor says no entry")
	var min_alt := INF
	for i in ceili(2.0 * el.period):
		world.step()
		min_alt = minf(min_alt, world.altitude_of(ship))
	assert_true(ship.is_active(), "ship still in orbit after two orbits")
	assert_near(min_alt, el.periapsis_radius - EARTH.radius_m, 500.0, "lowest altitude = predicted periapsis altitude (m)")


func test_trajectory_crossing_the_entry_interface_is_detected_and_timed() -> void:
	# −120 m/s at 400 km → periapsis well below 100 km: entry is predicted, and
	# the simulated crossing happens when predicted.
	var world := _orbit_world(0.1)
	var ship := _add(world, &"s", Vector3.ZERO, Vector3(0, 0, 120.0))
	world.anchor_id = &"s"
	var el := world.orbit_of(ship)
	var predicted := el.time_to_radius_descending(EARTH.entry_radius_m())
	assert_true(el.intersects_radius(EARTH.entry_radius_m()), "predictor flags entry")
	assert_true(predicted > 0.0 and predicted < el.period, "entry predicted within one orbit (%.1f s)" % predicted)
	var guard := ceili(el.period / world.fixed_dt)
	while ship.is_active() and guard > 0:
		world.step()
		guard -= 1
	assert_true(ship.status == ShipState.Status.ENTERED_ATMOSPHERE, "ship status after crossing 100 km")
	assert_near(ship.status_time, predicted, 0.5, "simulated vs predicted entry time (s)")
	var tick_count := world.tick
	world.step()
	assert_true(world.tick == tick_count + 1 and ship.position == ship.prev_position, "entered ship is no longer integrated")


func test_orbit_elements_known_values() -> void:
	var mu: float = EARTH.mu_m3_s2
	var r := _r0()
	var circ := OrbitElements.from_state(mu, Vec3d.new(0, r, 0), Vec3d.new(0, 0, -sqrt(mu / r)))
	assert_near(circ.eccentricity, 0.0, 1e-12, "circular eccentricity")
	assert_near(circ.period, _period(r), 1e-6, "circular period (s)")
	# Independent reference: 2π√((6,771 km)³/μ) = 5,544.9 s ≈ 92.4 min.
	assert_near(circ.period, 5544.9, 1.0, "400 km orbit period ≈ 92.4 min (s)")
	# Ellipse from periapsis at r with vis-viva speed for apoapsis 2r.
	var a := 1.5 * r
	var vp := sqrt(mu * (2.0 / r - 1.0 / a))
	var ell := OrbitElements.from_state(mu, Vec3d.new(r, 0, 0), Vec3d.new(0, vp, 0))
	assert_near(ell.eccentricity, 1.0 / 3.0, 1e-9, "ellipse eccentricity")
	assert_near(ell.periapsis_radius, r, 1e-3, "ellipse periapsis (m)")
	assert_near(ell.apoapsis_radius, 2.0 * r, 1e-3, "ellipse apoapsis (m)")
	assert_near(ell.time_to_apoapsis(), ell.period * 0.5, 1e-6, "periapsis → apoapsis = half period (s)")
	var apo_point := ell.point_at_angle(PI)
	assert_vec_near(Vector3(apo_point.x, apo_point.y, apo_point.z) / 1000.0, Vector3(-2.0 * r, 0, 0) / 1000.0, 1e-3,
		"path point 180° ahead is apoapsis (km)")
	var esc := OrbitElements.from_state(mu, Vec3d.new(r, 0, 0), Vec3d.new(0, sqrt(2.0 * mu / r) * 1.1, 0))
	assert_true(not esc.is_bound() and esc.apoapsis_radius == INF, "above escape speed: unbound, no apoapsis")


func test_assist_orbit_hold_spends_no_delta_v() -> void:
	# Assist on, translation hold off ("hold orbit"): coasting in free fall is
	# free — the old inertial-stop behaviour would burn ~8.7 m/s every second.
	var world := _orbit_world(0.1)
	var ship := _add(world, &"s")
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_translation = false
	world.set_input(&"s", input)
	for i in 6000:  # 10 minutes
		world.step()
	assert_near(ship.delta_v_expended, 0.0, 1e-9, "Δv spent holding orbit for 10 min (m/s)")
	assert_near(world.pci_position(ship.position).length(), _r0(), 1.0, "radius after 10 min (m)")


func test_assist_target_hold_matches_velocity_without_fighting_gravity() -> void:
	# Player 1 km from a co-orbiting target, drifting 5 m/s relative. Matching
	# velocity costs ≈5 m/s plus tidal station-keeping (~3n²·d·t ≈ 2 m/s over
	# 10 min), versus ~5,200 m/s to hover against gravity.
	var world := _orbit_world(0.1)
	var target := _add(world, &"target", Vector3(0, 0, -1000))
	var player := _add(world, &"player", Vector3.ZERO, Vector3(5, 0, 0))
	world.anchor_id = &"player"
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_target_id = &"target"
	world.set_input(&"player", input)
	for i in 6000:
		world.step()
	var rel := (player.velocity - target.velocity).length()
	assert_less_equal(rel, 0.01, "relative speed to target after 10 min (m/s)")
	assert_less_equal(player.delta_v_expended, 10.0, "Δv spent matching and holding target velocity (m/s)")


func test_rebase_preserves_pci_state() -> void:
	var world := _orbit_world()
	var a := _add(world, &"a", Vector3(4999, 0, 0), Vector3(120, 0, 0))
	var b := _add(world, &"b", Vector3(-3000, 200, 800), Vector3(-4, 1, 2))
	world.anchor_id = &"a"
	var b_pci_before := world.pci_position(b.position)
	var b_vel_before := world.pci_velocity(b.velocity)
	world.step()  # a crosses 5 km → rebase
	assert_less_equal(a.position.length(), 1e-6, "anchor at origin after rebase (m)")
	# b moved one tick at its velocity; gravity adds only ½·g·dt² ≈ 1.2 mm.
	var expected := b_pci_before.plus(b_vel_before.times(world.fixed_dt))
	assert_less_equal(world.pci_position(b.position).minus(expected).length(), 0.01, "other ship PCI position across rebase (m)")
	assert_vec_near(b.velocity, Vector3(-4, 1, 2), 1e-3, "local velocity unchanged by rebase")
