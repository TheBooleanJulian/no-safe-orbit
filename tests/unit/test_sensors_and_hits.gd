extends TestCase
## Measures: RCS propellant cost per m/s no worse than the main engines;
## sensor tracks (detection range, lock, dead-reckoned estimates, staleness,
## sensors down → visual range); ricochets off steep armour (mirrored, slower)
## versus shattering head-on; outward hull normals for shell holes.

const CELL := ShipGrid.CELL_SIZE_M


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _ship(id: StringName, pos: Vector3 = Vector3.ZERO) -> ShipState:
	var bp := _template()
	var catalog := ConstructionCatalog.default_catalog()
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


func test_rcs_costs_no_more_per_metre_per_second_than_the_mains() -> void:
	var cfg := _ship(&"s").config
	assert_true(cfg.rcs_isp_s >= cfg.main_isp_s, "RCS Isp %.0f s ≥ main Isp %.0f s" % [cfg.rcs_isp_s, cfg.main_isp_s])
	# Same Δv by RCS and by main engines: RCS must not use more propellant.
	var used := []
	for axis in [Vector3(0, 0, -1), Vector3(1, 0, 0)]:
		var ship := _ship(&"s")
		var before := ship.propellant_kg
		var input := ShipControlInput.create(axis, Vector3.ZERO, false)
		var dv := 0.0
		while dv < 5.0:
			var v0 := ship.velocity
			ShipDynamics.step(ship, input, 1.0 / 60.0)
			dv += (ship.velocity - v0).length()
		used.append(before - ship.propellant_kg)
	assert_less_equal(used[1], used[0] * 1.02, "propellant for 5 m/s: RCS %.1f kg vs mains %.1f kg" % [used[1], used[0]])


func test_sensor_track_detects_estimates_and_goes_stale() -> void:
	var me := _ship(&"me")
	var them := _ship(&"them", Vector3(0, 0, -30000))
	them.velocity = Vector3(0, 0, 100)
	var track := SensorTrack.new()
	assert_near(SensorTrack.range_of(me), 25000.0, 1e-6, "sensor mast range (m)")
	assert_true(not track.update(me, them, 0.0, 0.1) and not track.detected, "30 km: beyond the 25 km mast, nothing")
	them.position = Vector3(0, 0, -20000)
	assert_true(track.update(me, them, 1.0, 0.1) and track.in_contact and track.quality(1.0) == "MEAS", "20 km: detected and measured")
	assert_true(not track.locked, "no lock beyond %.0f km" % (SensorTrack.LOCK_RANGE_M / 1000.0))
	them.position = Vector3(0, 0, -8000)
	track.update(me, them, 2.0, 0.1)
	assert_true(track.locked, "lock inside 10 km")
	# Sensors go down: the contact is now an estimate, then stale.
	me.systems.damage_equipment(me.systems.equipment_by_id("e53"), 1000.0)
	assert_near(SensorTrack.range_of(me), ShipSystems.VISUAL_RANGE_M, 1e-6, "mast destroyed: visual range only (m)")
	them.position += them.velocity * 1.0
	track.update(me, them, 3.0, 1.0)
	assert_true(not track.in_contact and track.quality(3.0) == "EST", "out of contact: estimated")
	assert_vec_near(track.estimated_position(me, 3.0), them.position, 1.0, "dead reckoning follows a steady target (m)")
	var c := track.confidence
	track.update(me, them, 10.0, 7.0)
	assert_true(track.quality(10.0) == "STALE" and track.confidence < c, "after %.0f s it is stale and confidence decays" % SensorTrack.STALE_AFTER_S)


