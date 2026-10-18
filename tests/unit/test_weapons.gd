extends TestCase
## Measures: kinetic cannon — inherited velocity, recoil, rate of fire,
## magazine, finite flight time, gravity on rounds, swept hits (no
## tunnelling), burn-up at the entry interface, and fire-control intercepts.

const EARTH := preload("res://data/bodies/earth.tres")
const CONFIG := preload("res://data/ships/placeholder_frigate.tres")
const DT := 1.0 / 60.0


func _fire_input() -> ShipControlInput:
	var input := ShipControlInput.neutral()
	input.fire = true
	return input


func _config_with(cannon: KineticCannonConfig) -> ShipConfig:
	var cfg: ShipConfig = CONFIG.duplicate()
	cfg.cannon = cannon
	return cfg


func _orbit_world() -> WorldSimulation:
	var world := WorldSimulation.new()
	var r0 := EARTH.radius_m + 400_000.0
	world.set_central_body(EARTH, Vec3d.new(0, r0, 0), Vec3d.new(0, 0, -EARTH.circular_speed(r0)))
	return world


func test_round_inherits_ship_velocity_plus_muzzle_velocity() -> void:
	var world := WorldSimulation.new()
	var yawed := Quaternion(Vector3.UP, 0.7) * Quaternion(Vector3.RIGHT, 0.2)
	var ship := ShipState.create(&"s", "S", CONFIG, Vector3.ZERO, Vector3(12, -3, 40), yawed)
	world.add_ship(ship)
	world.set_input(&"s", _fire_input())
	world.step()
	var rounds := world.projectiles()
	assert_true(rounds.size() == 1, "one round after first tick (got %d)" % rounds.size())
	var expected := Vector3(12, -3, 40) + ship.forward() * CONFIG.cannon.muzzle_velocity_mps
	assert_vec_near(rounds[0].velocity, expected, 1e-3, "round velocity = ship velocity + muzzle·nose (m/s)")
	assert_vec_near(rounds[0].position, ship.position + ship.orientation * CONFIG.primary_muzzle(), 1e-3, "round starts at the muzzle (m)")


func test_recoil_conserves_momentum() -> void:
	var world := WorldSimulation.new()
	var ship := ShipState.create(&"s", "S", CONFIG, Vector3.ZERO, Vector3(0, 0, -20))
	world.add_ship(ship)
	world.set_input(&"s", _fire_input())
	var m_ship := CONFIG.mass_kg
	var m_round := CONFIG.cannon.round_mass_kg
	var before := Vector3(0, 0, -20) * (m_ship + m_round)
	world.step()
	var after := ship.velocity * m_ship + world.projectiles()[0].velocity * m_round
	# Tolerance is float32 rounding at ~5×10⁶ kg·m/s; the recoil impulse is 6,000.
	assert_vec_near(after, before, 1.0, "total momentum before/after one shot (kg·m/s)")


func test_rate_of_fire_and_magazine_limit() -> void:
	var world := WorldSimulation.new()
	world.add_ship(ShipState.create(&"s", "S", CONFIG))
	world.set_input(&"s", _fire_input())
	for i in 120:  # 2 s at 240 rpm → one shot every 15 ticks
		world.step()
	assert_true(world.get_ship(&"s").rounds_fired == 8, "rounds in 2 s at 240 rpm = 8 (got %d)" % world.get_ship(&"s").rounds_fired)

	var small: KineticCannonConfig = CONFIG.cannon.duplicate()
	small.magazine_rounds = 3
	var world2 := WorldSimulation.new()
	var ship2 := ShipState.create(&"s", "S", _config_with(small))
	world2.add_ship(ship2)
	world2.set_input(&"s", _fire_input())
	for i in 300:
		world2.step()
	assert_true(ship2.rounds_fired == 3 and ship2.cannon_rounds == 0, "magazine of 3 fires exactly 3 (fired %d)" % ship2.rounds_fired)


func test_flight_time_matches_straight_line_range() -> void:
	# Stationary target 1500 m ahead. Muzzle is 34 m forward of the centre and
	# the target box's near face is 26 m aft of its centre, so the round must
	# cover 1500 − 34 − 26 = 1440 m at 1500 m/s → 0.96 s. Never instant.
	var world := WorldSimulation.new()
	world.add_ship(ShipState.create(&"a_shooter", "A", CONFIG))
	world.add_ship(ShipState.create(&"b_target", "B", CONFIG, Vector3(0, 0, -1500)))
	world.set_input(&"a_shooter", _fire_input())
	world.step()
	world.set_input(&"a_shooter", ShipControlInput.neutral())
	var hit_tick := -1
	for i in 120:
		world.step()
		var hits := world.take_hit_events()
		if not hits.is_empty():
			hit_tick = hits[0].tick
			break
	assert_true(hit_tick > 0, "round hit the target")
	# Fired at the end of tick 1; the hit is recorded in the tick it lands.
	assert_near((hit_tick - 1) * DT, 1440.0 / 1500.0, DT, "time of flight (s)")


