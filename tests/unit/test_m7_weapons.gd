extends TestCase
## Measures: Milestone 7 — guided missiles (guidance, fuse, point-defence
## counterplay), the anti-ship, EMP and nuclear warheads, EMP hardening,
## launcher stock in the save and its restock at the yard, and that every
## template and enemy design still validates.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _bp(path: String = BlueprintIO.DEFAULT_TEMPLATE) -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(path, errors)


## A template with a launcher of `launcher` on a free exterior face.
func _armed(launcher: StringName) -> ShipBlueprint:
	var bp := _bp()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	EnemyFactory._fit_launcher(bp, _catalog(), launcher, rng)
	return bp


func _ship(id: StringName, bp: ShipBlueprint, pos: Vector3 = Vector3.ZERO, vel: Vector3 = Vector3.ZERO) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos, vel)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


func _launcher(sys: ShipSystems) -> ShipSystems.EquipmentState:
	for e in sys.equipment:
		if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER:
			return e
	return null


## A shooter with `launcher` at the origin and a cutter (no point defence)
## `range_m` ahead; the world holds both.
func _duel(launcher: StringName, range_m: float, target_bp: ShipBlueprint = null) -> WorldSimulation:
	var world := WorldSimulation.new(DT)
	world.add_ship(_ship(&"a", _armed(launcher)))
	world.add_ship(_ship(&"b", target_bp if target_bp != null else _bp("res://data/blueprints/cutter_mk1.json"), Vector3(0, 0, -range_m)))
	world.set_input(&"a", ShipControlInput.neutral())
	world.set_input(&"b", ShipControlInput.neutral())
	return world


## Steps until no missile is left in flight (or `max_s`); the link events.
func _fly_out(world: WorldSimulation, max_s: float) -> PackedStringArray:
	var events := PackedStringArray()
	var t := 0.0
	while t < max_s:
		world.step()
		events.append_array(world.take_link_events())
		t += DT
		if world.missiles.is_empty():
			break
	return events


func test_every_launcher_and_hardened_part_is_valid() -> void:
	for id in [&"missile_rack", &"emp_launcher", &"nuclear_launcher", &"sensor_mast_hardened", &"power_distribution_unit_hardened"]:
		var def: EquipmentDefinition = _catalog().equipment.get(id)
		assert_true(def != null and def.validate().is_empty(), "%s loads and is valid" % id)
	assert_true(_catalog().equipment[&"missile_rack"].rarity == Rarity.Tier.UNCOMMON
		and _catalog().equipment[&"emp_launcher"].rarity == Rarity.Tier.RARE
		and _catalog().equipment[&"nuclear_launcher"].rarity == Rarity.Tier.LEGENDARY, "rack uncommon, EMP rare, nuclear legendary")
	assert_true(_catalog().equipment[&"sensor_mast_hardened"].mass_kg > _catalog().equipment[&"sensor_mast"].mass_kg, "hardening costs mass")
	var sys := _ship(&"a", _armed(&"missile_rack")).systems
	assert_true(_launcher(sys) != null and not sys.blueprint.equipment.is_empty(), "a rack fits the template")
	assert_true(sys.missile_count() == {"Anti-ship missile": 12}, "twelve anti-ship missiles aboard (%s)" % sys.missile_count())


func test_guidance_hits_a_manoeuvring_target() -> void:
	var world := _duel(&"missile_rack", 3000.0)
	var target := world.get_ship(&"b")
	# The target strafes hard sideways and up the whole time (no assist).
	world.set_input(&"b", ShipControlInput.create(Vector3(1, 0.6, 0), Vector3.ZERO, false))
	assert_true(world.launch_missile(&"a", &"b") == "", "launched")
	assert_true(world.missiles.size() == 1 and world.missiles_at(&"b").size() == 1, "one missile after b")
	var events := _fly_out(world, 40.0)
	assert_true(target.hits_taken > 0 and Array(events).any(func(l: String) -> bool: return l.contains("hit")),
		"it caught the jinking target within 40 s (%s)" % "; ".join(events))
	assert_true(world.missiles.is_empty() and not world.ship_ids().any(func(id: StringName) -> bool: return String(id).contains("msl")),
		"the missile is gone after detonating")


