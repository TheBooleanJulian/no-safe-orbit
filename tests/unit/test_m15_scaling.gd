extends TestCase
## Measures: Milestone 15 — hangar capacity, crew complement and point
## defence that scale with hull size. The standard complement grows with the
## ship (a frigate's is unchanged); damage-control teams (one per two DC
## crew) repair at the same time, and every medic treats a patient of their
## own; PD coverage and the mounts a hull wants follow its surface, and the
## templates' PD and craft rise with their size.

const DT := 0.25


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _bp(name: String) -> ShipBlueprint:
	return BlueprintIO.load_file("res://data/blueprints/%s.json" % name, PackedStringArray())


func _ship(bp: ShipBlueprint) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var s := ShipState.create(&"s", bp.name, cfg, Vector3.ZERO)
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _specialists(want: Array[int]) -> int:
	var n := 0
	for r in CrewRoster.specialist_roles():
		n += want[r]
	return n


func test_the_standard_complement_scales_with_the_hull() -> void:
	var by_ship := {}
	for name in ["cutter_mk1", "corvette_mk1", "frigate_mk1", "destroyer_mk1", "cruiser_mk1", "carrier_mk1"]:
		var bp := _bp(name)
		var grid := ShipGrid.build(bp, _catalog())
		var stats := ShipStats.compute(bp, grid)
		var want := CrewRoster.complement_for(bp, grid, stats)
		by_ship[name] = want
		var roster := CrewRoster.default_for(bp, grid, stats)
		var counts := {}
		for m in roster.members:
			counts[m.role] = int(counts.get(m.role, 0)) + 1
		print("    measured: %s %d berths — standard %s (%d specialists); the roster has %d" % [name, stats.crew_capacity,
			Shipyard._complement_text(want), _specialists(want), roster.members.size()])
		if _specialists(want) <= stats.crew_capacity:
			for r in CrewRoster.specialist_roles():
				assert_true(int(counts.get(r, 0)) == want[r], "%s: the roster fills %s to the standard (%d)" % [name, CrewRoster.ROLE_NAMES[r], want[r]])
	assert_true(by_ship.frigate_mk1 == [2, 2, 2, 1, 4, 1, 0, 1], "the frigate's complement is unchanged, and a pilot for its fighter (%s)" % [by_ship.frigate_mk1])
	for big in ["destroyer_mk1", "cruiser_mk1", "carrier_mk1"]:
		var w: Array[int] = by_ship[big]
		for r in CrewRoster.specialist_roles():
			assert_true(w[r] >= by_ship.frigate_mk1[r], "%s: at least a frigate's %s" % [big, CrewRoster.ROLE_NAMES[r]])
		assert_true(_specialists(w) > 3 * _specialists(by_ship.frigate_mk1), "%s: over three times the specialists (%d)" % [big, _specialists(w)])


func test_damage_control_teams_repair_at_the_same_time() -> void:
	var bp := _bp("destroyer_mk1")
	# A workshop in place of a room the design can spare (nothing fitted in it).
	for r in bp.rooms:
		if r.def_id == &"bridge":
			continue
		var was := r.def_id
		r.def_id = &"workshop"
		if not ShipValidator.validate(bp, _catalog()).has_errors():
			break
		r.def_id = was
	assert_true(not ShipValidator.validate(bp, _catalog()).has_errors() and bp.rooms.any(func(r: ShipBlueprint.PlacedRoom) -> bool: return r.def_id == &"workshop"),
		"a destroyer with a workshop is valid")
	var ship := _ship(bp)
	var sys := ship.systems
	var teams := sys.repair_teams()
	var hurt: Array[ShipSystems.EquipmentState] = []
	for e in sys.equipment:
		if hurt.size() < teams + 1 and e.def.kind in [EquipmentDefinition.Kind.CANNON, EquipmentDefinition.Kind.RADIATOR] and sys.can_reach(e):
			e.hp = 0.5 * e.max_hp
			hurt.append(e)
	var started := 0
	while sys.start_field_repair() != null:
		started += 1
	print("    measured: destroyer — %d damage-control teams, %d repairs started at once; then: %s" % [teams, started, sys.field_repair_block_reason()])
	assert_true(teams == 3 and started == teams and sys.repair_tasks.size() == teams, "three teams, three repairs under way")
	assert_true(sys.field_repair_block_reason().contains("all 3"), "a fourth waits for a team")
	var longest := 0.0
	for t in sys.repair_tasks:
		longest = maxf(longest, t.total_s)
	var time := 0.0
	while not sys.repair_tasks.is_empty() and time < 600.0:
		sys.tick(ship, DT)
		time += DT
	print("    measured: all three patched in %.0f s (the longest alone %.0f s at the SYS channel's rate)" % [time, longest])
	var patched := hurt.filter(func(e: ShipSystems.EquipmentState) -> bool: return e.hp >= ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp - 1e-3)
	assert_true(patched.size() == teams and time < 1.5 * longest / sys.channel_factor(ShipSystems.Channel.SYS) + 1.0, "in parallel, not one after another")
	# A frigate's two DC crew make one team, as before.
	var frigate := _ship(_bp("frigate_mk1"))
	assert_true(frigate.systems.repair_teams() == 1, "a frigate: one team")


