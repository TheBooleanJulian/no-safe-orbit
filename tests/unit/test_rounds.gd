extends TestCase
## Measures: rounds that never expire — exact far-orbit propagation, rounds
## returning on their orbits to hit (even their own ship), recoil torque,
## momentum delivered by impacts, and rounds that go through and fly on.

const EARTH := preload("res://data/bodies/earth.tres")
const FIXTURE := preload("res://data/ships/placeholder_frigate.tres")
const CELL := ShipGrid.CELL_SIZE_M


func _template_ship(id: StringName) -> ShipState:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	var catalog := ConstructionCatalog.default_catalog()
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


func test_propagation_matches_geometry_and_integration() -> void:
	var mu: float = EARTH.mu_m3_s2
	var r := EARTH.radius_m + 400_000.0
	var v := sqrt(mu / r)
	var period := TAU * sqrt(r * r * r / mu)
	var q := OrbitElements.propagate(mu, Vec3d.new(r, 0, 0), Vec3d.new(0, v, 0), period * 0.25)
	assert_vec_near(q[0].to_vector3() / 1000.0, Vector3(0, r, 0) / 1000.0, 1e-3, "circular orbit, quarter period: 90° on (km)")
	var many := OrbitElements.propagate(mu, Vec3d.new(r, 0, 0), Vec3d.new(0, v, 0), period * 10.0 + 60.0)
	var one := OrbitElements.propagate(mu, Vec3d.new(r, 0, 0), Vec3d.new(0, v, 0), 60.0)
	assert_less_equal(many[0].minus(one[0]).length(), 1.0, "10 whole orbits change nothing (m)")
	# Elliptic: compare with a fine leapfrog over half an orbit.
	var r0 := Vec3d.new(r, 0, 0)
	var v0 := Vec3d.new(0, v * 1.1, 300.0)
	var x := r0.copy()
	var w := v0.copy()
	var dt := 0.05
	for i in roundi(2700.0 / dt):
		w = w.plus(x.times(-mu / pow(x.length(), 3.0) * dt * 0.5))
		x = x.plus(w.times(dt))
		w = w.plus(x.times(-mu / pow(x.length(), 3.0) * dt * 0.5))
	var p := OrbitElements.propagate(mu, r0, v0, 2700.0)
	assert_less_equal(p[0].minus(x).length(), 50.0, "elliptic propagation vs fine leapfrog after 45 min (m)")
	# Hyperbolic: energy conserved.
	var vh := Vec3d.new(0, sqrt(2.0 * mu / r) * 1.3, 0)
	var e0 := vh.dot(vh) * 0.5 - mu / r
	var h := OrbitElements.propagate(mu, Vec3d.new(r, 0, 0), vh, 3600.0)
	var e1 := h[1].dot(h[1]) * 0.5 - mu / h[0].length()
	assert_near(e1 / e0, 1.0, 1e-8, "hyperbolic energy ratio after 1 h")


func test_round_returns_on_its_orbit_and_hits_half_an_orbit_later() -> void:
	# A round given a 1° cross-track kick has the ship's period, so its orbit
	# crosses the ship's again at the opposite node — half an orbit later, when
	# the ship is there too. It drifts ~120 km away (far mode) and comes back.
	var world := WorldSimulation.new(0.1)
	var r := EARTH.radius_m + 400_000.0
	var v := sqrt(EARTH.mu_m3_s2 / r)
	world.set_central_body(EARTH, Vec3d.new(0, r, 0), Vec3d.new(0, 0, -v))
	var ship := ShipState.create(&"ship", "S", FIXTURE)
	world.add_ship(ship)
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"ship"  # its own ship: allowed once armed
	shot.weapon = FIXTURE.cannon
	var kick := Vector3(v * sin(deg_to_rad(1.0)), 0, v * (1.0 - cos(deg_to_rad(1.0))))
	# Leaves from the ship itself (arming keeps it from hitting on the way out;
	# a phase offset would make it cross the ship's plane ahead of it).
	shot.position = Vector3.ZERO
	shot.prev_position = shot.position
	shot.velocity = kick
	world.projectiles().append(shot)
	var half := PI * sqrt(r * r * r / EARTH.mu_m3_s2)
	var went_far := false
	var hit_at := -1.0
	while world.sim_time < half + 120.0 and hit_at < 0.0:
		world.step()
		went_far = went_far or not world.far_projectiles().is_empty()
		for ev in world.take_hit_events():
			hit_at = world.sim_time
	assert_true(went_far, "round left the engagement (far mode)")
	assert_true(hit_at > 0.0, "round came back around and hit its own ship")
	assert_near(hit_at, half, 60.0, "hit about half an orbit after firing (s)")


