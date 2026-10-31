extends TestCase
## Measures: Milestone 13 (part 1) — the jump drive costs Δv by distance, the
## same for every ship (play-test batch 7), paid in propellant by the rocket
## equation from the main tank and then a jump-only reserve; jumps that
## can't be paid are refused with the reason; a contract sets the course and
## the launch pays the jump; the yard refills the reserve; each station has
## its own shelves, prices and local traffic; v8 saves load with a full reserve.


func _profile(seed_value: int = 5) -> PlayerProfile:
	var p := PlayerProfile.new(seed_value)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	return p


func _cat() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _set_tanks(p: PlayerProfile, main_kg: float, reserve_kg: float) -> void:
	var stats := ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, _cat()))
	p.vessel.condition["stores"] = {"propellant_kg": main_kg, "rounds": stats.rounds_capacity, "jump_reserve_kg": reserve_kg}


func test_cost_is_delta_v_by_distance_paid_by_the_rocket_equation() -> void:
	var p := _profile()
	var drive := JumpDrive.standard()
	var tanks := p.vessel_tanks(_cat())
	var isp := float(tanks.isp_s)
	var home_dv := drive.delta_v(0.0)
	var moon_dv := p.jump_dv("moon")
	var local := drive.cost_kg(tanks.mass_kg, 0.0, isp)
	var moon := p.jump_cost_kg("moon", _cat())
	print("    measured: Δv home %.0f m/s, Earth→Moon %.0f m/s · Frigate %.0f t at Isp %.0f s burns %.1f t / %.1f t; carries %.0f m/s full" % [
		home_dv, moon_dv, float(tanks.mass_kg) / 1000.0, isp, local / 1000.0, moon / 1000.0, tanks.dv_full_mps])
	assert_true(drive.delta_v(1e9) > drive.delta_v(1e8), "farther costs more Δv")
	assert_true(moon_dv > 3.0 * home_dv, "Earth to the Moon is a real cost")
	# Every ship pays the same Δv; the propellant follows from its mass and Isp.
	var cutter := PlayerProfile.new(1)
	cutter.ensure_vessel(BlueprintIO.load_file("res://tests/fixtures/cutter_mk1.json", PackedStringArray()))
	var ct := cutter.vessel_tanks(_cat())
	print("    measured: the Cutter (%.0f t) pays the same %.0f m/s with %.1f t" % [float(ct.mass_kg) / 1000.0, cutter.jump_dv("moon"), cutter.jump_cost_kg("moon", _cat()) / 1000.0])
	assert_near(cutter.jump_dv("moon"), moon_dv, 1e-6, "the same Δv for every ship (m/s)")
	assert_true(cutter.jump_cost_kg("moon", _cat()) < 0.5 * moon, "a lighter ship burns fewer tonnes for it")
	assert_near(drive.cost_kg(2.0 * tanks.mass_kg, 1e8, isp), 2.0 * drive.cost_kg(tanks.mass_kg, 1e8, isp), 1.0, "twice the mass, twice the propellant (kg)")
	assert_true(drive.cost_kg(tanks.mass_kg, 1e8, 450.0) > drive.cost_kg(tanks.mass_kg, 1e8, 900.0), "a lower Isp burns more for the same Δv")
	assert_near(JumpDrive.delta_v_of(tanks.mass_kg, moon, isp), moon_dv, 1e-3, "the rocket equation both ways (m/s)")
	assert_near(float(tanks.dv_mps), JumpDrive.delta_v_of(tanks.mass_kg, float(tanks.main_kg) + float(tanks.reserve_kg), isp), 1e-6, "what the tanks aboard buy (m/s)")
	assert_true(local < 0.1 * float(tanks.capacity_kg) and moon < float(tanks.capacity_kg), "a jump home is a small part of the tank; one tank covers the Moon")
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
	assert_true(why.contains("SERVICE BAY") and p.location == "earth", "too little propellant: refused with the reason, still at Earth")
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


func test_a_contract_sets_the_course_and_the_launch_pays() -> void:
	var p := _profile()
	p.board = [{"id": "c1", "title": "Bounty", "location": "moon", "ships": 1, "goal": "disable", "threat": 1, "credits": 100, "parts": 0}]
	# Beyond what the ship could ever carry: refused, the offer stays up.
	var drive := JumpDrive.standard()
	var was := drive.base_dv_mps
	drive.base_dv_mps = 1.0e5
	var why := ContractBoard.accept(p, "c1")
	drive.base_dv_mps = was
	assert_true(why.contains("Δv") and p.active_contract.is_empty() and p.board.size() == 1, "out of reach: refused (%s)" % why)
	# Within reach: accepted with empty tanks — nothing moves until launch.
	_set_tanks(p, 0.0, 0.0)
	assert_true(ContractBoard.accept(p, "c1") == "" and not p.active_contract.is_empty() and p.location == "earth" and p.launch_point() == "moon",
		"accepted: the course is the Moon, still docked at Earth")
	assert_true(p.relocate(p.launch_point(), _cat()).contains("SERVICE BAY") and p.location == "earth", "the launch can't pay it with empty tanks")
	_set_tanks(p, 80_000.0, 20_000.0)
	assert_true(p.relocate(p.launch_point(), _cat()) == "" and p.location == "moon" and p.launch_point() == "moon", "topped up: the launch jumps there")


func test_the_nav_chart_course_waits_for_launch() -> void:
	var p := _profile()
	assert_true(p.launch_point() == "earth", "no course: launch where docked")
	p.jump_target = "moon"
	assert_true(p.launch_point() == "moon" and p.location == "earth", "a course laid in moves nothing")
	assert_true("jump_target" not in p.to_dict(), "a course is not saved")
	p.active_contract = {"location": "earth"}
	assert_true(p.launch_point() == "moon", "a course chosen on the chart beats the contract's")
	p.jump_target = ""
	assert_true(p.launch_point() == "earth", "without one, the contract's location")
	p.active_contract = {}
	assert_true(p.relocate("moon", _cat()) == "" and p.jump_target == "" and p.launch_point() == "moon", "after the jump the course is spent")


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
	assert_true(not ShipValidator.validate(bp, _cat()).has_errors() and bp.name.ends_with("-class missile corvette"), "an armed corvette (%s)" % bp.name)
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
