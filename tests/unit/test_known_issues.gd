extends TestCase
## Measures: fixes to known issues — stores are kept between sorties and
## bought back at the yard; craft refuel and rearm from their carrier's
## stores; the enemy keeps a fighting range, jinks, holds fire when hot and
## flees when beaten; mixed gun batteries each lead the target themselves.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _ship(id: StringName, pos: Vector3 = Vector3.ZERO, bp: ShipBlueprint = null) -> ShipState:
	if bp == null:
		bp = _template()
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


func test_stores_are_bought_back_at_the_yard() -> void:
	var p := PlayerProfile.new(2)
	p.ensure_vessel(_template())
	p.vessel.condition = {"stores": {"propellant_kg": 30_000.0, "rounds": 200}}
	var need := ServiceYard.resupply_needs(p.vessel, _catalog())
	assert_near(need.propellant_kg, 50_000.0, 1.0, "50 t of propellant to top up")
	assert_true(need.rounds == 200 and need.credits == 50 + 20, "200 rounds; 70 credits (%d)" % need.credits)
	p.credits = 30
	var line := ServiceYard.resupply(p.vessel, p, _catalog())
	assert_true(line.contains("Partly") and p.credits == 0, "short of credits: partly (%s)" % line)
	assert_near(float(p.vessel.condition.stores.propellant_kg), 60_000.0, 1.0, "30 credits bought 30 t first")
	p.credits = 500
	ServiceYard.resupply(p.vessel, p, _catalog())
	assert_true(not p.vessel.condition.has("stores"), "topped up: full again")


func test_craft_refuel_and_rearm_from_the_carrier() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c")
	world.add_ship(carrier)
	var wing := AirWing.for_ship(carrier)
	var fighter: AirWing.Craft
	for c in wing.crafts:
		if not c.is_drone():
			fighter = c
	fighter.propellant_fraction = 0.5
	fighter.ammo = 0
	fighter.service_left_s = 0.01
	var prop_before := carrier.propellant_kg
	var rounds_before := carrier.cannon_rounds
	wing.update(world, DT)
	assert_true(fighter.propellant_fraction > 0.99 and fighter.ammo == fighter.config.cannon.magazine_rounds, "the fighter is full again")
	assert_near(prop_before - carrier.propellant_kg, 0.5 * fighter.config.propellant_capacity_kg, 0.01, "its propellant came from the carrier (kg)")
	assert_true(carrier.cannon_rounds < rounds_before, "its rounds came from the carrier's magazine (%d → %d)" % [rounds_before, carrier.cannon_rounds])


func test_the_enemy_keeps_range_jinks_cools_and_runs() -> void:
	var me := _ship(&"me")
	var them := _ship(&"them", Vector3(0, 0, -800))
	var close := GunneryAI.combat(them, me, 3.0)
	var away := them.orientation.inverse() * (them.position - me.position).normalized()
	assert_true(close.translation.dot(away) > 0.3, "too close: it backs off (%s)" % close.translation)
	var a := GunneryAI.combat(them, me, 0.0).translation
	var b := GunneryAI.combat(them, me, 4.0).translation
	assert_true(a.distance_to(b) > 0.3, "it weaves (jinks) over time")
	them.systems.temperature_k = ShipSystems.THROTTLE_TEMP_K - 5.0
	assert_true(not GunneryAI.combat(them, me, 1.0).fire, "running hot, it holds fire")
	them.systems.temperature_k = ShipSystems.NOMINAL_TEMP_K
	var keep := [EquipmentDefinition.Kind.REACTOR, EquipmentDefinition.Kind.MAIN_ENGINE, EquipmentDefinition.Kind.CANNON,
		EquipmentDefinition.Kind.POWER_DISTRIBUTION, EquipmentDefinition.Kind.PROPELLANT_TANK]
	for e in them.systems.equipment:
		# Everything else gone; what it needs to run is badly hurt but working.
		them.systems.damage_equipment(e, e.max_hp * 0.8 if keep.has(e.def.kind) else 1000.0)
	them.systems.solve_power()
	them.config = them.systems.effective_config()
	assert_true(GunneryAI.should_flee(them), "beaten (%.0f%% intact) but able to run" % (them.systems.intact_fraction() * 100.0))
	var run := GunneryAI.combat(them, me, 1.0)
	assert_true(run.translation.z < -0.5 and not run.fire, "it burns away and stops shooting")