func test_gravity_acts_on_rounds() -> void:
	# A round's planet-centred trajectory must match independent two-body
	# integration from the same initial state, and differ from a straight line.
	var world := _orbit_world()
	world.add_ship(ShipState.create(&"s", "S", CONFIG, Vector3.ZERO, Vector3.ZERO, Quaternion(Vector3.RIGHT, -PI / 2)))  # nose down
	world.set_input(&"s", _fire_input())
	world.step()
	world.set_input(&"s", ShipControlInput.neutral())
	var shot := world.projectiles()[0]
	var r := world.pci_position(shot.position)
	var v := world.pci_velocity(shot.velocity)
	var straight_line := r.plus(v.times(20.0))  # same start, no gravity
	var mu: float = EARTH.mu_m3_s2
	for i in 1200:  # 20 s, reference leapfrog in PCI doubles
		world.step()
		v = v.plus(r.times(-mu / pow(r.length(), 3.0) * DT * 0.5))
		r = r.plus(v.times(DT))
		v = v.plus(r.times(-mu / pow(r.length(), 3.0) * DT * 0.5))
	var sim := world.pci_position(shot.position)
	assert_less_equal(sim.minus(r).length(), 1.0, "round PCI position vs reference two-body integration after 20 s (m)")
	# ½·g·t² ≈ 0.5 × 8.7 × 400 ≈ 1,700 m of fall relative to a straight line.
	assert_true(sim.minus(straight_line).length() > 1000.0,
		"round deviates from a gravity-free line by %.0f m (expected ≈1,700 m)" % sim.minus(straight_line).length())


func test_fast_round_does_not_tunnel_through_target() -> void:
	# 6 km/s crossing shot: 100 m per tick against a 20 m wide hit box. End
	# positions straddle the box; only a swept test catches it.
	var world := WorldSimulation.new()
	var target := ShipState.create(&"target", "T", CONFIG)
	world.add_ship(target)
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"nobody"
	shot.position = Vector3(-150, 1.5, -4)
	shot.prev_position = shot.position
	shot.velocity = Vector3(6000, 0, 0)
	world.projectiles().append(shot)
	var hits: Array[HitEvent] = []
	for i in 5:
		world.step()
		hits.append_array(world.take_hit_events())
	assert_true(hits.size() == 1, "exactly one hit recorded (got %d)" % hits.size())
	assert_true(world.projectiles().is_empty(), "round consumed by the hit")
	if hits.size() == 1:
		assert_near(hits[0].point_body.x, -10.0, 1e-3, "impact on the hit box's −X face (m)")


func test_segment_box_cases() -> void:
	var c := Vector3.ZERO
	var h := Vector3(1, 1, 1)
	assert_near(HitTest.segment_box(Vector3(-5, 0, 0), Vector3(5, 0, 0), c, h), 0.4, 1e-6, "through the middle: entry fraction")
	assert_near(HitTest.segment_box(Vector3(-5, 3, 0), Vector3(5, 3, 0), c, h), -1.0, 0.0, "passes above: miss")
	assert_near(HitTest.segment_box(Vector3(0, 0, 0), Vector3(5, 0, 0), c, h), 0.0, 0.0, "starts inside: immediate")
	assert_near(HitTest.segment_box(Vector3(-5, 0, 0), Vector3(-2, 0, 0), c, h), -1.0, 0.0, "stops short: miss")


func test_round_coasts_far_and_reenters_on_time() -> void:
	# Fired straight down at 1.5 km/s from 400 km: it leaves the engagement
	# (far mode, analytic orbit) and is removed when its orbit crosses 100 km.
	var world := _orbit_world()
	world.add_ship(ShipState.create(&"s", "S", CONFIG, Vector3.ZERO, Vector3.ZERO, Quaternion(Vector3.RIGHT, -PI / 2)))
	world.set_input(&"s", _fire_input())
	world.step()
	world.set_input(&"s", ShipControlInput.neutral())
	var shot := world.projectiles()[0]
	var orbit := OrbitElements.from_state(EARTH.mu_m3_s2, world.pci_position(shot.position), world.pci_velocity(shot.velocity))
	var predicted := world.sim_time + orbit.time_to_radius_descending(EARTH.entry_radius_m())
	var went_far := false
	var gone_at := -1.0
	while world.sim_time < predicted + 10.0:
		world.step()
		went_far = went_far or not world.far_projectiles().is_empty()
		if gone_at < 0.0 and world.round_count() == 0:
			gone_at = world.sim_time
	assert_true(went_far, "round left the engagement and coasted in far mode")
	assert_near(gone_at, predicted, 1.5, "removed at its predicted entry-interface crossing (s)")