func test_anti_ship_warhead_penetrates_and_blasts() -> void:
	var world := _duel(&"missile_rack", 2000.0)
	var target := world.get_ship(&"b")
	world.launch_missile(&"a", &"b")
	var hits: Array[HitEvent] = []
	var t := 0.0
	while t < 30.0 and hits.is_empty():
		world.step()
		hits.append_array(world.take_hit_events())
		t += DT
	assert_true(hits.size() == 1 and hits[0].shooter_id == &"a", "one warhead hit, credited to the shooter")
	assert_true(hits[0].report != null and hits[0].report.penetrated, "the shaped charge penetrated")
	var blasts := target.systems.take_explosions()
	assert_true(not blasts.is_empty() and str(blasts[0].lines[0]).contains("warhead"), "and the warhead blast went off inside")
	var bursts := world.take_bursts()
	assert_true(bursts.size() == 1 and int(bursts[0].kind) == MissileConfig.Warhead.ANTI_SHIP, "one burst for the views")


func test_point_defence_shoots_down_an_incoming_missile() -> void:
	# The frigate template carries two point-defence turrets.
	var world := _duel(&"missile_rack", 4000.0, _bp())
	var target := world.get_ship(&"b")
	world.launch_missile(&"a", &"b")
	var events := _fly_out(world, 40.0)
	assert_true(Array(events).any(func(l: String) -> bool: return l.contains("shot down")), "point defence shot it down (%s)" % "; ".join(events))
	assert_true(target.hits_taken == 0, "before it reached the hull")
	var spent := target.pd_rounds_capacity - target.pd_rounds
	assert_true(spent > 0, "spending rounds from its magazine (%d)" % spent)


func test_own_point_defence_and_guns_ignore_our_missiles() -> void:
	var world := _duel(&"missile_rack", 6000.0, _bp())
	var shooter := world.get_ship(&"a")
	world.launch_missile(&"a", &"b")
	for i in 120:
		world.step()
	assert_true(world.missiles.size() == 1 and world.missiles[0].is_active(), "our missile flies on past our own point defence")
	var spent := shooter.pd_rounds_capacity - shooter.pd_rounds
	assert_true(spent == 0, "our turrets held fire")


func test_launcher_reload_and_stock() -> void:
	var world := _duel(&"missile_rack", 5000.0)
	var sys := world.get_ship(&"a").systems
	assert_true(world.launch_missile(&"a", &"b") == "", "first away")
	assert_true(world.launch_missile(&"a", &"b") != "", "the tube is cycling")
	for i in int(ShipSystems.LAUNCHER_CYCLE_S / DT) + 2:
		world.step()
	assert_true(world.launch_missile(&"a", &"b") == "", "cycled: second away")
	var cap := _launcher(sys).def.missile_capacity
	assert_true(sys.missiles_left(_launcher(sys)) == cap - 2, "%d left" % (cap - 2))
	var none := WorldSimulation.new(DT)
	none.add_ship(_ship(&"x", _bp()))
	none.add_ship(_ship(&"y", _bp(), Vector3(0, 0, -3000)))
	assert_true(none.launch_missile(&"x", &"y") == "no missile launcher fitted", "no launcher, no missile")


