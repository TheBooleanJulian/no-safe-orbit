extends TestCase
## Measures: power distribution (zero-sum pips, channel effects on thrust,
## rate of fire, attitude control and repair speed) and crew orders
## (covering a lost role by walking a general crew member to its station;
## choosing what damage control patches first).

const DT := 0.1


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _ship(bp: ShipBlueprint = null) -> ShipState:
	if bp == null:
		bp = _template()
	var catalog := ConstructionCatalog.default_catalog()
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(&"s", "S", cfg)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


func test_diverting_power_is_zero_sum_and_capped() -> void:
	var s := _ship().systems
	assert_true(s.pips == [2, 2, 2], "starts balanced")
	assert_true(s.divert(ShipSystems.Channel.ENG) and s.divert(ShipSystems.Channel.ENG), "two pips into engines")
	assert_true(s.pips[ShipSystems.Channel.ENG] == 4 and s.pips[0] + s.pips[1] + s.pips[2] == ShipSystems.PIPS_TOTAL,
		"engines at 4, total still %d: %s" % [ShipSystems.PIPS_TOTAL, s.pips])
	assert_true(not s.divert(ShipSystems.Channel.ENG), "no more than 4 pips in a channel")
	s.balance_power()
	assert_true(s.pips == [2, 2, 2], "balance restores 2/2/2")


func test_channels_change_what_the_ship_can_do() -> void:
	var ship := _ship()
	var s := ship.systems
	var base := s.effective_config()
	s.divert(ShipSystems.Channel.ENG)
	s.divert(ShipSystems.Channel.ENG)
	var eng := s.effective_config()
	assert_near(eng.thrust_forward_n / base.thrust_forward_n, 1.5, 1e-6, "ENG 4 pips: 150 % thrust")
	assert_true(eng.cannon.rate_of_fire_rpm < base.cannon.rate_of_fire_rpm, "paid for by the guns: %.0f → %.0f rpm" % [base.cannon.rate_of_fire_rpm, eng.cannon.rate_of_fire_rpm])
	s.balance_power()
	s.divert(ShipSystems.Channel.WEP)
	s.divert(ShipSystems.Channel.WEP)
	var wep := s.effective_config()
	assert_near(wep.cannon.rate_of_fire_rpm / base.cannon.rate_of_fire_rpm, 1.5, 1e-6, "WEP 4 pips: 150 % rate of fire")
	assert_true(wep.thrust_forward_n < base.thrust_forward_n and wep.max_torque_nm.x < base.max_torque_nm.x, "at the cost of engines and attitude control")


func test_sys_power_speeds_up_repairs() -> void:
	var times := []
	for boost in [false, true]:
		var bp := _template()
		(bp.find("r9") as ShipBlueprint.PlacedRoom).def_id = &"workshop"
		var ship := _ship(bp)
		var s := ship.systems
		if boost:
			s.divert(ShipSystems.Channel.SYS)
			s.divert(ShipSystems.Channel.SYS)
		s.damage_equipment(s.equipment_by_id("e28"), 30.0)
		s.start_field_repair()
		var t := 0.0
		while s.repair_task != null and t < 120.0:
			s.tick(ship, DT)
			t += DT
		times.append(t)
	assert_near(times[1], times[0] / 1.5, 0.3, "SYS 4 pips: repairs 1.5× faster (%.1f s vs %.1f s)" % [times[1], times[0]])


func test_a_general_crew_member_can_take_over_the_bridge() -> void:
	var ship := _ship()
	var s := ship.systems
	for m in s.crew.members:
		if m.role == CrewRoster.Role.COMMAND:
			m.state = CrewRoster.State.DEAD
	s.invalidate()
	assert_true(not s.has_command(), "bridge crew dead: ship AI")
	assert_true(s.cover_role(CrewRoster.Role.COMMAND) == "", "a general heads to the bridge")
	var walker: String = s.crew_orders.keys()[0]
	var walk: float = s.crew_orders[walker].left_s
	assert_true(walk > 0.0, "it takes a walk (%.0f s)" % walk)
	var t := 0.0
	while not s.has_command() and t < 60.0:
		s.tick(ship, DT)
		t += DT
	assert_near(t, walk, DT + 1e-6, "command restored on arrival (s)")
	assert_true(s.crew.by_id(walker).role == CrewRoster.Role.COMMAND, "%s now holds command" % walker)
	assert_near(s.effective_config().thrust_forward_n, s.base_config.thrust_forward_n, 1e-3, "full thrust again (N)")