func test_rounds_never_expire() -> void:
	var world := WorldSimulation.new()
	world.add_ship(ShipState.create(&"s", "S", CONFIG))
	world.set_input(&"s", _fire_input())
	world.step()
	world.set_input(&"s", ShipControlInput.neutral())
	for i in 60 * 60:  # a minute later
		world.step()
	assert_true(world.round_count() == 1, "the round is still flying after 60 s (%d)" % world.round_count())


func test_intercept_time_known_geometry() -> void:
	# Stationary target 1000 m ahead, 1000 m/s round → exactly 1 s.
	assert_near(FireControl.intercept_time(Vector3(0, 0, -1000), Vector3.ZERO, 1000.0), 1.0, 1e-6, "head-on stationary TOF (s)")
	# Crossing at 100 m/s: |r + v t| = s t → t = r / sqrt(s² − v²).
	var t := FireControl.intercept_time(Vector3(0, 0, -1000), Vector3(100, 0, 0), 1000.0)
	var expected := 1000.0 / sqrt(1000.0 * 1000.0 - 100.0 * 100.0)
	assert_near(t, expected, 0.01, "crossing-target TOF (s)")
	var lead := FireControl.lead_point(Vector3(0, 0, -1000), Vector3(100, 0, 0), t)
	assert_vec_near(lead, Vector3(100.0 * expected, 0, -1000), 1.0, "lead point (m)")
	assert_near(lead.length(), 1000.0 * t, 1.0, "round can reach the lead point in t (m)")
	# Receding faster than the round: no solution.
	assert_near(FireControl.intercept_time(Vector3(0, 0, -1000), Vector3(0, 0, -1200), 1000.0), -1.0, 0.0, "no solution when outrun")


func test_lead_solution_produces_a_hit_in_orbit() -> void:
	# End to end: target 2 km ahead crossing at 40 m/s, both in orbit. Point the
	# nose at the lead point, fire once; the round must hit at ≈ predicted TOF.
	var world := _orbit_world()
	var shooter := ShipState.create(&"a_shooter", "A", CONFIG)
	var target := ShipState.create(&"b_target", "B", CONFIG, Vector3(0, 0, -2000), Vector3(40, 0, 0))
	world.add_ship(shooter)
	world.add_ship(target)
	var muzzle := shooter.position + shooter.orientation * CONFIG.primary_muzzle()
	var aim_target := target.position + target.orientation * CONFIG.hit_box_center
	var tof := FireControl.intercept_time(aim_target - muzzle, target.velocity - shooter.velocity, CONFIG.cannon.muzzle_velocity_mps)
	var aim := FireControl.lead_point(aim_target - muzzle, target.velocity - shooter.velocity, tof).normalized()
	shooter.orientation = Quaternion(Vector3.FORWARD, aim)
	shooter.snapshot_previous()
	world.set_input(&"a_shooter", _fire_input())
	world.step()
	world.set_input(&"a_shooter", ShipControlInput.neutral())
	var hit: HitEvent = null
	for i in 240:
		world.step()
		var hits := world.take_hit_events()
		if not hits.is_empty():
			hit = hits[0]
			break
	assert_true(hit != null, "lead-aimed round hit the crossing target (predicted TOF %.3f s)" % tof)
	if hit != null:
		# The aim point is the box centre; the hit lands on its surface, so the
		# recorded tick is at or slightly before the predicted time.
		assert_near((hit.tick - 1) * DT, tof, 0.05, "actual vs predicted time of flight (s)")


func test_every_mount_fires() -> void:
	var cfg: ShipConfig = CONFIG.duplicate()
	cfg.cannon_muzzles_body = PackedVector3Array([Vector3(-5, 0, -30), Vector3(5, 0, -30)])
	var world := WorldSimulation.new()
	var ship := ShipState.create(&"s", "S", cfg)
	world.add_ship(ship)
	world.set_input(&"s", _fire_input())
	world.step()
	assert_true(world.projectiles().size() == 2 and ship.cannon_rounds == cfg.cannon.magazine_rounds - 2,
		"both mounts fired one round each (%d in flight)" % world.projectiles().size())
	assert_true(world.projectiles()[0].position.x < 0.0 and world.projectiles()[1].position.x > 0.0, "rounds leave from their own muzzles")