func test_a_mixed_battery_leads_each_gun_on_its_own() -> void:
	var bp := _template()
	bp.add_equipment(&"railgun", Vector3i(4, 2, 6), &"dorsal")
	var world := WorldSimulation.new(DT)
	var me := _ship(&"me", Vector3.ZERO, bp)
	var them := _ship(&"them", Vector3(1500, 300, -2500))
	them.velocity = Vector3(-120, 0, 0)
	world.add_ship(me)
	world.add_ship(them)
	assert_true(me.config.mount_cannon(0).muzzle_velocity_mps != me.config.mount_cannon(1).muzzle_velocity_mps, "two different guns")
	var input := GunneryAI.command(me, them)
	var corr := world._lead_correction(me, input, 1)
	assert_true(corr.length() > 10.0, "the railgun's own lead differs from the cannon's by %.0f m" % corr.length())
	input.lead_target_id = &""
	assert_true(world._lead_correction(me, input, 1) == Vector3.ZERO, "no lock: no correction")


func test_a_medic_treats_the_wounded_in_flight() -> void:
	var ship := _ship(&"s")
	var sys := ship.systems
	var patient: CrewRoster.Member
	for m in sys.crew.members:
		if m.role == CrewRoster.Role.SECURITY:
			patient = m
			break
	patient.state = CrewRoster.State.WOUNDED
	var t := 0.0
	while t < ShipSystems.MEDICAL_TREATMENT_S + 1.0 and patient.state == CrewRoster.State.WOUNDED:
		sys.tick(ship, 0.5)
		t += 0.5
	assert_true(patient.fit(), "treated by the medic in %.0f s" % t)
	for m in sys.crew.members:
		if m.role == CrewRoster.Role.MEDICAL:
			m.state = CrewRoster.State.DEAD
	patient.state = CrewRoster.State.WOUNDED
	for i in 200:
		sys.tick(ship, 0.5)
	assert_true(not patient.fit(), "no medic: the wounded wait for the yard")


func test_craft_fly_in_formation() -> void:
	assert_true(CraftAI.escort_offset(1).distance_to(CraftAI.escort_offset(2)) > 30.0 and CraftAI.escort_offset(0) != CraftAI.escort_offset(1),
		"escorts take separate stations")
	var me := _ship(&"me")
	var target := _ship(&"t", Vector3(0, 0, -3000))
	var a := ShipControlInput.neutral()
	var b := ShipControlInput.neutral()
	var craft := ShipState.create(&"f", "F", (load("res://data/catalog/equipment/fighter_bay.tres") as EquipmentDefinition).craft, Vector3(0, 0, -100))
	CraftAI.attack(craft, target, CraftAI.STRIKE_RANGE_M, 0, a, 0)
	CraftAI.attack(craft, target, CraftAI.STRIKE_RANGE_M, 0, b, 1)
	assert_true(a.translation.distance_to(b.translation) > 0.05 or a.rotation.distance_to(b.rotation) > 0.05, "a wingman takes its own approach")
	assert_true(me.is_active(), "the carrier is untouched")


func test_the_enemy_spends_its_power_like_a_fighter() -> void:
	var me := _ship(&"me")
	var them := _ship(&"them", Vector3(0, 0, -2000))
	GunneryAI.combat(them, me, 0.0)
	assert_true(them.systems.pips[2] == 3, "healthy and fighting: weapons pips up (%s)" % str(them.systems.pips))
