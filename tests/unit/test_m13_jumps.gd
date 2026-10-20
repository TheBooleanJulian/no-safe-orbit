extends TestCase
## Measures: Milestone 13 (part 1) — the jump drive burns propellant by mass
## and distance, from the main tank and then a jump-only reserve; jumps that
## can't be paid are refused with the reason (a contract too); the yard
## refills the reserve; each station has its own shelves, prices and local
## traffic; v8 saves load with a full reserve.


func _profile(seed_value: int = 5) -> PlayerProfile:
	var p := PlayerProfile.new(seed_value)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	return p


func _cat() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _set_tanks(p: PlayerProfile, main_kg: float, reserve_kg: float) -> void:
	var stats := ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, _cat()))
	p.vessel.condition["stores"] = {"propellant_kg": main_kg, "rounds": stats.rounds_capacity, "jump_reserve_kg": reserve_kg}


func test_cost_grows_with_mass_and_distance() -> void:
	var p := _profile()
	var drive := JumpDrive.standard()
	var tanks := p.vessel_tanks(_cat())
	var local := drive.cost_kg(tanks.mass_kg, 0.0)
	var moon := p.jump_cost_kg("moon", _cat())
	print("    measured: Frigate %.0f t — jump home %.1f t, Earth→Moon %.1f t; tanks %.0f t + reserve %.0f t" % [
		float(tanks.mass_kg) / 1000.0, local / 1000.0, moon / 1000.0, float(tanks.capacity_kg) / 1000.0, float(tanks.reserve_capacity_kg) / 1000.0])
	assert_near(drive.cost_kg(2.0 * tanks.mass_kg, 1e8), 2.0 * drive.cost_kg(tanks.mass_kg, 1e8), 1.0, "twice the mass, twice the cost (kg)")
	assert_true(drive.cost_kg(tanks.mass_kg, 1e9) > drive.cost_kg(tanks.mass_kg, 1e8), "farther costs more")
	assert_true(local < 0.1 * float(tanks.capacity_kg), "a jump home is a small part of the tank")
	assert_true(moon > 3.0 * local and moon < float(tanks.capacity_kg), "Earth to the Moon is a real cost, but one tank covers it")
	assert_near(float(tanks.reserve_capacity_kg), 0.25 * float(tanks.capacity_kg), 1.0, "the reserve is a quarter of the tankage (kg)")


func test_pay_main_first_then_reserve() -> void:
	var a := JumpDrive.pay(10_000.0, 5_000.0, 4_000.0)
	assert_true(a.ok and is_equal_approx(a.main_kg, 6_000.0) and is_equal_approx(a.reserve_kg, 5_000.0), "from the main tank")
	var b := JumpDrive.pay(10_000.0, 5_000.0, 12_000.0)
	assert_true(b.ok and is_equal_approx(b.main_kg, 0.0) and is_equal_approx(b.reserve_kg, 3_000.0), "then the reserve")
	var c := JumpDrive.pay(10_000.0, 5_000.0, 16_000.0)
	assert_true(not c.ok and is_equal_approx(c.main_kg, 10_000.0) and is_equal_approx(c.reserve_kg, 5_000.0), "short: refused, nothing taken")
	var tow := JumpDrive.standard().tow_credits(600_000.0)
	print("    measured: rescue tow for a 600 t ship %d cr" % tow)
	assert_true(tow == 150 + 300, "tow: call-out plus per tonne")


func test_relocation_is_paid_or_refused() -> void:
	var p := _profile()
	_set_tanks(p, 10_000.0, 2_000.0)
	var why := p.relocate("moon", _cat())
	print("    measured: refused — %s" % why)
	assert_true(why.contains("ARMOURY") and p.location == "earth", "too little propellant: refused with the reason, still at Earth")
	# The cost counts the propellant aboard, so it is read with the tanks set.
	_set_tanks(p, 20_000.0, 20_000.0)
	var cost := p.jump_cost_kg("moon", _cat())
	assert_true(p.relocate("moon", _cat()) == "" and p.location == "moon", "enough with the reserve: jumped")
	var t := p.vessel_tanks(_cat())
	print("    measured: 20 t + 20 t reserve, the jump burned %.1f t → %.1f t + %.1f t" % [cost / 1000.0, float(t.main_kg) / 1000.0, float(t.reserve_kg) / 1000.0])
	assert_near(float(t.main_kg), 0.0, 1.0, "the main tank went first (kg)")
	assert_near(float(t.reserve_kg), 40_000.0 - cost, 1.0, "then the reserve (kg)")
	var need := ServiceYard.resupply_needs(p.vessel, _cat())
	assert_near(float(need.reserve_kg), float(t.reserve_capacity_kg) - float(t.reserve_kg), 1.0, "the yard refills the reserve (kg)")
	p.credits = 10_000
	ServiceYard.resupply(p.vessel, p, _cat())
	assert_true(is_equal_approx(float(p.vessel_tanks(_cat()).reserve_kg), float(t.reserve_capacity_kg)), "and does, for credits")
	assert_true(p.relocate("moon", _cat()) == "", "staying put is free")
	assert_true(str(p.vessel.history).contains("Jumped to Lunar Shipyard"), "the vessel's history has the jump")