func test_recoil_kicks_the_ship_and_its_spin() -> void:
	var cfg: ShipConfig = FIXTURE.duplicate()
	cfg.cannon_muzzles_body = PackedVector3Array([Vector3(0, 5, -20)])  # above the CoM
	var world := WorldSimulation.new()
	var ship := ShipState.create(&"s", "S", cfg)
	world.add_ship(ship)
	var fire := ShipControlInput.neutral()
	fire.fire = true
	world.set_input(&"s", fire)
	world.step()
	var p := cfg.cannon.round_mass_kg * cfg.cannon.muzzle_velocity_mps
	assert_near(ship.velocity.z, p / cfg.mass_kg, 1e-6, "pushed aft by m·v / M (m/s)")
	# −r × p with r = (0, 5, −20), p = (0, 0, −m·v): nose pitches up (+X).
	var expected := -Vector3(0, 5, -20).cross(Vector3(0, 0, -p)) / cfg.inertia_kgm2
	assert_vec_near(ship.angular_velocity, expected, 1e-7, "recoil spin from an off-centre muzzle (rad/s)")
	assert_true(ship.angular_velocity.x > 0.0, "a muzzle above the CoM kicks the nose up")


func test_impact_pushes_and_spins_the_target() -> void:
	var world := WorldSimulation.new()
	var target := _template_ship(&"t")
	world.add_ship(target)
	# 20 mm round (stopped by the nose armour) striking off-centre, head-on.
	var weak: KineticCannonConfig = FIXTURE.cannon.duplicate()
	weak.penetration_mm = 20.0
	var com := target.systems.stats.center_of_mass_m
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"nobody"
	shot.weapon = weak
	shot.position = Vector3(3.5 * CELL, 1.5 * CELL, -20.0) - com
	shot.prev_position = shot.position
	shot.velocity = Vector3(0, 0, weak.muzzle_velocity_mps)
	world.projectiles().append(shot)
	for i in 3:
		world.step()
	var hits := world.take_hit_events()
	assert_true(hits.size() == 1 and hits[0].report.stopped_by_armor, "round stopped by armour")
	var j := weak.round_mass_kg * weak.muzzle_velocity_mps
	assert_near(target.velocity.z, j / target.mass_kg(), 1e-6, "target pushed by the full round momentum (m/s)")
	assert_true(target.angular_velocity.length() > 1e-7, "off-centre hit spins the target (%s)" % target.angular_velocity)
	assert_true(world.round_count() == 0, "stopped round is gone")


func test_overpenetrating_round_flies_on_slower() -> void:
	var world := WorldSimulation.new()
	var target := _template_ship(&"t")
	world.add_ship(target)
	var heavy: KineticCannonConfig = FIXTURE.cannon.duplicate()
	heavy.penetration_mm = 400.0
	var com := target.systems.stats.center_of_mass_m
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"nobody"
	shot.weapon = heavy
	# Side-on through the empty deck 2 of the fuselage: thin and fast.
	shot.position = Vector3(-20.0, 7.5, 6.0 * CELL) - com
	shot.prev_position = shot.position
	shot.velocity = Vector3(1500, 0, 0)
	world.projectiles().append(shot)
	var report: DamageReport = null
	for i in 3:
		world.step()
		for ev in world.take_hit_events():
			report = ev.report
	assert_true(report != null and report.exit_pen_mm > 0.0, "went through the hull")
	assert_true(world.round_count() == 1, "one round still flying beyond the ship")
	if world.round_count() == 1 and report != null:
		var out := world.projectiles()[0]
		var expected := 1500.0 * pow(report.exit_pen_mm / report.entry_pen_mm, 1.0 / 1.4)
		assert_near(out.velocity.length(), expected, 1.0, "speed matches leftover penetration (m/s)")
		assert_true(out.position.x > target.systems.stats.hull_bounds_m.size.x * 0.5 - 5.0, "it is past the far side")
	assert_true(report.path_body.size() >= 3 and not report.events.is_empty(), "path and events recorded for the replay")


func test_incoming_round_warning() -> void:
	var world := WorldSimulation.new()
	var ship := ShipState.create(&"s", "S", FIXTURE)
	world.add_ship(ship)
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"enemy"
	shot.position = Vector3(0, 0, -3000)
	shot.velocity = Vector3(0, 0, 1000)
	world.projectiles().append(shot)
	assert_near(Hud.incoming_round_time(world, ship), 3.0, 0.01, "head-on round 3 km out at 1 km/s: impact in 3 s")
	shot.position = Vector3(500, 0, -3000)
	assert_near(Hud.incoming_round_time(world, ship), -1.0, 0.0, "a round passing 500 m wide raises no warning")
