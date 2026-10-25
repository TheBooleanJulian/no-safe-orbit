extends TestCase
## Measures: play-test batch 9, part 4 — crew. Fighters need a pilot aboard
## to launch (drones don't): the pilot flies out with the craft, comes back
## with it, and is lost with it; v11 saves get general crew posted as
## pilots. Crew gain levels with sorties or training, specialists at the
## top, and are paid each sortie; gunners' and engineers' levels make guns
## faster and reactors stronger. A department takes a dropped crew member.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _frigate_plan(pilots: bool) -> Array:
	var v := ShipInstance.new()
	v.name = "Test"
	v.blueprint = BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	v.ensure_crew(_catalog())
	if not pilots:
		for c: Dictionary in v.crew:
			if int(c.role) == CrewRoster.Role.PILOT:
				c.role = CrewRoster.Role.GENERAL
	return v.crew


func _carrier(plan: Array) -> ShipState:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config("c")
	var s := ShipState.create(&"c", "c", cfg, Vector3.ZERO)
	s.side = &"player"
	var sys := ShipSystems.create(bp, grid, stats, cfg)
	sys.use_crew_plan(plan)
	s.attach_systems(sys)
	return s


func _fighter(wing: AirWing) -> AirWing.Craft:
	for c in wing.crafts:
		if not c.is_drone():
			return c
	return null


func test_a_fighter_needs_a_pilot_and_takes_them_along() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _carrier(_frigate_plan(false))
	world.add_ship(carrier)
	var wing := AirWing.for_ship(carrier)
	world.wings.append(wing)
	var f := _fighter(wing)
	var why := wing.launch_block_reason(world, f)
	print("    measured: no pilot — %s" % why)
	assert_true(why.contains("no pilot"), "no pilot aboard: grounded")
	var drone: AirWing.Craft = null
	for c in wing.crafts:
		if c.is_drone():
			drone = c
	assert_true(drone == null or wing.launch_block_reason(world, drone) == "", "a drone flies itself")
	# With a pilot.
	world = WorldSimulation.new(DT)
	carrier = _carrier(_frigate_plan(true))
	world.add_ship(carrier)
	wing = AirWing.for_ship(carrier)
	world.wings.append(wing)
	f = _fighter(wing)
	assert_true(wing.launch(world, f) == "", "with a pilot: launched")
	var pilot := carrier.systems.crew.by_id(f.pilot_id)
	assert_true(pilot != null and pilot.role == CrewRoster.Role.PILOT and pilot.location == -1 and pilot.busy, "the pilot is out with it")
	assert_true(wing.launch_block_reason(world, f).contains("already out"), "one craft, one pilot")
	wing.recall(f)
	for i in roundi(90.0 / DT):
		world.step()
		if f.status == AirWing.Status.DOCKED:
			break
	print("    measured: recovered %s; pilot at %d, busy %s" % [f.status == AirWing.Status.DOCKED, pilot.location, pilot.busy])
	assert_true(f.status == AirWing.Status.DOCKED and pilot.location >= 0 and not pilot.busy and f.pilot_id == "", "back aboard with it")
	# Shot down: the pilot is lost with it.
	f.service_left_s = 0.0
	assert_true(wing.launch(world, f) == "", "out again")
	world.get_ship(f.id).hull_damage = 1.0e6
	world.get_ship(f.id).status = ShipState.Status.DESTROYED
	world.step()
	assert_true(f.status == AirWing.Status.LOST and pilot.state == CrewRoster.State.DEAD, "lost with the craft")


func test_a_v11_save_posts_pilots() -> void:
	var path := "user://test_b9_crew_profile.json"
	for s in ["", ".bak", ".tmp", ".v11"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var p := PlayerProfile.new(4)
	p.ensure_vessel(BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()))
	p.vessel.crew = _frigate_plan(false)
	var d := p.to_dict()
	d.schema_version = 11
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	var pilots := q.vessel.crew.filter(func(c: Dictionary) -> bool: return int(c.role) == CrewRoster.Role.PILOT).size()
	print("    measured: v11 → v%d: %d pilot%s posted for the frigate's fighter" % [q.loaded_schema if false else PlayerProfile.SCHEMA_VERSION, pilots, "" if pilots == 1 else "s"])
	assert_true(q.loaded_schema == 11 and pilots == 1, "a general crew member posted as its pilot")
	assert_true(FileAccess.file_exists(path + ".v11"), "the v11 original is kept")
	for s in ["", ".bak", ".tmp", ".v11"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))


