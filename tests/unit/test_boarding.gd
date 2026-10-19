extends TestCase
## Measures: Milestone 5 — abstract crew (complement, casualties from
## venting, command and gun-crew effects, routes through the access graph,
## crewed repairs) and boarding (spec §16 "Crew/boarding"): docking
## tolerances, boarding only over a physical connection, a target tearing
## free, a severed gangway stranding the team, outcomes set by numbers and
## roles rather than instant kills, and layout changing how boarding goes.

const DT := 0.1


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _ship(bp: ShipBlueprint, id: StringName) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


func _room(s: ShipSystems, id: String) -> int:
	for i in s.blueprint.rooms.size():
		if s.blueprint.rooms[i].id == id:
			return i
	return -1


func _roles(s: ShipSystems, role: int) -> Array[CrewRoster.Member]:
	return s.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.role == role)


## Put `b` (turned 180° about up) with its first collar facing `a`'s first
## collar, `gap` metres away, at `a`'s velocity.
func _alongside(a: ShipState, b: ShipState, gap: float) -> void:
	b.orientation = Quaternion(Vector3.UP, PI)
	var pa: Docking.Port = Docking.collars(a.systems)[0]
	var pb: Docking.Port = Docking.collars(b.systems)[0]
	b.position = pa.world_position(a) + pa.world_normal(a) * gap - b.orientation * pb.position_body
	b.velocity = a.velocity
	b.angular_velocity = Vector3.ZERO
	b.snapshot_previous()


## A world with us ("a") and a target ("b") alongside; `prepare` may edit the
## target before it is built. Returns [world, a, b].
func _setup(target_bp: ShipBlueprint = null) -> Array:
	var world := WorldSimulation.new(DT)
	var a := _ship(_template(), &"a")
	var b := _ship(target_bp if target_bp != null else _template(), &"b")
	_alongside(a, b, 15.0)
	world.add_ship(a)
	world.add_ship(b)
	return [world, a, b]


