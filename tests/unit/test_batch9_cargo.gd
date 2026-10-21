extends TestCase
## Measures: play-test batch 9, part 6 — cargo contracts, work without a
## fight. Offered only when another station is charted, to there; accepting
## loads the freight into the hold (refused if it won't fit) and sets the
## course; it pays on arriving there with the freight aboard. Banking leaves
## it aboard; jettisoning it, or losing the ship, fails the contract; it is
## saved with the hold.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(6)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	return p


func _hold_m3(p: PlayerProfile) -> float:
	return ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, _catalog())).cargo_m3


## A cargo offer on `p`'s board, `m3` of freight to the Moon.
func _offer(p: PlayerProfile, m3: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := ContractBoard._cargo_offer(p, rng, ["moon"], 0)
	c.freight_m3 = m3
	p.board = [c]
	return c


func test_offers_go_to_another_charted_station() -> void:
	var cargo := 0
	var total := 0
	var pays := []
	for seed in 30:
		var p := _profile()
		p.board_seed = seed
		for c: Dictionary in ContractBoard.generate(p):
			total += 1
			if c.kind != "cargo":
				continue
			cargo += 1
			pays.append(int(c.credits))
			assert_true(c.location != p.location and int(c.ships) == 0 and int(c.parts) == 0, "elsewhere, no fight, credits only")
			assert_true(int(c.freight_m3) >= ContractBoard.FREIGHT_M3.x and int(c.freight_m3) <= ContractBoard.FREIGHT_M3.y, "a sensible load")
			assert_true(int(c.goal) == MissionChain.Goal.DELIVER, "the delivery goal")
	pays.sort()
	print("    measured: %d of %d offers cargo over 30 boards; pay %d–%d cr" % [cargo, total, pays[0], pays[-1]])
	assert_true(cargo > total / 6 and cargo < total / 2, "about one offer in three")
	# Only one station charted: nowhere to carry anything.
	var alone := _profile()
	alone.known_locations = ["earth"]
	for c: Dictionary in ContractBoard.generate(alone):
		assert_true(c.kind != "cargo", "no cargo with nowhere else to go")


func test_accept_loads_the_freight_and_sets_the_course() -> void:
	var p := _profile()
	p.encounter_size = 2
	var hold := _hold_m3(p)
	var big := _offer(p, ceili(hold) + 1)
	var why := ContractBoard.accept(p, str(big.id))
	print("    measured: hold %.0f m³; a %d m³ load — %s" % [hold, int(big.freight_m3), why])
	assert_true(why.contains("hold") and p.active_contract.is_empty() and not p.vessel.cargo.has("freight"), "too big: refused")
	var c := _offer(p, 20)
	var before := p.vessel.cargo_volume_m3(_catalog())
	assert_true(ContractBoard.accept(p, str(c.id)) == "", "accepted")
	assert_near(p.vessel.cargo_volume_m3(_catalog()) - before, 20.0, 1e-6, "20 m³ more in the hold")
	assert_true(p.launch_point() == "moon" and p.encounter_size == 2, "the course is the Moon; the chosen fight size is kept")
	var lines := p.vessel.cargo_lines(_catalog())
	assert_true(lines[-1].kind == "freight", "a line of its own in the hold, the last to vent")
	assert_true(ShipyardSections._contract_text(c).contains("no fight"), "the board says so")


func test_delivered_on_arrival() -> void:
	var p := _profile()
	var c := _offer(p, 30)
	ContractBoard.accept(p, str(c.id))
	p.vessel.cargo["spare_parts"] = 5
	p.bank_cargo(_catalog())
	assert_true(p.vessel.cargo.has("freight") and not p.vessel.cargo.has("spare_parts"), "banking leaves the freight aboard")
	assert_true(ContractBoard.deliver(p) == "" and not p.active_contract.is_empty(), "not at the Moon yet: nothing")
	# Round-trips through a save.
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	assert_true(int(q.vessel.cargo.freight.m3) == 30 and str(q.active_contract.id) == str(c.id), "saved with the hold")
	var credits := q.credits
	q.location = "moon"
	var line := ContractBoard.deliver(q)
	print("    measured: %s (%d → %d cr)" % [line, credits, q.credits])
	assert_true(q.credits == credits + int(c.credits) and q.active_contract.is_empty() and not q.vessel.cargo.has("freight"), "paid; the hold empty")
	assert_true(ContractBoard.deliver(q) == "", "once")


func test_jettisoned_or_lost_freight_fails_it() -> void:
	var p := _profile()
	var c := _offer(p, 25)
	ContractBoard.accept(p, str(c.id))
	assert_true(p.vessel.vent("freight", "freight").contains("25 m³"), "jettisoned")
	var credits := p.credits
	p.location = "moon"
	var line := ContractBoard.deliver(p)
	assert_true(line.contains("FAILED") and p.active_contract.is_empty() and p.credits == credits, "failed, unpaid: %s" % line)
	# Abandoned: the freight goes back.
	var a := _profile()
	ContractBoard.accept(a, str(_offer(a, 25).id))
	ContractBoard.abandon(a)
	assert_true(not a.vessel.cargo.has("freight"), "abandoned: unloaded")
	# Lost with the ship.
	var l := _profile()
	ContractBoard.accept(l, str(_offer(l, 25).id))
	var lost := l.lose_vessel(_catalog())
	assert_true(" ".join(lost).contains("Contract failed") and l.active_contract.is_empty(), "lost with the ship: %s" % " ".join(lost))
