extends TestCase
## Measures: Milestone 13's last contract — retrieve. A pod lost at a
## charted station, usually guarded, to bring back to the station that
## offered the work: accepting sets the course and the fight; nothing is
## loaded; it pays only with the pod aboard at that station; abandoning or
## losing the ship loses it.


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(13)
	p.ensure_vessel(BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()))
	return p


func _offer(p: PlayerProfile, at: String) -> Dictionary:
	var c := ContractBoard._retrieve_offer(p, RandomNumberGenerator.new(), [at], 0)
	p.board = [c]
	return c


func test_offers() -> void:
	var n := 0
	var total := 0
	for seed in 40:
		var p := _profile()
		p.board_seed = seed
		for c: Dictionary in ContractBoard.generate(p):
			total += 1
			if c.kind != "retrieve":
				continue
			n += 1
			assert_true(ContractBoard.deliver_to(c) == p.location and int(c.ships) >= 1 and int(c.freight_m3) == ContractBoard.RETRIEVE_M3,
				"back to this station, guarded, a small pod")
			assert_true(int(c.goal) == MissionChain.Goal.RETRIEVE and ShipyardSections._contract_text(c).contains("back to the"), "its goal, its board text")
	print("    measured: %d of %d offers retrieve over 40 boards" % [n, total])
	assert_true(n > total / 10 and n < total / 3, "a regular part of the board")


func test_accept_and_bring_it_back() -> void:
	var p := _profile()
	var c := _offer(p, "moon")
	var hold := p.vessel.cargo_volume_m3(ConstructionCatalog.default_catalog())
	assert_true(ContractBoard.accept(p, str(c.id)) == "", "accepted")
	assert_true(p.launch_point() == "moon" and p.encounter_size == int(c.ships), "the course is the Moon, with its guards")
	assert_near(p.vessel.cargo_volume_m3(ConstructionCatalog.default_catalog()), hold, 1e-6, "nothing loaded (m³)")
	p.location = "earth"
	assert_true(ContractBoard.deliver(p) == "" and not p.active_contract.is_empty(), "not recovered: nothing to hand over, nothing failed")
	# Recovered at the Moon (Main stows it on G), then home.
	p.vessel.cargo["freight"] = {"contract": str(c.id), "m3": int(c.freight_m3), "what": str(c.freight)}
	p.location = "moon"
	assert_true(ContractBoard.deliver(p) == "", "aboard, but at the Moon: not yet")
	p.location = "earth"
	var credits := p.credits
	var line := ContractBoard.deliver(p)
	print("    measured: %s (%d → %d cr)" % [line, credits, p.credits])
	assert_true(p.credits == credits + int(c.credits) and p.active_contract.is_empty() and not p.vessel.cargo.has("freight"), "paid at the station that wanted it")
	# Abandoned, or lost with the ship: gone.
	var q := _profile()
	var d := _offer(q, "earth")
	ContractBoard.accept(q, str(d.id))
	q.vessel.cargo["freight"] = {"contract": str(d.id), "m3": 6, "what": str(d.freight)}
	var lost := q.lose_vessel(ConstructionCatalog.default_catalog())
	assert_true(" ".join(lost).contains("Contract failed") and q.active_contract.is_empty(), "lost with the ship")
