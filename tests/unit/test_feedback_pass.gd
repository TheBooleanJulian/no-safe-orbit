extends TestCase
## Measures: the play-test feedback pass — controls, target markers and the
## closest-approach readout, gun balance, armour, crew and rooms, shipyard
## tools and the rest of the 57 items.

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


func test_closest_approach() -> void:
	# Target 1 km ahead, crossing at 10 m/s, 100 m off our line: we close at 20 m/s.
	var ca := RelativeMotion.closest_approach(Vector3.ZERO, Vector3(0, 0, -20), Vector3(100, 0, -1000), Vector3.ZERO)
	assert_near(ca.time, 50.0, 1e-6, "closest in 50 s")
	assert_near(ca.miss, 100.0, 1e-6, "miss by 100 m")
	var opening := RelativeMotion.closest_approach(Vector3.ZERO, Vector3(0, 0, 5), Vector3(0, 0, -1000), Vector3.ZERO)
	assert_near(opening.time, 0.0, 1e-9, "opening: closest now")
	assert_near(opening.miss, 1000.0, 1e-6, "at the present range")


func test_velocity_hold_cycles_three_modes() -> void:
	var input := PlayerInput.new()
	var ev := InputEventAction.new()
	ev.action = &"toggle_velocity_hold"
	ev.pressed = true
	var seen: Array = []
	for i in 3:
		input.handle_event(ev)
		seen.append(input.velocity_hold)
	assert_true(seen == [PlayerInput.VelocityHold.TARGET, PlayerInput.VelocityHold.TARGET_MARKERS, PlayerInput.VelocityHold.ORBIT],
		"X: match → target markers → orbit (%s)" % [seen])
	input.velocity_hold = PlayerInput.VelocityHold.TARGET_MARKERS
	assert_true(input.target_relative(), "target markers without matching velocity")


func test_rate_of_fire_does_not_compound_on_recompute() -> void:
	var s := _ship(&"s").systems
	s.pips.assign([1, 1, 4])
	var rates := []
	for i in 4:
		s.invalidate()
		rates.append(s.effective_config().mount_cannon(0).rate_of_fire_rpm)
	var base: float = s.base_config.mount_cannon(0).rate_of_fire_rpm
	assert_true(rates.all(func(r: float) -> bool: return is_equal_approx(r, base * 1.5)),
		"WEP 4 is always 1.5 × %.0f rpm (%s)" % [base, rates])


func test_each_gun_meets_its_armour() -> void:
	var auto: KineticCannonConfig = load("res://data/weapons/light_autocannon.tres")
	var heavy: KineticCannonConfig = load("res://data/weapons/medium_kinetic_cannon.tres")
	var rail: KineticCannonConfig = load("res://data/weapons/railgun.tres")
	var skin := 20.0
	var light := skin + ShipBlueprint.PLATE_THIN_MM
	var thick := skin + ShipBlueprint.PLATE_THICK_MM
	assert_true(auto.penetration_mm > skin * 1.4 and auto.penetration_mm < light, "autocannon: through bare hull, stopped by light armour")
	assert_true(heavy.penetration_mm > light * 1.4 and heavy.penetration_mm < thick, "heavy kinetic: through light, stopped by heavy")
	assert_true(rail.penetration_mm > thick * 2.0, "railgun: through heavy armour to 60°")
	var dps := []
	for g in [auto, heavy, rail]:
		dps.append(g.penetration_mm * g.rate_of_fire_rpm)
	assert_true(dps.max() / dps.min() < 1.1, "similar damage rates (mm·rpm %s)" % [dps])
	assert_true(rail.rate_of_fire_rpm < heavy.rate_of_fire_rpm, "the railgun fires slowest")
	assert_near(auto.penetration_at(0.3 * auto.muzzle_velocity_mps), auto.penetration_mm, 1e-6, "no fall-off for a slow or far impact")


func test_magazines_hold_mass_not_rounds() -> void:
	var guns: Array[KineticCannonConfig] = [load("res://data/weapons/light_autocannon.tres"), load("res://data/weapons/medium_kinetic_cannon.tres")]
	# 1200 kg: 600 kg each → 600 autocannon rounds (1 kg) + 150 heavy (4 kg).
	assert_true(ShipStats.rounds_from_mass(1200.0, guns) == 750, "shared by mount, divided by round mass (%d)" % ShipStats.rounds_from_mass(1200.0, guns))
	var bp := _template()
	bp.add_equipment(&"kinetic_cannon", Vector3i(4, 2, 4), &"dorsal")
	var ship := _ship(&"m", Vector3.ZERO, bp)
	var auto_n := ship.rounds_for(ship.config.mount_cannon(0))
	var heavy_n := ship.rounds_for(ship.config.mount_cannon(1))
	assert_near(float(auto_n) / heavy_n, 4.0, 0.1, "four light rounds to each heavy one (%d / %d)" % [auto_n, heavy_n])


func test_profiles_keep_the_parts_their_designs_use() -> void:
	var p := PlayerProfile.new(3)
	var bp := _template()
	bp.add_equipment(&"kinetic_cannon", Vector3i(4, 2, 4), &"dorsal")
	p.ensure_vessel(bp)
	var d := p.to_dict()
	d.schema_version = 3
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(d)), PackedStringArray())
	assert_true(q.owned(&"kinetic_cannon") >= 1, "a v3 save using the once-common heavy cannon owns it")
	var rep := ShipValidator.Report.new()
	q.check_design(q.vessel.blueprint, _catalog(), rep)
	assert_true(not rep.has_code(&"part_not_owned"), "and the design still checks out")