func test_steep_hits_ricochet_and_head_on_ones_shatter() -> void:
	var gun: KineticCannonConfig = load("res://data/weapons/medium_kinetic_cannon.tres")
	var weak: KineticCannonConfig = gun.duplicate()
	weak.penetration_mm = 20.0
	for steep in [true, false]:
		var world := WorldSimulation.new()
		var target := _ship(&"t")
		world.add_ship(target)
		var com := target.systems.stats.center_of_mass_m
		# The nose section's port flank (30 mm plate, nothing in front of it).
		var aim := Vector3(2.0 * CELL, 1.5 * CELL, 2.0 * CELL) - com
		# Steep: coming in from ahead, 75° from the flank's normal; else straight in.
		var dir := (Vector3(cos(deg_to_rad(75.0)), 0, sin(deg_to_rad(75.0))) if steep else Vector3(1, 0, 0)).normalized()
		var shot := ProjectileState.new()
		shot.id = 1
		shot.shooter_id = &"nobody"
		shot.weapon = weak
		shot.position = aim - dir * 30.0
		shot.prev_position = shot.position
		shot.velocity = dir * weak.muzzle_velocity_mps
		world.projectiles().append(shot)
		for i in 3:
			world.step()
		var hits := world.take_hit_events()
		assert_true(hits.size() == 1 and hits[0].report.stopped_by_armor, "%s round is stopped by the plate" % ("steep" if steep else "head-on"))
		var bounced := world.projectiles().filter(func(p: ProjectileState) -> bool: return p.ricochet)
		if steep:
			assert_true(hits[0].report.ricochet and bounced.size() == 1, "steep: it ricochets (%s)" % hits[0].report.headline())
			if bounced.size() == 1:
				var v: Vector3 = bounced[0].velocity - target.velocity
				assert_near(v.length(), weak.muzzle_velocity_mps * WorldSimulation.RICOCHET_KEEP, 5.0, "ricochet speed (m/s)")
				assert_true(v.x < 0.0 and v.z * dir.z > 0.0, "mirrored off the flank: x reversed, along-hull motion kept (%s)" % v)
		else:
			assert_true(not hits[0].report.ricochet and bounced.is_empty(), "head-on: it shatters, no ricochet")


func test_hole_normals_point_out_of_the_hull() -> void:
	var ship := _ship(&"s")
	var com := ship.systems.stats.center_of_mass_m
	# Across the exposed upper deck, port to starboard (40 mm belt plates).
	var p := Vector3(2.0 * CELL, 2.5 * CELL, 6.5 * CELL) - com
	var r := Penetration.apply(ship.systems, p, Vector3(1, 0, 0), 400.0)
	assert_true(r.penetrated, "a 400 mm round goes in through the port flank")
	assert_vec_near(r.entry_normal_body, Vector3(-1, 0, 0), 1e-6, "entry hole faces port (out of the flank)")
	if r.exit_pen_mm > 0.0:
		assert_vec_near(r.exit_normal_body, Vector3(1, 0, 0), 1e-6, "exit hole faces starboard")


func test_a_reactor_explosion_plays_out_and_its_debris_flies_free() -> void:
	var world := WorldSimulation.new()
	var ship := _ship(&"s")
	world.add_ship(ship)
	var boom := ReactorExplosion.new()
	boom.setup(&"s", Vector3(0, 0, 4), ShipSystems.REACTOR_BLAST_RADIUS_M, 7)
	boom.step(world, 1.0, Vector3.ZERO, 0.0)
	var t := 0.0
	var first := Vector3.ZERO
	while t < 1.0:
		boom.step(world, 1.0, Vector3.ZERO, 0.1)
		t += 0.1
	# Debris flies on its own: move the ship away, the debris does not follow.
	var piece: MeshInstance3D = boom.get_child(boom.get_child_count() - 1).get_child(0)
	first = piece.position
	ship.position += Vector3(500, 0, 0)
	boom.step(world, 1.0, Vector3.ZERO, 0.1)
	assert_true(piece.position.distance_to(first) < 10.0, "debris keeps its own trajectory (moved %.1f m)" % piece.position.distance_to(first))
	assert_true(boom.position.x > 400.0, "the fireball rides with the ship")
	while not boom.finished():
		boom.step(world, 1.0, Vector3.ZERO, 0.25)
	assert_true(boom.age >= ReactorExplosion.LIFETIME_S, "it ends after %.1f s" % ReactorExplosion.LIFETIME_S)
	boom.free()


func test_shipboard_sounds_are_synthesised() -> void:
	var audio := ShipAudio.new()
	audio._ready()
	for sound in ["gun", "hit", "ricochet", "explosion", "alert", "dock"]:
		assert_true(audio.has_sound(sound), "%s is made" % sound)
	var wav: AudioStreamWAV = audio._streams["explosion"]
	assert_true(wav.data.size() > ShipAudio.MIX_RATE * 2 * 2, "the explosion lasts over 2 s")
	var loud := 0
	for i in range(0, wav.data.size(), 2):
		loud = maxi(loud, absi(wav.data.decode_s16(i)))
	assert_true(loud > 5000, "and it is not silent (peak %d)" % loud)
	audio.free()