func test_a_contract_needs_the_jump_paid() -> void:
	var p := _profile()
	p.board = [{"id": "c1", "title": "Bounty", "location": "moon", "ships": 1, "goal": "disable", "threat": 1, "credits": 100, "parts": 0}]
	_set_tanks(p, 0.0, 0.0)
	var why := ContractBoard.accept(p, "c1")
	assert_true(why != "" and p.active_contract.is_empty() and p.board.size() == 1 and p.location == "earth",
		"unaffordable: the offer stays up, nothing accepted, no free trip")
	_set_tanks(p, 80_000.0, 20_000.0)
	assert_true(ContractBoard.accept(p, "c1") == "" and p.location == "moon" and not p.active_contract.is_empty(), "paid: accepted and there")


func test_each_station_has_its_own_shelves() -> void:
	var p := _profile(11)
	p.refresh_station(_cat())
	var earth_fee := 0
	for c in p.hire_pool:
		earth_fee += int(c.fee)
	assert_true(p.vendor_stock.size() == PlayerProfile.VENDOR_STOCK_SIZE, "Earth: three items as before")
	var q := _profile(11)
	q.location = "moon"
	q.refresh_station(_cat())
	var moon := Location.by_id("moon")
	assert_true(q.vendor_stock.size() == moon.vendor_stock_size, "the Moon: %d items" % moon.vendor_stock_size)
	for item in q.vendor_stock:
		var def: EquipmentDefinition = _cat().equipment[StringName(item.id)]
		assert_true(def.rarity <= moon.vendor_max_rarity, "%s within the Moon's range" % item.id)
		assert_true(int(item.price) == roundi(PlayerProfile.VENDOR_PRICES[def.rarity] * moon.price_factor), "%s at lunar prices" % item.id)
	var moon_fee := 0
	for c in q.hire_pool:
		moon_fee += int(c.fee)
	print("    measured: crew fees Earth %d cr, Moon %d cr (same faces)" % [earth_fee, moon_fee])
	assert_true(moon_fee > earth_fee, "hiring costs more on the Moon")


func test_local_traffic() -> void:
	var earth := Location.by_id("earth")
	var moon := Location.by_id("moon")
	for loc in Location.all():
		assert_true(loc.validate().is_empty(), "%s validates: %s" % [loc.id, loc.validate()])
	var seen := {}
	for m in range(1, 13):
		for i in 3:
			assert_true(earth.enemy_template(m, i) == "frigate_mk1.json", "Earth: frigates, as before")
			seen[moon.enemy_template(m, i)] = true
			assert_true(moon.enemy_template(m, i) == moon.enemy_template(m, i), "seeded")
	print("    measured: lunar traffic %s" % ", ".join(seen.keys()))
	assert_true(seen.has("corvette_mk1.json") and seen.has("frigate_mk1.json"), "the Moon mixes corvettes and frigates")
	var corvette := BlueprintIO.load_file("res://data/blueprints/corvette_mk1.json", PackedStringArray())
	var bp := EnemyFactory.design(6, corvette, _cat(), 1)
	assert_true(not ShipValidator.validate(bp, _cat()).has_errors() and bp.name.ends_with("-class corvette"), "an armed corvette (%s)" % bp.name)
	assert_true(moon.threat_bonus > earth.threat_bonus, "and tougher")


func test_schema_9_migration() -> void:
	var path := "user://test_m13_profile.json"
	for s in ["", ".bak", ".tmp", ".v8"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var p := _profile(4)
	var stats := ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, _cat()))
	p.vessel.condition["stores"] = {"propellant_kg": 30_000.0, "rounds": stats.rounds_capacity}
	var d := p.to_dict()
	d.schema_version = 8
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	var t := q.vessel_tanks(_cat())
	assert_true(q.loaded_schema == 8 and FileAccess.file_exists(path + ".v8"), "a v8 save loads; the original is kept")
	assert_true(is_equal_approx(float(t.reserve_kg), float(t.reserve_capacity_kg)) and is_equal_approx(float(t.main_kg), 30_000.0),
		"its vessel starts with a full reserve and keeps its propellant")
	_set_tanks(q, 30_000.0, 4_000.0)
	q.save(path)
	var r := PlayerProfile.load_file(path, PackedStringArray())
	assert_true(r.loaded_schema == PlayerProfile.SCHEMA_VERSION and PlayerProfile.SCHEMA_VERSION >= 9, "saved at the current schema (9 or later)")
	assert_near(float(r.vessel_tanks(_cat()).reserve_kg), 4_000.0, 1.0, "with the reserve (kg)")
	for s in ["", ".bak", ".tmp", ".v8"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
