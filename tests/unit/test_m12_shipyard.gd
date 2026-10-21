extends TestCase
## Measures: Milestone 12 — the ship dealer (every template for credits:
## parts at station rates plus the hull fee, a margin, the standard crew
## hired at the usual fee), buying and scrapping ships, and that no ship can
## be bought and scrapped (or scrapped and re-commissioned) at a profit.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _templates() -> Array[ShipBlueprint]:
	var out: Array[ShipBlueprint] = []
	for path in BlueprintIO.list_templates():
		out.append(BlueprintIO.load_file(path, PackedStringArray()))
	return out


func test_every_template_is_for_sale() -> void:
	var names := PackedStringArray()
	for bp in _templates():
		var price := ServiceYard.dealer_price(bp, _catalog())
		var parts := ServiceYard.parts_value(bp, _catalog())
		var expect_ship := ceili((parts * ServiceYard.part_credits() + PlayerProfile.NEW_HULL_FEE) * ServiceYard.DEALER_MARKUP)
		# Rarer parts come with the ship, at the quartermaster's prices plus the margin.
		var units := 0
		for id: StringName in ServiceYard.rare_units(bp, _catalog()):
			units += int(ServiceYard.rare_units(bp, _catalog())[id]) * PlayerProfile.VENDOR_PRICES[(_catalog().equipment[id] as EquipmentDefinition).rarity]
		assert_true(int(price.ship) == expect_ship and int(price.units) == ceili(units * ServiceYard.DEALER_MARKUP)
			and int(price.crew) == int(price.crew_count) * PlayerProfile.HIRE_FEE
			and int(price.total) == int(price.ship) + int(price.units) + int(price.crew),
			"%s: parts + fee + margin, rarer parts at the quartermaster's price + margin, crew at the hiring fee (%s)" % [bp.name, price])
		names.append("%s %d cr" % [bp.name, price.total])
	print("    measured: dealer prices — %s" % ", ".join(names))
	assert_true(names.size() >= 3, "Cutter, Corvette and Frigate Mk I are all offered (%d)" % names.size())


func test_buying_a_ship() -> void:
	var p := PlayerProfile.new(1)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	var cutter := BlueprintIO.load_file("res://data/blueprints/cutter_mk1.json", PackedStringArray())
	var price := ServiceYard.dealer_price(cutter, _catalog())
	p.credits = int(price.total) - 1
	assert_true(p.buy_ship(cutter, _catalog()) != "" and p.vessels.size() == 1 and p.credits == int(price.total) - 1,
		"one credit short: refused, nothing taken")
	p.credits = int(price.total) + 10
	assert_true(p.buy_ship(cutter, _catalog()) == "", "bought")
	assert_true(p.vessels.size() == 2 and p.active_vessel == 1 and p.credits == 10, "it joins the hangar as the active vessel, paid in full")
	assert_true(p.vessel.crew.size() == int(price.crew_count) and p.vessel.crew.size() > 0, "with its standard crew (%d)" % p.vessel.crew.size())


func test_no_buy_then_scrap_arbitrage() -> void:
	for bp in _templates():
		var p := PlayerProfile.new(2)
		p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
		var price := ServiceYard.dealer_price(bp, _catalog())
		p.credits = int(price.total)
		var parts_before := p.spare_parts
		assert_true(p.buy_ship(bp, _catalog()) == "", "%s bought" % bp.name)
		var got := p.scrap_vessel(p.active_vessel, _catalog())
		var parts_worth := float(got) * ServiceYard.part_credits()
		assert_true(got >= 0 and p.spare_parts == parts_before + got and p.vessels.size() == 1, "%s scrapped for %d parts" % [bp.name, got])
		assert_true(parts_worth < float(price.total) * 0.5,
			"%s: scrapping returns parts worth %.0f cr at station rates — under half its %d cr price" % [bp.name, parts_worth, price.total])
		# Nor scrap-and-recommission: the parts back don't build it again.
		assert_true(got < ServiceYard.parts_value(bp, _catalog()), "%s: scrap parts (%d) < a new hull's parts (%d)" % [bp.name, got, ServiceYard.parts_value(bp, _catalog())])


func test_scrapping() -> void:
	var p := PlayerProfile.new(3)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	assert_true(p.scrap_vessel(0, _catalog()) == -1 and p.vessels.size() == 1, "not your last ship")
	var v := p.vessel
	v.condition = {"equipment": {}}
	var fresh := ServiceYard.scrap_value(v, _catalog())
	assert_true(fresh == floori(ServiceYard.parts_value(v.blueprint, _catalog()) * ServiceYard.SCRAP_RETURN), "an intact ship: half its parts (%d)" % fresh)


