extends TestCase
## Measures: fixed-timestep clock, frame-rate independence, interpolation,
## deterministic results, config validation and relative-motion maths.

const CONFIG := preload("res://data/ships/placeholder_frigate.tres")


func _world_with_burning_ship() -> WorldSimulation:
	var world := WorldSimulation.new()
	var ship := ShipState.create(&"a", "A", CONFIG, Vector3.ZERO, Vector3(1, 2, 3))
	world.add_ship(ship)
	world.set_input(&"a", ShipControlInput.create(Vector3(0.3, -0.5, -1), Vector3(0.2, 0.4, -0.6), true))
	return world


func test_frame_rate_does_not_change_results() -> void:
	# Same 2 s of real time fed as steady 60 fps vs jittery frames must give
	# bit-identical simulation state (same number of fixed ticks).
	var steady := _world_with_burning_ship()
	for i in 120:
		steady.advance(1.0 / 60.0)
	var jittery := _world_with_burning_ship()
	var pattern: Array[float] = [0.004, 0.031, 0.0105, 0.021, 0.0005]  # sums to 1/15 s
	for i in 30:
		for d in pattern:
			jittery.advance(d)
	assert_true(steady.tick == jittery.tick, "tick count steady=%d jittery=%d" % [steady.tick, jittery.tick])
	var a := steady.get_ship(&"a")
	var b := jittery.get_ship(&"a")
	assert_vec_near(b.position, a.position, 1e-9, "position independent of frame pacing")
	assert_vec_near(b.velocity, a.velocity, 1e-9, "velocity independent of frame pacing")


func test_advance_returns_interpolation_fraction() -> void:
	# Half a tick of real time: no step yet, alpha ≈ 0.5.
	var world := _world_with_burning_ship()
	var alpha := world.advance(world.fixed_dt * 0.5)
	assert_true(world.tick == 0, "no tick before a full fixed_dt elapsed")
	assert_near(alpha, 0.5, 1e-6, "interpolation alpha after half a tick")


func test_long_stall_is_capped_and_recorded() -> void:
	# A 1 s hitch runs at most MAX_STEPS_PER_ADVANCE ticks and logs dropped time.
	var world := _world_with_burning_ship()
	world.advance(1.0)
	assert_true(world.tick == WorldSimulation.MAX_STEPS_PER_ADVANCE, "ticks after 1 s hitch = %d" % world.tick)
	assert_true(world.dropped_time > 0.8, "dropped time recorded (%s s)" % world.dropped_time)


func test_ship_without_input_coasts() -> void:
	var world := WorldSimulation.new()
	world.add_ship(ShipState.create(&"drifter", "D", CONFIG, Vector3.ZERO, Vector3(0, 0, -10)))
	for i in 60:
		world.step()
	assert_vec_near(world.get_ship(&"drifter").position, Vector3(0, 0, -10), 1e-4, "1 s coast with default input")


func test_placeholder_config_is_valid() -> void:
	var problems := CONFIG.validate()
	assert_true(problems.is_empty(), "placeholder frigate config problems: %s" % ", ".join(problems))
	var broken := ShipConfig.new()
	broken.mass_kg = 0.0
	assert_true(not broken.validate().is_empty(), "zero-mass config is rejected")


func test_range_and_range_rate_for_head_on_closure() -> void:
	# Target 1000 m ahead, closing at 30 m/s combined: range rate −30.
	var r := RelativeMotion.range_between(Vector3.ZERO, Vector3(0, 0, -1000))
	var rr := RelativeMotion.range_rate(Vector3.ZERO, Vector3(0, 0, -10), Vector3(0, 0, -1000), Vector3(0, 0, 20))
	assert_near(r, 1000.0, 1e-6, "range")
	assert_near(rr, -30.0, 1e-6, "range rate (negative = closing)")


func test_range_rate_zero_for_pure_crossing_motion() -> void:
	# Target moving perpendicular to the line of sight: instantaneous range rate 0.
	var rr := RelativeMotion.range_rate(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -500), Vector3(40, 0, 0))
	assert_near(rr, 0.0, 1e-6, "crossing-target range rate")