func test_every_medic_treats_a_patient_of_their_own() -> void:
	var ship := _ship(_bp("destroyer_mk1"))
	var sys := ship.systems
	var medics := sys.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.role == CrewRoster.Role.MEDICAL)
	var wounded: Array[CrewRoster.Member] = []
	for m in sys.crew.members:
		if m.role == CrewRoster.Role.SECURITY and wounded.size() < 3:
			m.state = CrewRoster.State.WOUNDED
			wounded.append(m)
	var time := 0.0
	while wounded.any(func(m: CrewRoster.Member) -> bool: return m.state == CrewRoster.State.WOUNDED) and time < 600.0:
		sys.tick(ship, DT)
		time += DT
	var one := ShipSystems.MEDICAL_TREATMENT_S / (maxf(sys.room_bonus(&"life_support"), 0.5) * sys.tech_factor("medicine"))
	print("    measured: %d medics treat 3 wounded in %.0f s (one treatment %.0f s)" % [medics.size(), time, one])
	assert_true(medics.size() >= 3 and time <= one + 1.0, "three at once, not one after another")


func test_point_defence_and_hangars_follow_the_hull() -> void:
	var rows := []
	for name in ["corvette_mk1", "frigate_mk1", "destroyer_mk1", "cruiser_mk1", "carrier_mk1"]:
		var bp := _bp(name)
		var grid := ShipGrid.build(bp, _catalog())
		var t0 := Time.get_ticks_usec()
		var pd := PdCoverage.of(grid)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var craft := 0
		for i in bp.equipment.size():
			if grid.equipment_def(i) != null and grid.equipment_def(i).kind == EquipmentDefinition.Kind.CRAFT_MOUNT:
				craft += 1
		rows.append([name, pd, craft])
		print("    measured: %s %.0f m² — PD %d / %d wanted, covers %d %% (%.1f ms) · %d craft" % [name, pd.area_m2, pd.mounts, pd.recommended,
			roundi(float(pd.coverage) * 100.0), ms, craft])
		assert_true(int(pd.mounts) >= int(pd.recommended), "%s carries the PD its hull wants" % name)
		assert_true(ms < 50.0, "%s: worked out in %.1f ms (the stats panel redraws on every edit)" % [name, ms])
	for i in range(1, rows.size()):
		assert_true(int(rows[i][1].recommended) >= int(rows[i - 1][1].recommended), "%s wants at least %s's PD" % [rows[i][0], rows[i - 1][0]])
	assert_true(int(rows[4][2]) > int(rows[2][2]) and int(rows[4][1].recommended) > 2 * int(rows[1][1].recommended),
		"the carrier carries far more craft, and its hull wants far more PD, than a frigate")
	# One PD mount covers no more than its side of the hull; none, nothing.
	var bp := _bp("frigate_mk1")
	var kept := false
	for e in bp.equipment:
		if e.def_id == &"point_defence":
			if kept:
				e.def_id = &"sensor_mast"
			kept = true
	var one := PdCoverage.of(ShipGrid.build(bp, _catalog()))
	for e in bp.equipment:
		if e.def_id == &"point_defence":
			e.def_id = &"sensor_mast"
	var none := PdCoverage.of(ShipGrid.build(bp, _catalog()))
	print("    measured: frigate with one PD mount covers %d %%; with none %d %%" % [roundi(float(one.coverage) * 100.0), roundi(float(none.coverage) * 100.0)])
	assert_true(float(one.coverage) > 0.3 and float(one.coverage) < 0.7 and float(none.coverage) == 0.0, "a mount covers its side; none, nothing")