func test_capital_ships_are_battleships_and_spawn_fast() -> void:
	var cat := _catalog()
	for id in ["destroyer_mk1", "cruiser_mk1", "carrier_mk1"]:
		var bp := BlueprintIO.load_file("res://data/blueprints/%s.json" % id, PackedStringArray())
		assert_true(bp != null, "%s exists" % id)
		if bp == null:
			continue
		var report := ShipValidator.validate(bp, cat)
		assert_true(report.issues.is_empty(), "%s validates clean (%d issues)" % [id, report.issues.size()])
		# Play-test batch 6: better armed and armoured — a main battery of
		# heavy guns, armour on the flanks, a superstructure above the hull.
		var heavy := 0
		for e in bp.equipment:
			if e.def_id in [&"kinetic_cannon", &"railgun"]:
				heavy += 1
		var top_tower := 0
		for m in bp.modules:
			top_tower = maxi(top_tower, m.position.y)
		var flank_plates := 0
		for key: String in bp.armor:
			if key.ends_with("port") or key.ends_with("starboard"):
				flank_plates += 1
		assert_true(heavy >= 2 and flank_plates > 100, "%s: a main battery (%d heavy guns) and armoured flanks (%d plates)" % [id, heavy, flank_plates])
		assert_true(top_tower >= 3, "%s: a superstructure rises above the hull (deck %d)" % [id, top_tower])
		# Its rarer parts come with it.
		var p := PlayerProfile.new(3)
		p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
		p.credits = 10_000_000
		var units := ServiceYard.rare_units(bp, cat)
		assert_true(p.buy_ship(bp, cat) == "", "%s bought" % id)
		for uid: StringName in units:
			assert_true(p.owned(uid) == int(units[uid]), "%s comes with its %d × %s" % [id, units[uid], uid])
		var t0 := Time.get_ticks_usec()
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config(id))
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("    measured: %s %.0f t, %d modules, crew %d, compiled in %.1f ms" % [id, stats.mass_kg / 1000.0, bp.modules.size(), sys.crew.members.size(), ms])
		assert_true(stats.mass_kg >= 900_000.0, "%s is capital-sized (%.0f t)" % [id, stats.mass_kg / 1000.0])
		assert_less_equal(ms, 60.0, "%s compiles (grid, stats, systems) without a hitch (ms)" % id)


func test_the_mission_board() -> void:
	var p := PlayerProfile.new(9)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	ContractBoard.refresh(p)
	assert_true(p.board.size() == ContractBoard.OFFERS, "%d offers on the board" % p.board.size())
	var again := ContractBoard.generate(p)
	assert_true(str(again) == str(p.board), "seeded: the same profile and sortie, the same offers")
	for c: Dictionary in p.board:
		assert_true(int(c.credits) > 0 and int(c.ships) >= 1 and int(c.ships) <= PlayerProfile.MAX_ENCOUNTER and p.known_locations.has(c.location),
			"%s pays, has 1–3 ships at a known location" % c.title)
	var pick: Dictionary = p.board[0]
	assert_true(ContractBoard.accept(p, str(pick.id)) == "", "accepted")
	assert_true(p.active_contract.id == pick.id and p.location == pick.location and p.encounter_size == int(pick.ships)
		and p.board.size() == ContractBoard.OFFERS - 1, "it sets where and how many, and leaves the board")
	assert_true(ContractBoard.accept(p, str(p.board[0].id)) != "", "one contract at a time")
	var m := MissionChain.from_dict(p.campaign)
	m.contract = p.active_contract.duplicate()
	assert_true(m.goal() == int(pick.goal) and m.number_text().begins_with("CONTRACT"), "the sortie runs the contract (%s)" % m.number_text())
	var credits := p.credits
	m.complete(p)
	assert_true(p.credits == credits + int(pick.credits) and p.active_contract.is_empty() and m.step == 0,
		"completing pays %d cr, clears it and leaves the tutorial chain where it was" % pick.credits)
	ContractBoard.accept(p, str(p.board[0].id))
	ContractBoard.abandon(p)
	assert_true(p.active_contract.is_empty(), "abandoned")


func test_schema_8_migration() -> void:
	var path := "user://test_m12_profile.json"
	for s in ["", ".bak", ".tmp", ".v7"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var p := PlayerProfile.new(4)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	var d := p.to_dict()
	d.schema_version = 7
	for k in ["board", "board_sortie", "board_seed", "active_contract"]:
		d.erase(k)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	assert_true(q.loaded_schema == 7 and q.board.is_empty() and q.active_contract.is_empty(), "a v7 save: no board yet, no contract")
	assert_true(FileAccess.file_exists(path + ".v7"), "the v7 original is kept")
	ContractBoard.refresh(q)
	ContractBoard.accept(q, str(q.board[0].id))
	q.save(path)
	var r := PlayerProfile.load_file(path, PackedStringArray())
	assert_true(r.loaded_schema == PlayerProfile.SCHEMA_VERSION and r.active_contract.id == q.active_contract.id and r.board.size() == q.board.size(),
		"board and contract saved at the current schema")
	for s in ["", ".bak", ".tmp", ".v7"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
