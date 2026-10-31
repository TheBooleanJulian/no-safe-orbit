extends TestCase
## Measures: play-test batch 6 — "guns can auto fire but at reduced rate of
## fire" and "enemies still feel slightly too strong when it's not a 1v1":
## automation fires at its policy's share of the rated rate (a hand on the
## trigger always at full rate); enemy leads fire at 70 %, wingmen at 45 %;
## wingmen are fitted as for earlier missions; suited crew keep command of a
## vented bridge (one breach used to disable the ship).

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _ship(id: StringName, pos: Vector3) -> ShipState:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func test_auto_fire_has_its_own_rate_and_the_trigger_is_full_rate() -> void:
	var p := ShipPolicy.preset("Standard")
	assert_near(p.autofire_rate, 0.5, 1e-6, "auto-fire at half the guns' rate by default")
	assert_near(p.trigger_rate(true), 1.0, 1e-6, "a hand on the trigger: full rate")
	assert_near(p.trigger_rate(false), 0.5, 1e-6, "automation alone: its own rate")
	p.autofire_rate = 0.25
	var q := ShipPolicy.from_dict(p.to_dict())
	assert_near(q.autofire_rate, 0.25, 1e-6, "saved with the vessel's policy")
	var d := p.to_dict()
	d.erase("autofire_rate")
	assert_near(ShipPolicy.from_dict(d).autofire_rate, 0.5, 1e-6, "older policies get the default")
	d["autofire_rate"] = 7.0
	assert_near(ShipPolicy.from_dict(d).autofire_rate, 1.0, 1e-6, "never above the rated rate")


func test_half_rate_fires_half_as_often() -> void:
	var counts := []
	for rate in [1.0, 0.5]:
		var world := WorldSimulation.new(DT)
		var s := _ship(&"s", Vector3.ZERO)
		world.add_ship(s)
		for i in roundi(10.0 / DT):
			var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
			input.fire = true
			input.fire_rate = rate
			world.set_input(&"s", input)
			world.step()
		counts.append(s.rounds_fired)
	print("    measured: 10 s on the trigger — %d rounds at full rate, %d at half" % [counts[0], counts[1]])
	assert_true(counts[0] > 0 and absi(counts[1] * 2 - counts[0]) <= 2, "half the rate, half the rounds")


func test_enemy_leads_and_wingmen_fire_slower() -> void:
	assert_near(EnemyFactory.policy(5, 0).autofire_rate, EnemyFactory.LEAD_FIRE_RATE, 1e-6, "the lead at 70 %")
	assert_near(EnemyFactory.policy(5, 1).autofire_rate, EnemyFactory.WINGMAN_FIRE_RATE, 1e-6, "wingmen at 45 %")
	var world := WorldSimulation.new(DT)
	var shooter := _ship(&"e", Vector3.ZERO)
	var target := _ship(&"p", Vector3(0, 0, -2000))
	world.add_ship(shooter)
	world.add_ship(target)
	var input := GunneryAI.combat(shooter, target, 0.0, EnemyFactory.policy(5, 1))
	assert_near(input.fire_rate, EnemyFactory.WINGMAN_FIRE_RATE, 1e-6, "their gunnery fires at that rate")


func test_wingmen_are_fitted_as_for_earlier_missions() -> void:
	var t := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	assert_true(EnemyFactory.kit_mission(7, 0) == 7 and EnemyFactory.kit_mission(7, 1) == 5 and EnemyFactory.kit_mission(7, 2) == 4,
		"lead 7, wingmen 5 and 4")
	assert_true(EnemyFactory.kit_mission(2, 2) == 1, "never below mission 1")
	var plates := []
	for v in 3:
		plates.append(EnemyFactory.design(7, t, _catalog(), v).armor.size())
	print("    measured: mission 7 armour plates — lead %d, wingmen %d and %d" % plates)
	assert_true(plates[1] < plates[0] and plates[2] < plates[0], "the wingmen carry less armour")


func test_suited_crew_keep_command_of_a_vented_bridge() -> void:
	var s := _ship(&"s", Vector3.ZERO)
	var sys := s.systems
	var bridge := -1
	for i in sys.blueprint.rooms.size():
		if sys.room_role(i) == &"command":
			bridge = i
	assert_true(bridge >= 0, "the frigate has a bridge")
	sys.rooms[bridge].pressurized = false
	sys.invalidate()
	assert_true(sys.disabled_reason() == "command room lost", "unsuited: a vented bridge loses command")
	sys.suited = true
	sys.invalidate()
	assert_true(sys.disabled_reason() == "", "at general quarters (suits on) the crew keep command")