func test_cover_needs_a_pressurised_station_and_a_way_there() -> void:
	var s := _ship().systems
	s.breach_room(s.command_room())
	assert_true(s.cover_role(CrewRoster.Role.COMMAND).contains("no pressurised"), "nobody can take a vented bridge")


func test_player_chooses_what_damage_control_patches_first() -> void:
	var bp := _template()
	(bp.find("r9") as ShipBlueprint.PlacedRoom).def_id = &"workshop"
	var s := _ship(bp).systems
	s.damage_equipment(s.equipment_by_id("e28"), 30.0)   # reactor: first by default
	s.damage_equipment(s.equipment_by_id("e42"), 6.0)    # radiator
	assert_true(s.field_repair_target().id == "e28", "default order: reactor first")
	s.preferred_repair_id = "e42"
	assert_true(s.field_repair_target().id == "e42", "player's pick goes first")


func test_boarding_party_size_is_the_players_choice() -> void:
	var a := _ship()
	var link := DockingLink.new()
	link.state = DockingLink.State.SEALED
	link.a_port = Docking.collars(a.systems)[0]
	var b := _ship()
	link.b_port = Docking.collars(b.systems)[0]
	var party := BoardingAction.start(link, a.systems, b.systems, 3)
	assert_true(party.team.size() == 3, "a party of 3 (got %d)" % party.team.size())


# --- Damage-control actions --------------------------------------------------------

func test_switching_a_load_off_reroutes_its_power() -> void:
	var ship := _ship()
	var s := ship.systems
	s.damage_equipment(s.equipment_by_id("e28"), 0.0)
	var demand := s.power_demand_kw
	assert_true(s.set_switched_off("e41", true), "the gun can be switched off")
	assert_true(not s.equipment_by_id("e41").powered and not s.equipment_by_id("e41").working(), "a switched-off gun is unpowered")
	assert_near(demand - s.power_demand_kw, 120.0, 1e-3, "its 120 kW freed (kW)")
	assert_true(not s.set_switched_off("e28", true), "reactors make power: they can't be switched off as loads")
	s.set_switched_off("e41", false)
	assert_true(s.equipment_by_id("e41").working(), "switched back on")


func test_isolating_a_compartment_blocks_crew_routes() -> void:
	var s := _ship().systems
	var bridge := s.command_room()
	var reactor := -1
	var corridor := -1
	for i in s.blueprint.rooms.size():
		if s.blueprint.rooms[i].id == "r15":
			reactor = i
		if s.blueprint.rooms[i].id == "r8":
			corridor = i
	assert_true(not s.route(bridge, reactor).is_empty(), "bridge to reactor room: open")
	s.set_isolated(corridor, true)
	assert_true(s.route(bridge, reactor).is_empty(), "the corridor isolated: no way through")
	assert_true(not s.route(bridge, reactor, true).is_empty(), "suited boarders still cut through")
	s.set_isolated(corridor, false)
	assert_true(not s.route(bridge, reactor).is_empty(), "reopened")


func test_schematic_picks_the_system_under_the_cursor() -> void:
	var map := ShipSchematic.new()
	map.systems = _ship().systems
	map.interactive = true
	map.size = Vector2(500, 260)
	map.layout_hits()
	var c := map.center_of("e28")
	assert_true(c.x >= 0.0, "the reactor is on the all-decks map")
	assert_true(map.pick_at(c).get("id", "") == "e28", "clicking it picks the reactor")
	map.free()