func test_emp_resets_exposed_electronics_and_spares_the_hardened() -> void:
	var ship := _ship(&"s", _bp())
	var s := ship.systems
	var sensor: ShipSystems.EquipmentState
	var pdu: ShipSystems.EquipmentState
	var engine: ShipSystems.EquipmentState
	for e in s.equipment:
		match e.def.kind:
			EquipmentDefinition.Kind.SENSOR:
				sensor = e
			EquipmentDefinition.Kind.POWER_DISTRIBUTION:
				pdu = e
			EquipmentDefinition.Kind.MAIN_ENGINE:
				engine = e
	s.emp(1.0)
	assert_near(sensor.disrupted_s, ShipSystems.EMP_RESET_S, 1e-6, "an exposed sensor mast resets for 20 s")
	assert_true(not sensor.working() and s.disrupted().size() > 0, "and is down meanwhile")
	if pdu != null:
		assert_near(pdu.disrupted_s, ShipSystems.EMP_RESET_S * ShipSystems.EMP_INTERNAL_FACTOR, 1e-6, "an internal unit sees half")
	assert_true(engine.disrupted_s == 0.0 and engine.working(), "engines are mechanical: unaffected")
	for i in 22:
		s.tick(ship, 1.0)
	assert_true(sensor.disrupted_s == 0.0 and sensor.working() and s.disrupted().is_empty(), "back online after the reset")
	# The hardened mast rides out a weaker pulse that resets the plain one.
	var hard := _ship(&"h", _bp())
	var hs := hard.systems
	for e in hs.equipment:
		if e.def.kind == EquipmentDefinition.Kind.SENSOR:
			e.def = _catalog().equipment[&"sensor_mast_hardened"]
	s.emp(0.6)
	hs.emp(0.6)
	var hard_sensor: ShipSystems.EquipmentState
	for e in hs.equipment:
		if e.def.kind == EquipmentDefinition.Kind.SENSOR:
			hard_sensor = e
	assert_true(sensor.disrupted_s > 10.0 and hard_sensor.disrupted_s == 0.0, "plain resets (%.1f s), hardened survives" % sensor.disrupted_s)


func test_emp_warhead_in_flight() -> void:
	var world := _duel(&"emp_launcher", 3000.0)
	var target := world.get_ship(&"b")
	var hull_before := 0.0
	for m in target.systems.modules:
		hull_before += m.structure
	world.launch_missile(&"a", &"b")
	var events := _fly_out(world, 40.0)
	assert_true(not target.systems.disrupted().is_empty(), "its electronics are resetting (%s)" % "; ".join(events))
	var hull_after := 0.0
	for m in target.systems.modules:
		hull_after += m.structure
	assert_near(hull_after, hull_before, 1e-6, "no structural damage from an EMP")
	assert_true(target.hits_taken == 0, "and no hit")


func test_nuclear_armour_shields_the_crew_and_heat_spikes() -> void:
	var stripped := _bp()
	stripped.armor.clear()
	var bare := _ship(&"bare", stripped).systems
	var bp := stripped.duplicate_blueprint()
	var grid := ShipGrid.build(bp, _catalog())
	for c: Vector3i in grid.module_at:
		if grid.plateable_faces(c).has(&"dorsal"):
			bp.armor[ShipBlueprint.plate_key(c, &"dorsal")] = ShipBlueprint.PLATE_THICK_MM
	var plated := _ship(&"plated", bp).systems
	assert_true(plated.facing_armor_mm(Vector3.UP) > bare.facing_armor_mm(Vector3.UP) + 50.0, "the plates face the burst")
	var t0 := bare.temperature_k
	bare.nuclear(2.8, Vector3.UP)
	plated.nuclear(2.8, Vector3.UP)
	var dead := func(s: ShipSystems) -> int:
		return s.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.state == CrewRoster.State.DEAD).size()
	assert_true(dead.call(bare) > 0 and dead.call(plated) == 0, "bare hull: %d dead; behind armour: none" % dead.call(bare))
	var dose := 2.8 / (1.0 + bare.facing_armor_mm(Vector3.UP) / 60.0)
	assert_near(bare.temperature_k - t0, minf(ShipSystems.NUKE_HEAT_K * dose, ShipSystems.NUKE_HEAT_MAX_K), 1e-3, "heat spike from the dose")
	assert_true(not bare.disrupted().is_empty(), "with an EMP on top")


