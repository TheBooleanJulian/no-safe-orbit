extends TestCase
## Measures: play-test batch 11, part 2 — the crew manifest. Two berths a
## quarters cell; crew are yours, not a ship's (they move with you, and
## those without a berth rest ashore, unpaid); the hiring hall never runs
## dry and fills empty berths; every name differs and everyone has a past;
## a cafeteria lifts the crew's skill, a crew armoury the boarders'; saves
## before v14 are moved over.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(11)
	p.ensure_vessel(BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()))
	p.vessel.ensure_crew(_catalog())
	return p


func test_two_berths_a_cell_and_live_with_the_refit() -> void:
	var p := _profile()
	var quarters := 0
	for r in p.vessel.blueprint.rooms:
		if r.def_id == &"crew_quarters":
			quarters += r.rect.size.x * r.rect.size.y
	var berths := p.berths(_catalog())
	print("    measured: frigate %d quarters cells → %d berths; crew %d" % [quarters, berths, p.vessel.crew.size()])
	assert_true(berths == 2 * quarters and p.vessel.crew.size() == berths, "two a cell, and filled")
	var ashore := p.fit_crew(berths - 3)
	assert_true(ashore == 3 and p.resting.size() == 3 and p.vessel.crew.size() == berths - 3, "fewer berths: the rest go ashore")
	assert_true((_catalog().rooms[&"life_support"] as RoomDefinition).display_name == "Medbay", "life support is the Medbay")


func test_the_hall_never_runs_dry_and_names_differ() -> void:
	var p := _profile()
	p.credits = 100_000
	p.refresh_station(_catalog())
	var n := p.vessel.crew.size()
	for k in 5:
		p.dismiss(0)
	for k in 5:
		assert_true(p.hire(0, _catalog()) == "", "hire %d" % (k + 1))
		assert_true(p.hire_pool.size() == PlayerProfile.HIRE_POOL_SIZE, "someone new steps up")
	assert_true(p.vessel.crew.size() == n, "the berths filled again")
	# A destroyer filled: every name differs, everyone has a past.
	var big := PlayerProfile.new(12)
	big.ensure_vessel(BlueprintIO.load_file("res://tests/fixtures/destroyer_mk1.json", PackedStringArray()))
	big.vessel.crew = []
	big.credits = 1_000_000
	var line := big.fill_berths(big.berths(_catalog()))
	var names := {}
	for c: Dictionary in big.vessel.crew:
		names[str(c.name)] = true
		assert_true(str(c.get("occupation", "")) != "", "%s has a past" % c.name)
	print("    measured: destroyer — %s; %d crew, %d different names; e.g. %s, formerly %s" % [line, big.vessel.crew.size(), names.size(),
		big.vessel.crew[0].name, big.vessel.crew[0].occupation])
	assert_true(big.vessel.crew.size() == big.berths(_catalog()) and names.size() == big.vessel.crew.size(), "filled, no name twice")


func test_resting_crew_and_ships() -> void:
	var p := _profile()
	var first := str(p.vessel.crew[0].name)
	assert_true(p.rest_crew(0) == "" and p.resting.size() == 1, "ashore to rest")
	var wages_aboard := p.wages()
	assert_true(p.board_resting(0, p.berths(_catalog()), CrewRoster.Role.SECURITY) == "" and p.resting.is_empty(), "back aboard")
	assert_true(str(p.vessel.crew[-1].name) == first and int(p.vessel.crew[-1].role) == CrewRoster.Role.SECURITY, "posted where dropped")
	assert_true(p.wages() > wages_aboard, "paid again once aboard (resting is unpaid)")
	# Crew are yours: a bigger ship bought, they go with you.
	p.credits = 1_000_000
	var crew_names := p.vessel.crew.map(func(c: Dictionary) -> String: return str(c.name))
	assert_true(p.buy_ship(BlueprintIO.load_file("res://tests/fixtures/destroyer_mk1.json", PackedStringArray()), _catalog()) == "", "bought")
	var aboard := p.vessel.crew.map(func(c: Dictionary) -> String: return str(c.name))
	var kept := crew_names.filter(func(n: String) -> bool: return aboard.has(n)).size()
	print("    measured: the destroyer has %d aboard (%d from the frigate), %d resting; the frigate %d" % [aboard.size(), kept, p.resting.size(),
		p.vessels[0].crew.size()])
	assert_true(kept == crew_names.size() and p.vessels[0].crew.is_empty(), "the frigate's crew came across")
	assert_true(p.vessel.crew.size() == p.berths(_catalog()), "every berth filled from the new hands")
	# Back to the frigate: as many as it has berths; the rest rest.
	assert_true(p.select_vessel(0), "the frigate again")
	assert_true(p.vessel.crew.size() == p.berths(_catalog()) and p.resting.size() > 100, "16 aboard, the rest ashore (%d)" % p.resting.size())


