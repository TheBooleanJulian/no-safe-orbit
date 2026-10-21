extends TestCase
## Measures: play-test batch 9, part 3 — the service bay: refuel and rearm
## each on their own (the main tank before the jump reserve; rounds, then
## point defence, then missiles), what the credits allow, the stores record
## gone once full; spare parts in any amount at the lot's rate.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _profile() -> Array:
	var p := PlayerProfile.new(4)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	var st := ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, _catalog()))
	var reserve := JumpDrive.standard().reserve_capacity_kg(st.propellant_capacity_kg)
	p.vessel.condition["stores"] = {"propellant_kg": 20_000.0, "jump_reserve_kg": 0.0, "rounds": 100, "pd_rounds": 50}
	return [p, st, reserve]


func test_refuel_fills_the_tanks_only() -> void:
	var a := _profile()
	var p: PlayerProfile = a[0]
	var st: ShipStats = a[1]
	var reserve: float = a[2]
	# Credits for the main tank and part of the reserve.
	var main_need := st.propellant_capacity_kg - 20_000.0
	p.credits = ceili(main_need / 1000.0 * ServiceYard.PROPELLANT_CREDITS_PER_T) + 5
	var line := ServiceYard.refuel(p.vessel, p, _catalog())
	var stores: Dictionary = p.vessel.condition.stores
	print("    measured: %s — main %.1f t, reserve %.1f of %.1f t, rounds %d, credits left %d" % [line, float(stores.propellant_kg) / 1000.0,
		float(stores.jump_reserve_kg) / 1000.0, reserve / 1000.0, int(stores.rounds), p.credits])
	assert_near(float(stores.propellant_kg), st.propellant_capacity_kg, 1.0, "the main tank first (kg)")
	assert_near(float(stores.jump_reserve_kg), 5000.0, 1.0, "then what's left on the reserve (kg)")
	assert_true(int(stores.rounds) == 100 and int(stores.pd_rounds) == 50 and p.credits == 0, "the magazine untouched; the credits spent")
	assert_true(line.contains("credits short"), "it says so")
	p.credits = 10_000
	ServiceYard.refuel(p.vessel, p, _catalog())
	assert_true(float(ServiceYard.resupply_needs(p.vessel, _catalog()).reserve_kg) <= 0.0, "with credits, the reserve too")


func test_rearm_fills_the_magazine_only() -> void:
	var a := _profile()
	var p: PlayerProfile = a[0]
	var st: ShipStats = a[1]
	p.vessel.condition["stores"].propellant_kg = st.propellant_capacity_kg
	p.vessel.condition["stores"].jump_reserve_kg = a[2]
	p.credits = 10_000
	var credits := p.credits
	var need: Dictionary = ServiceYard.resupply_needs(p.vessel, _catalog())
	var line := ServiceYard.rearm(p.vessel, p, _catalog())
	print("    measured: %s (needed %d rounds, %d PD rounds)" % [line, need.rounds, need.pd_rounds])
	assert_true(not p.vessel.condition.has("stores"), "full again: no stores record")
	assert_true(credits - p.credits == ceili(float(int(need.rounds) + int(need.pd_rounds)) / ServiceYard.ROUNDS_PER_CREDIT - 1e-9), "rounds at the yard's rate")
	assert_true(ServiceYard.rearm(p.vessel, p, _catalog()) == "" and ServiceYard.refuel(p.vessel, p, _catalog()) == "", "nothing to do: nothing bought")


func test_spare_parts_in_any_amount() -> void:
	var p := PlayerProfile.new(1)
	p.credits = 1000
	var parts := p.spare_parts
	assert_true(PlayerProfile.parts_price(PlayerProfile.PARTS_LOT) == PlayerProfile.PARTS_LOT_PRICE and PlayerProfile.parts_price(120) == 300
		and PlayerProfile.parts_price(15) == 38, "the lot's rate, rounded up")
	assert_true(p.buy_spare_parts(120) and p.spare_parts == parts + 120 and p.credits == 700, "120 for 300 cr")
	assert_true(not p.buy_spare_parts(1000) and p.spare_parts == parts + 120, "not beyond the credits")
	assert_true(not p.buy_spare_parts(0), "not none")