func test_nuclear_burst_imparts_no_momentum() -> void:
	var world := _duel(&"nuclear_launcher", 3000.0)
	var target := world.get_ship(&"b")
	var v0 := target.velocity
	world.launch_missile(&"a", &"b")
	var events := _fly_out(world, 60.0)
	assert_true(Array(events).any(func(l: String) -> bool: return l.contains("detonated")), "it went off (%s)" % "; ".join(events))
	assert_vec_near(target.velocity, v0, 1e-3, "no blast wave in vacuum: the target's velocity is unchanged")
	assert_true(target.systems.temperature_k > ShipSystems.NOMINAL_TEMP_K + 20.0, "but it is hot")


func test_missiles_persist_and_restock_for_credits() -> void:
	var cat := _catalog()
	var p := PlayerProfile.new(4)
	p.ensure_vessel(_armed(&"missile_rack"))
	var ship := _ship(&"p", p.vessel.blueprint)
	var e := _launcher(ship.systems)
	ship.systems.missiles_used[e.id] = 3
	var after := ship.systems.condition()
	after["stores"] = {"propellant_kg": ship.propellant_kg, "rounds": ship.cannon_rounds, "missiles": ship.systems.missile_count()}
	p.dock(after, cat)
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	var again := _ship(&"p", q.vessel.blueprint)
	again.systems.apply_condition(q.vessel.condition)
	assert_true(again.systems.missiles_left(_launcher(again.systems)) == e.def.missile_capacity - 3, "three fewer after the save round trip")
	var unit := e.def.missile.unit_credits
	var need := ServiceYard.resupply_needs(q.vessel, cat)
	assert_true(need.missiles == 3 and need.missile_credits == 3 * unit, "three to restock at %d cr (%s)" % [unit, need])
	q.credits = 2 * unit + 1
	var line := ServiceYard.resupply(q.vessel, q, cat)
	assert_true(line.contains("Partly") and int(q.vessel.condition.missiles_used[e.id]) == 1 and q.credits == 1,
		"%d cr buys two (%s)" % [2 * unit + 1, line])
	q.credits = 500
	ServiceYard.resupply(q.vessel, q, cat)
	assert_true(not q.vessel.condition.has("missiles_used") and q.credits == 500 - unit, "the last one: full again")
	assert_true(unit <= 10 and cat.equipment[&"nuclear_launcher"].missile.unit_credits <= 200, "restocking is cheap")


func test_templates_and_enemy_designs_validate() -> void:
	var cat := _catalog()
	for path in ["res://data/blueprints/frigate_mk1.json", "res://data/blueprints/corvette_mk1.json", "res://data/blueprints/cutter_mk1.json"]:
		var bp := _bp(path)
		assert_true(not ShipValidator.validate(bp, cat).has_errors(), "%s is valid" % path)
	var template := _bp()
	var launchers := {}
	for mission in range(1, 11):
		var bp := EnemyFactory.design(mission, template, cat)
		assert_true(not ShipValidator.validate(bp, cat).has_errors(), "mission %d enemy is valid" % mission)
		for e in bp.equipment:
			if cat.equipment.has(e.def_id) and cat.equipment[e.def_id].kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER:
				launchers[mission] = launchers.get(mission, []) + [e.def_id]
	assert_true(not launchers.has(1) and not launchers.has(3), "no missiles early on")
	assert_true(range(4, 11).all(func(m: int) -> bool: return launchers.has(m) and launchers[m].has(&"missile_rack")),
		"a missile rack from mission 4 (%s)" % launchers)
	assert_true(range(6, 11).any(func(m: int) -> bool: return launchers[m].has(&"emp_launcher")), "and sometimes EMP from mission 6")
	var guns := {}
	for mission in range(2, 11):
		for e in EnemyFactory.design(mission, template, cat).equipment:
			guns[e.def_id] = true
	assert_true(guns.has(&"kinetic_cannon"), "the gun upgrade is now the heavy cannon")