func _run(world: WorldSimulation, seconds: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < seconds:
		if until.is_valid() and until.call():
			break
		world.step()
		t += DT
	return t


## Dock, wait for the seal, send the party; returns the boarding action.
func _board(world: WorldSimulation) -> BoardingAction:
	var found := world.dock(&"a", &"b")
	if not found.has("link"):
		fail("docking refused: %s" % ", ".join(found.get("assessment", {}).get("problems", ["no collar"])))
		return null
	var link: DockingLink = found.link
	_run(world, 60.0, func() -> bool: return link.sealed())
	return world.start_boarding(link)


func _kill(s: ShipSystems, role: int) -> void:
	for m in _roles(s, role):
		m.state = CrewRoster.State.DEAD
	s.invalidate()


# --- Crew ---------------------------------------------------------------------------

func test_default_crew_fills_the_berths_by_role() -> void:
	var s := _ship(_template(), &"s").systems
	var counts := []
	for role in CrewRoster.Role.size():
		counts.append(_roles(s, role).size())
	assert_true(s.crew.members.size() == s.stats.crew_capacity, "one person per berth (%d)" % s.stats.crew_capacity)
	assert_true(counts == [2, 2, 2, 1, 4, 1, 4], "command, eng, DC, weapons, security, medical, general = %s" % [counts])
	assert_true(_roles(s, CrewRoster.Role.COMMAND).all(func(m: CrewRoster.Member) -> bool: return m.location == s.command_room()),
		"command crew start on the bridge")


func test_ship_ai_flies_with_assist_when_the_bridge_is_lost() -> void:
	var world := WorldSimulation.new(DT)
	var ship := _ship(_template(), &"s")
	world.add_ship(ship)
	_kill(ship.systems, CrewRoster.Role.COMMAND)
	ship.config = ship.systems.effective_config()
	ship.angular_velocity = Vector3(0, 0.2, 0)
	world.set_input(&"s", ShipControlInput.neutral())  # manual, no input
	_run(world, 20.0)
	assert_near(ship.angular_velocity.length(), 0.0, 1e-3, "the ship AI damps the spin even though the pilot chose manual (rad/s)")


func test_venting_a_room_hurts_its_occupants_and_command() -> void:
	var ship := _ship(_template(), &"s")
	var rate := ship.config.assist_max_rate_rad_s
	ship.systems.breach_room(ship.systems.command_room())
	ship.config = ship.systems.effective_config()
	var cmd := _roles(ship.systems, CrewRoster.Role.COMMAND)
	assert_true(cmd[0].state == CrewRoster.State.WOUNDED and cmd[1].state == CrewRoster.State.DEAD,
		"bridge vents: one commander wounded, one killed")
	assert_true(not ship.systems.has_command(), "no command crew on a pressurised bridge")
	assert_vec_near(ship.config.assist_max_rate_rad_s, rate * ShipSystems.SHIP_AI_FACTOR, 1e-6, "ship AI flies it: turn rates limited (rad/s)")
	assert_near(ship.config.thrust_forward_n, ship.systems.base_config.thrust_forward_n * ShipSystems.SHIP_AI_FACTOR, 1e-3, "and main thrust limited (N)")
	assert_true(ship.systems.event_log[-1].contains("1 killed, 1 wounded"), "log says so: %s" % ship.systems.event_log[-1])


func test_without_gun_crew_the_guns_fire_at_half_rate() -> void:
	var ship := _ship(_template(), &"s")
	var rpm := ship.config.cannon.rate_of_fire_rpm
	_kill(ship.systems, CrewRoster.Role.WEAPONS)
	ship.config = ship.systems.effective_config()
	assert_near(ship.config.cannon.rate_of_fire_rpm, rpm * ShipSystems.NO_GUN_CREW_RATE_FACTOR, 1e-6, "rate of fire (rpm)")


func test_crew_cannot_pass_sealed_or_vented_connections() -> void:
	var s := _ship(_template(), &"s").systems
	var bridge := s.command_room()
	var reactor := _room(s, "r15")
	assert_true(s.route(bridge, reactor).size() == 4, "bridge → corridor → lower corridor → reactor room")
	assert_true(s.route(bridge, reactor, false, {"h24": true}).is_empty(), "the ladder h24 sealed: no way down")
	s.breach_room(_room(s, "r8"))
	assert_true(s.route(bridge, reactor).is_empty(), "the corridor vented: no way through without suits")
	assert_true(s.route(_room(s, "r9"), reactor, true).size() == 4, "suited, the way is open")


func test_field_repair_needs_crew_who_can_get_there() -> void:
	var bp := _template()
	(bp.find("r9") as ShipBlueprint.PlacedRoom).def_id = &"workshop"
	var s := _ship(bp, &"s").systems
	s.damage_equipment(s.equipment_by_id("e28"), 30.0)
	_kill(s, CrewRoster.Role.DAMAGE_CONTROL)
	assert_true(s.field_repair_block_reason() == "", "engineers can still do it")
	_kill(s, CrewRoster.Role.ENGINEERING)
	assert_true(s.field_repair_block_reason().contains("crew"), "no damage control or engineers: %s" % s.field_repair_block_reason())
	assert_true(s.start_field_repair() == null, "and it does not start")


func test_casualties_persist_and_the_wounded_recover() -> void:
	var ship := _ship(_template(), &"s")
	ship.systems.breach_room(ship.systems.command_room())
	var p := PlayerProfile.new(1)
	p.ensure_vessel(_template())
	p.dock(ship.systems.condition(), _catalog())
	assert_true(p.vessel.dead_crew() == {"command": 1} and not p.vessel.condition.crew.has("wounded"), "dead stay dead, wounded recover: %s" % p.vessel.condition)
	p.vessel.condition.breached = []  # bridge patched at the yard
	var grid := ShipGrid.build(p.vessel.blueprint, _catalog())
	var stats := ShipStats.compute(p.vessel.blueprint, grid)
	var again := ShipSystems.create(p.vessel.blueprint, grid, stats, stats.to_ship_config("x"))
	again.apply_condition(p.vessel.condition)
	assert_true(again.crew.count(CrewRoster.State.DEAD) == 1 and again.has_command(), "next sortie: one commander short, still in command")


# --- Docking ---------------------------------------------------------------------------

func test_docking_fails_outside_the_tolerances() -> void:
	var a := _ship(_template(), &"a")
	var b := _ship(_template(), &"b")
	_alongside(a, b, 15.0)
	var ok: Dictionary = Docking.best(a, b)
	assert_true(ok.assessment.ok and ok.b_port.kind == &"collar", "15 m, matched, aligned: docks collar to collar (%s)" % ", ".join(ok.assessment.problems))
	var cases := {
		"range": func() -> void: _alongside(a, b, 40.0),
		"relative speed": func() -> void: b.velocity = a.velocity + Vector3(0, 0, 1.0),
		"turn rate": func() -> void: b.angular_velocity = Vector3(0, 0.12, 0),
		"misaligned": func() -> void: a.orientation = Quaternion(Vector3.FORWARD, deg_to_rad(35.0)),
	}
	for what in cases:
		a.orientation = Quaternion.IDENTITY
		_alongside(a, b, 15.0)
		cases[what].call()
		var s: Dictionary = Docking.assess(a, Docking.collars(a.systems)[0], b, Docking.collars(b.systems)[0])
		assert_true(not s.ok and ", ".join(s.problems).contains(what), "%s outside tolerance is refused: %s" % [what, ", ".join(s.problems)])


func test_boarding_begins_only_over_a_sealed_gangway() -> void:
	var setup := _setup()
	var world: WorldSimulation = setup[0]
	var found := world.dock(&"a", &"b")
	var link: DockingLink = found.link
	assert_true(link.state == DockingLink.State.EXTENDING, "gangway extending")
	assert_true(world.start_boarding(link) == null, "no boarding before the seal")
	var t := _run(world, 60.0, func() -> bool: return link.sealed())
	assert_near(t, Docking.COLLAR_SEAL_S, DT + 1e-6, "collar seals after (s)")
	assert_true(world.start_boarding(link) != null, "boarding can start once sealed")


func test_a_target_that_can_still_manoeuvre_tears_free() -> void:
	var setup := _setup()
	var world: WorldSimulation = setup[0]
	var a: ShipState = setup[1]
	var b: ShipState = setup[2]
	var link: DockingLink = world.dock(&"a", &"b").link
	_run(world, 60.0, func() -> bool: return link.sealed())
	assert_true(GunneryAI.can_break_contact(b), "an intact, crewed target can try")
	world.set_input(&"b", GunneryAI.break_contact(b, a))
	_run(world, 2.0)
	assert_true(link.state == DockingLink.State.SEVERED and link.reason.contains("pulled apart"), "it tears the gangway: %s" % link.reason)
	b.systems.damage_equipment(b.systems.equipment_by_id("e28"), 1000.0)
	assert_true(not GunneryAI.can_break_contact(b), "without power it cannot")


func test_a_severed_gangway_strands_the_team() -> void:
	var setup := _setup()
	var world: WorldSimulation = setup[0]
	var b: ShipState = setup[2]
	_kill(b.systems, CrewRoster.Role.GENERAL)  # nobody in the entry room
	var boarding := _board(world)
	_run(world, 120.0, func() -> bool: return boarding.phase == BoardingAction.Phase.ABOARD)
	assert_true(boarding.phase == BoardingAction.Phase.ABOARD, "the team is aboard (%s)" % BoardingAction.PHASE_NAMES[boarding.phase])
	boarding.link.release()
	boarding.withdraw()
	_run(world, 120.0, func() -> bool: return boarding.finished())
	assert_true(boarding.phase == BoardingAction.Phase.STRANDED, "no gangway, no way home: %s" % BoardingAction.PHASE_NAMES[boarding.phase])
	assert_true(boarding.team.all(func(m: CrewRoster.Member) -> bool: return m.location < 0), "the team is still on the other ship")


func test_outcome_depends_on_who_is_defending_not_on_instant_kills() -> void:
	var full := _setup()
	var hard := _board(full[0])
	_run(full[0], 600.0, func() -> bool: return hard.finished())
	var soft_setup := _setup()
	var soft_target: ShipState = soft_setup[2]
	_kill(soft_target.systems, CrewRoster.Role.SECURITY)
	var soft := _board(soft_setup[0])
	_run(soft_setup[0], 600.0, func() -> bool: return soft.finished())
	var lost := func(b: BoardingAction) -> int: return b.team.filter(func(m: CrewRoster.Member) -> bool: return not m.fit()).size()
	assert_true(soft.prize and soft.phase == BoardingAction.Phase.RETURNED, "without its security team the target is captured and the team comes home on its own (%s)" % BoardingAction.PHASE_NAMES[soft.phase])
	assert_true(soft_target.systems.captured and soft_target.systems.is_disabled(), "a captured ship is out of the fight")
	assert_true(lost.call(hard) > lost.call(soft), "the full crew costs the boarders more: %d vs %d down\n%s" % [lost.call(hard), lost.call(soft), "\n".join(hard.log)])
	assert_true(hard.elapsed > 30.0 and soft.elapsed > 30.0, "boarding takes time, not one tick (%.0f s / %.0f s)" % [hard.elapsed, soft.elapsed])


func test_layout_decides_how_long_it_takes() -> void:
	# Same ship, but its collar opens straight into the bridge instead of the
	# crew quarters two locked hatches away.
	var near_bp := _template()
	(near_bp.find("e50") as ShipBlueprint.PlacedEquipment).cell = Vector3i(2, 1, 2)
	var times := []
	for bp in [_template(), near_bp]:
		var setup := _setup(bp)
		var b: ShipState = setup[2]
		_kill(b.systems, CrewRoster.Role.SECURITY)
		var boarding := _board(setup[0])
		_run(setup[0], 600.0, func() -> bool: return boarding.finished())
		assert_true(boarding.prize, "captured (%s)" % BoardingAction.PHASE_NAMES[boarding.phase])
		times.append(boarding.elapsed)
	assert_true(times[0] > times[1] + 2.0 * BoardingAction.HATCH_CUT_S,
		"two locked hatches and two rooms more: %.0f s vs %.0f s" % [times[0], times[1]])