func test_cafeteria_and_armoury() -> void:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var pg := ShipGrid.build(bp, _catalog())
	var ps := ShipStats.compute(bp, pg)
	var plain := ShipSystems.create(bp, pg, ps, ps.to_ship_config("p"))
	var with_rooms := bp.duplicate_blueprint()
	(with_rooms.find("r16") as ShipBlueprint.PlacedRoom).def_id = &"cafeteria"
	var g := ShipGrid.build(with_rooms, _catalog())
	var st := ShipStats.compute(with_rooms, g)
	var caf := ShipSystems.create(with_rooms, g, st, st.to_ship_config("c"))
	var cells: int = caf.working_cells(&"cafeteria")
	print("    measured: a %d-cell cafeteria — crew skill ×%.2f; gun rate %.1f → %.1f rpm" % [cells, caf.crew_skill_factor(),
		plain.effective_config().cannon.rate_of_fire_rpm, caf.effective_config().cannon.rate_of_fire_rpm])
	assert_near(caf.crew_skill_factor(), 1.0 + ShipSystems.CAFETERIA_PER_CELL * cells, 1e-6, "+2 % a cell")
	assert_true(caf.effective_config().cannon.rate_of_fire_rpm > plain.effective_config().cannon.rate_of_fire_rpm, "the gunners are better fed")
	var arm := with_rooms.duplicate_blueprint()
	(arm.find("r16") as ShipBlueprint.PlacedRoom).def_id = &"armoury"
	var ga := ShipGrid.build(arm, _catalog())
	var sta := ShipStats.compute(arm, ga)
	var sa := ShipSystems.create(arm, ga, sta, sta.to_ship_config("a"))
	var security := sa.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.role == CrewRoster.Role.SECURITY)
	print("    measured: crew armoury — boarding strength ×%.2f; security stationed there: %d of %d" % [sa.armoury_factor(),
		security.filter(func(m: CrewRoster.Member) -> bool: return sa.room_role(m.station) == &"armoury").size(), security.size()])
	assert_true(sa.armoury_factor() > 1.0 and plain.armoury_factor() == 1.0, "the armoury lifts the fight")
	assert_true(not security.is_empty() and security.all(func(m: CrewRoster.Member) -> bool: return sa.room_role(m.station) == &"armoury"),
		"security stand watch there")


func test_v13_saves_move_crew_to_the_station() -> void:
	var path := "user://test_b11_crew_profile.json"
	for s in ["", ".bak", ".tmp", ".v13"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var p := _profile()
	p.credits = 1_000_000
	p.buy_ship(BlueprintIO.load_file("res://tests/fixtures/cutter_mk1.json", PackedStringArray()), _catalog())
	var d := p.to_dict()
	d.schema_version = 13
	d.erase("resting")
	# As a v13 save had it: each vessel its own crew of 3 a cell, no occupations.
	d.vessels[0].crew = []
	for k in 24:
		d.vessels[0].crew.append({"name": "Old Hand %d" % k, "role": 6, "skill": 0, "sorties": 2})
	d.active_vessel = 0
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	print("    measured: v13 — frigate %d aboard (16 berths), %d resting, cutter %d; occupation of a veteran: %s" % [q.vessel.crew.size(),
		q.resting.size(), q.vessels[1].crew.size(), q.vessel.crew[0].get("occupation", "?")])
	assert_true(q.loaded_schema == 13 and FileAccess.file_exists(path + ".v13"), "migrated, the original kept")
	assert_true(q.vessel.crew.size() == 16 and q.vessels[1].crew.is_empty() and q.resting.size() >= 8, "16 aboard; the rest and the cutter's crew ashore")
	assert_true(str(q.vessel.crew[0].get("occupation", "")) != "", "everyone given a past")
	for s in ["", ".bak", ".tmp", ".v13"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