func test_crew_rise_with_sorties_and_training_and_are_paid() -> void:
	var p := PlayerProfile.new(6)
	p.ensure_vessel(BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()))
	p.vessel.ensure_crew(_catalog())
	p.credits = 1000
	var wages := p.wages()
	var lines := PackedStringArray()
	for k in 3:
		lines.append_array(p.dock({}, _catalog()))
	var c: Dictionary = p.vessel.crew[0]
	print("    measured: wages %d cr a sortie (%d crew); after 3 sorties %s is %s; credits %d" % [wages, p.vessel.crew.size(), c.name,
		CrewRoster.title(int(c.role), int(c.skill)), p.credits])
	assert_true(wages == p.vessel.crew.size() * PlayerProfile.WAGE_BASE, "rookies: %d cr each" % PlayerProfile.WAGE_BASE)
	assert_true(int(c.sorties) == 3 and int(c.skill) == 1 and " ".join(lines).contains("is now Able"), "three sorties: Able")
	assert_true(p.credits == 1000 - wages * 2 - p.wages(), "paid each sortie (the third at the new rate)")
	# Training: a level for credits, up to a specialist.
	p.credits = 1000
	assert_true(p.train(0) == "" and int(c.skill) == 2 and p.credits == 1000 - PlayerProfile.TRAINING_COSTS[2], "trained to Veteran")
	assert_true(p.train(0) == "" and int(c.skill) == 3, "and to specialist")
	print("    measured: %s the %s (%s)" % [c.name, CrewRoster.title(int(c.role), 3), CrewRoster.ROLE_NAMES[int(c.role)]])
	assert_true(CrewRoster.title(int(c.role), 3) == CrewRoster.SPECIALIST_TITLES[int(c.role)] and p.train(0).contains("already"), "no further")
	p.credits = 0
	assert_true(p.train(1).contains("costs"), "not without credits")


func test_skilled_gunners_and_engineers_count() -> void:
	var plan := _frigate_plan(true)
	var base := _carrier(plan.duplicate(true))
	for c: Dictionary in plan:
		if int(c.role) in [CrewRoster.Role.WEAPONS, CrewRoster.Role.ENGINEERING]:
			c.skill = 3
	var vets := _carrier(plan)
	var rof0 := base.systems.effective_config().cannon.rate_of_fire_rpm
	var rof3 := vets.systems.effective_config().cannon.rate_of_fire_rpm
	var out0 := base.systems.reactor_output()
	var out3 := vets.systems.reactor_output()
	print("    measured: specialist gunners %.0f → %.0f rpm; specialist engineers reactor ×%.3f" % [rof0, rof3, out3 / out0])
	assert_near(rof3 / rof0, 1.0 + 3 * ShipSystems.GUNNER_SKILL_STEP, 1e-3, "gunners fire faster")
	assert_near(out3 / out0, 1.0 + 3 * ShipSystems.ENGINEER_SKILL_STEP, 1e-3, "engineers get more from the reactor")


func test_a_department_takes_a_dropped_crew_member() -> void:
	var dept := CrewDepartment.new()
	dept.role = CrewRoster.Role.PILOT
	var got := []
	dept.crew_dropped.connect(func(i: int, r: int) -> void: got.append([i, r]))
	assert_true(dept._can_drop_data(Vector2.ZERO, {"crew_index": 4}) and not dept._can_drop_data(Vector2.ZERO, "x"), "takes a crew badge only")
	dept._drop_data(Vector2.ZERO, {"crew_index": 4})
	assert_true(got == [[4, CrewRoster.Role.PILOT]], "posts them to its role")
	dept.free()
