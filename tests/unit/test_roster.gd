extends TestCase
## Measures: the prebuilt roster (2026-10-26, tools/make_roster.gd) — nine
## hulls that validate clean, fly on a new profile with what is sold with
## them, keep the roster's conventions (weapons, launchers and plumes clear
## of their own hull; the PD a hull wants; no hatch blocked), look different
## from one another, and differ in what they do: a battleship is not a big
## cruiser, the carrier and the scout work with craft and sensors the game
## has, the freighter carries more than anything and earns from it.

const ROSTER := {
	"cutter_mk1": "interceptor", "corvette_mk1": "missile corvette", "frigate_mk1": "escort frigate",
	"destroyer_mk1": "gun destroyer", "cruiser_mk1": "heavy cruiser", "battleship_mk1": "battleship",
	"carrier_mk1": "fleet carrier", "scout_mk1": "scout", "freighter_mk1": "heavy freighter",
}


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _bp(id: String) -> ShipBlueprint:
	return BlueprintIO.load_file("%s/%s.json" % [BlueprintIO.TEMPLATE_DIR, id], PackedStringArray())


func _stats(bp: ShipBlueprint) -> ShipStats:
	return ShipStats.compute(bp, ShipGrid.build(bp, _catalog()))


func _count(bp: ShipBlueprint, kind: EquipmentDefinition.Kind) -> int:
	var n := 0
	for e in bp.equipment:
		var def: EquipmentDefinition = _catalog().equipment.get(e.def_id)
		if def != null and def.kind == kind:
			n += 1
	return n


func _has(bp: ShipBlueprint, def_id: StringName) -> bool:
	return bp.equipment.any(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == def_id)


func test_nine_hulls_for_sale_each_valid_and_named_for_its_role() -> void:
	var cat := _catalog()
	var listed := BlueprintIO.list_templates()
	assert_true(listed.size() == ROSTER.size(), "nine hulls at the dealer (%d)" % listed.size())
	for id: String in ROSTER:
		var bp := _bp(id)
		assert_true(bp != null and listed.has("%s/%s.json" % [BlueprintIO.TEMPLATE_DIR, id]), "%s is for sale" % id)
		if bp == null:
			continue
		var report := ShipValidator.validate(bp, cat)
		assert_true(report.issues.is_empty(), "%s validates clean:\n%s" % [id, report.summary()])
		assert_true(EnemyFactory.hull_type(bp.name) == ROSTER[id] and bp.designer != "", "%s is a %s (%s, by %s)" % [id, ROSTER[id], bp.name, bp.designer])
		var t0 := Time.get_ticks_usec()
		var grid := ShipGrid.build(bp, cat)
		var stats := ShipStats.compute(bp, grid)
		var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config(id))
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var price := ServiceYard.dealer_price(bp, cat, grid, stats)
		print("    measured: %-26s %4d modules %6.0f t %.2f g Δv %5.0f m/s crew %3d cargo %5.0f m³ %6d cr; compiled in %3.0f ms" % [bp.name,
			bp.modules.size(), stats.mass_kg / 1000.0, stats.thrust_forward_n / stats.mass_kg / ShipDynamics.G0, stats.delta_v_m_s(),
			sys.crew.members.size(), stats.cargo_m3, int(price.total), ms])
		assert_less_equal(ms, 150.0, "%s compiles without a long hitch (ms)" % id)


func test_the_rosters_conventions() -> void:
	var cat := _catalog()
	var K := EquipmentDefinition.Kind
	for id: String in ROSTER:
		var bp := _bp(id)
		var grid := ShipGrid.build(bp, cat)
		for i in bp.equipment.size():
			var def := grid.equipment_def(i)
			var e := bp.equipment[i]
			if def.is_external() and def.kind in [K.CANNON, K.POINT_DEFENCE, K.MISSILE_LAUNCHER, K.MAIN_ENGINE, K.SENSOR]:
				var n: Vector3i = ShipGrid.FACE_NORMALS[e.face]
				var clear := range(1, 4).all(func(k: int) -> bool: return not grid.is_hull(e.cell + n * k))
				assert_true(clear, "%s: %s %s has three clear cells off its %s face" % [id, def.display_name, e.id, e.face])
		for h in bp.hatches:
			assert_true(not grid.equipment_at.has(h.a) and not grid.equipment_at.has(h.b), "%s: hatch %s is not blocked by machinery" % [id, h.id])
		var pd := PdCoverage.of(grid)
		if id != "freighter_mk1":
			assert_true(int(pd.mounts) >= int(pd.recommended), "%s carries the PD its hull wants (%d of %d)" % [id, pd.mounts, pd.recommended])
		var stats := ShipStats.compute(bp, grid)
		assert_true(stats.power_generation_kw >= stats.power_draw_kw and stats.heat_rejection_kw >= stats.heat_generation_kw,
			"%s: power %.0f/%.0f kW, heat %.0f/%.0f kW" % [id, stats.power_generation_kw, stats.power_draw_kw, stats.heat_generation_kw, stats.heat_rejection_kw])


func test_nine_different_silhouettes() -> void:
	# Plan and profile outlines: no two hulls share them.
	var seen := {}
	for id: String in ROSTER:
		var grid := ShipGrid.build(_bp(id), _catalog())
		var plan := {}
		var side := {}
		for c: Vector3i in grid.module_at:
			plan[Vector2i(c.x, c.z)] = true
			side[Vector2i(c.y, c.z)] = true
		var key := "%d|%d|%s" % [plan.size(), side.size(), grid.cell_bounds().size]
		assert_true(not seen.has(key), "%s's outline differs from %s's" % [id, seen.get(key, "")])
		seen[key] = id
	# What makes each one out, physically.
	var interceptor := _bp("cutter_mk1")
	var booms := interceptor.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool:
		return e.face == &"fore" and e.def_id == &"autocannon")
	assert_true(booms.size() == 2, "the interceptor's guns are at the front of its outrigger booms")
	var destroyer := _bp("destroyer_mk1")
	var gun := destroyer.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == &"railgun")
	var dgrid := ShipGrid.build(destroyer, _catalog())
	var dstats := ShipStats.compute(destroyer, dgrid)
	var muzzle := dgrid.equipment_position_m(destroyer.equipment.find(gun[0])) if gun.size() == 1 else Vector3.INF
	var off := Vector2(muzzle.x - dstats.center_of_mass_m.x, muzzle.y - dstats.center_of_mass_m.y).length()
	print("    measured: the destroyer's railgun muzzle is %.2f m off its centre of mass's line" % off)
	assert_true(gun.size() == 1 and gun[0].face == &"fore" and is_equal_approx(muzzle.x, dgrid.hull_bounds_m().get_center().x) and off < 0.5,
		"the destroyer's one railgun is on its bow, on the centreline: recoil through the centre of mass")
	var battleship := _bp("battleship_mk1")
	assert_true(battleship.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == &"railgun" and e.face == &"fore").size() == 2,
		"the battleship's twin spinal railguns")
	var carrier := ShipGrid.build(_bp("carrier_mk1"), _catalog())
	assert_true(not carrier.is_hull(Vector3i(7, 2, 20)) and carrier.is_hull(Vector3i(1, 2, 20)) and carrier.is_hull(Vector3i(14, 2, 20)),
		"the carrier's hangar deck sits low between its two hulls")
	var scout := _stats(_bp("scout_mk1"))
	assert_true(absf(scout.hull_bounds_m.get_center().x - scout.center_of_mass_m.x) > 3.0, "the scout is lopsided: its sensor boom")


func test_the_battleship_is_not_a_big_cruiser() -> void:
	var cat := _catalog()
	var cr := _bp("cruiser_mk1")
	var bs := _bp("battleship_mk1")
	var c := _stats(cr)
	var b := _stats(bs)
	var cp := ServiceYard.dealer_price(cr, cat)
	var bpr := ServiceYard.dealer_price(bs, cat)
	# A jump to Mars from Earth: the propellant (= credits) it burns.
	var dv := JumpDrive.standard().delta_v(Location.distance_m(Location.by_id("earth"), Location.by_id("mars")))
	var c_kg := JumpDrive.propellant_for(c.wet_mass_kg(), dv, c.main_isp_s)
	var b_kg := JumpDrive.propellant_for(b.wet_mass_kg(), dv, b.main_isp_s)
	print("    measured: cruiser %.0f t, %.2f g, Δv %.0f m/s, %d crew, %.0f t of plate, %d cr, Mars jump %.0f t — battleship %.0f t, %.2f g, Δv %.0f m/s, %d crew, %.0f t of plate, %d cr, Mars jump %.0f t" % [
		c.mass_kg / 1000.0, c.thrust_forward_n / c.mass_kg / ShipDynamics.G0, c.delta_v_m_s(), cp.crew_count, c.plate_mass_kg / 1000.0, cp.total, c_kg / 1000.0,
		b.mass_kg / 1000.0, b.thrust_forward_n / b.mass_kg / ShipDynamics.G0, b.delta_v_m_s(), bpr.crew_count, b.plate_mass_kg / 1000.0, bpr.total, b_kg / 1000.0])
	# What the battleship buys: guns and protection.
	assert_true(_count(bs, EquipmentDefinition.Kind.CANNON) > _count(cr, EquipmentDefinition.Kind.CANNON) and _has(bs, &"railgun") and not _has(cr, &"railgun"),
		"the battleship mounts more guns, railguns among them")
	assert_true(b.plate_mass_kg > 3.0 * c.plate_mass_kg, "three times the armour")
	# What it pays: mobility, range, running costs, flexibility.
	assert_true(b.thrust_forward_n / b.mass_kg < 0.75 * c.thrust_forward_n / c.mass_kg, "it accelerates slower")
	assert_true(c.delta_v_m_s() > 2.0 * b.delta_v_m_s(), "the cruiser has more than twice its range")
	assert_true(b_kg > 3.0 * c_kg, "a jump costs it three times the propellant")
	assert_true(int(bpr.crew_count) > 2 * int(cp.crew_count) and int(bpr.total) > 2 * int(cp.total), "twice the crew and the price")
	assert_true(_count(bs, EquipmentDefinition.Kind.CRAFT_MOUNT) == 0 and _count(bs, EquipmentDefinition.Kind.MISSILE_LAUNCHER) == 0,
		"no craft and no missiles")
	assert_true(_count(cr, EquipmentDefinition.Kind.CRAFT_MOUNT) >= 3 and _count(cr, EquipmentDefinition.Kind.MISSILE_LAUNCHER) >= 4
		and _has(cr, &"repair_drone_rack"), "the cruiser: missiles, and drones for the work far from a yard")
	# Both survive damage: a second bridge, workshop, more than one keel corridor.
	for bp: ShipBlueprint in [cr, bs]:
		var bridges := bp.rooms.filter(func(r: ShipBlueprint.PlacedRoom) -> bool: return r.def_id == &"bridge").size()
		var corridor_decks := {}
		for r in bp.rooms:
			if r.def_id == &"corridor":
				corridor_decks[r.deck] = true
		assert_true(bridges >= 2 and corridor_decks.size() >= 2 and bp.rooms.any(func(r: ShipBlueprint.PlacedRoom) -> bool: return r.def_id == &"workshop"),
			"%s: %d bridges, keel corridors on %d decks, a workshop" % [bp.name, bridges, corridor_decks.size()])


func test_the_carrier_and_the_scout_use_what_the_game_has() -> void:
	var cat := _catalog()
	var carrier := _bp("carrier_mk1")
	var grid := ShipGrid.build(carrier, cat)
	var stats := ShipStats.compute(carrier, grid)
	var bays := 0
	for i in carrier.equipment.size():
		var def := grid.equipment_def(i)
		if def.kind == EquipmentDefinition.Kind.CRAFT_MOUNT and not def.is_external():
			bays += 1
			assert_true(not ShipGrid.door_face(carrier, grid, i).is_empty() and def.craft != null, "bay %s has a door and a craft" % carrier.equipment[i].id)
	var sys := ShipSystems.create(carrier, grid, stats, stats.to_ship_config("carrier"))
	print("    measured: carrier — %d hangar bays, %d craft in all, hangar service ×%.2f" % [bays, _count(carrier, EquipmentDefinition.Kind.CRAFT_MOUNT), stats.hangar_factor])
	assert_true(bays >= 10 and stats.hangar_factor > 1.5, "ten bays or more, with deck room to service them")
	assert_true(not _has(carrier, &"kinetic_cannon") and not _has(carrier, &"railgun") and _has(carrier, &"jammer"),
		"no heavy guns: it defends, it doesn't duel")
	assert_true(sys.crew != null and sys.crew.members.any(func(m: CrewRoster.Member) -> bool: return m.role == CrewRoster.Role.PILOT),
		"it compiles with its crew, pilots among them")
	# The scout: masts that one hit can't all take, a jammer, an EW drone, and
	# the Δv for a deep-space survey the frigate can't make.
	var scout := _bp("scout_mk1")
	assert_true(_count(scout, EquipmentDefinition.Kind.SENSOR) >= 3 and _has(scout, &"jammer") and _has(scout, &"ew_drone_rack"), "the scout's sensors and EW")
	var voyager := Artifact.by_id("voyager1")
	var dvs := {}
	for id: String in ["scout_mk1", "frigate_mk1"]:
		var p := PlayerProfile.new(3)
		p.ensure_vessel(_bp(id))
		dvs[id] = [float(p.vessel_tanks(cat).dv_full_mps), p.survey_dv(voyager)]
	print("    measured: Voyager 1 survey Δv %.0f m/s; scout carries %.0f, frigate %.0f" % [dvs.scout_mk1[1], dvs.scout_mk1[0], dvs.frigate_mk1[0]])
	assert_true(dvs.scout_mk1[0] >= dvs.scout_mk1[1] and dvs.frigate_mk1[0] < dvs.frigate_mk1[1], "the scout can survey Voyager 1; the frigate can't")


func test_the_freighter_carries_and_earns() -> void:
	var cat := _catalog()
	var hold := _stats(_bp("freighter_mk1")).cargo_m3
	for id: String in ROSTER:
		if id != "freighter_mk1":
			assert_true(hold > 4.0 * _stats(_bp(id)).cargo_m3, "the freighter's hold (%.0f m³) dwarfs the %s's" % [hold, id])
	var fp := ServiceYard.dealer_price(_bp("freighter_mk1"), cat)
	assert_true(int(fp.units) == 0 and int(fp.total) < int(ServiceYard.dealer_price(_bp("destroyer_mk1"), cat).total),
		"common, cheap kit: %d cr" % fp.total)
	# Bulk loads, on the board's usual cargo contracts.
	var p := PlayerProfile.new(4)
	p.ensure_vessel(_bp("freighter_mk1"))
	p.known_locations = ["earth", "moon", "mars"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bulk := ContractBoard._cargo_offer(p, rng, ["mars"], 0)
	var parcel := ContractBoard._cargo_offer(p, rng, ["mars"], 1)
	print("    measured: %s — %d m³ for %d cr; %s — %d m³ for %d cr" % [bulk.title, bulk.freight_m3, bulk.credits, parcel.title, parcel.freight_m3, parcel.credits])
	assert_true(int(bulk.freight_m3) > ContractBoard.FREIGHT_M3.y and int(bulk.freight_m3) <= hold and int(bulk.credits) > int(parcel.credits),
		"a bulk load, more pay a trip")
	assert_true(int(parcel.freight_m3) <= ContractBoard.FREIGHT_M3.y, "the other offers stay parcels")
	p.board = [bulk]
	assert_true(ContractBoard.accept(p, str(bulk.id)) == "" and int(p.vessel.cargo.freight.m3) == int(bulk.freight_m3), "accepted: the load is in the hold")
	# A frigate isn't offered bulk.
	var f := PlayerProfile.new(4)
	f.ensure_vessel(_bp("frigate_mk1"))
	var small := ContractBoard._cargo_offer(f, rng, ["mars"], 0)
	assert_true(int(small.freight_m3) <= ContractBoard.FREIGHT_M3.y, "a frigate gets parcels")


func test_a_new_captain_flies_the_frigate_with_its_racks() -> void:
	var cat := _catalog()
	var p := PlayerProfile.new(9)
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	p.ensure_vessel(bp)
	var rep := ShipValidator.Report.new()
	p.check_design(p.vessel.blueprint, cat, rep)
	assert_true(not rep.has_errors(), "the starting frigate launches on a new profile:\n%s" % rep.summary())
	assert_true(p.owned(&"missile_rack") == _count(bp, EquipmentDefinition.Kind.MISSILE_LAUNCHER), "its racks are the captain's")
	p.ensure_vessel(bp)
	assert_true(p.owned(&"missile_rack") == _count(bp, EquipmentDefinition.Kind.MISSILE_LAUNCHER), "and only once")
	for r in bp.rooms:
		assert_true((cat.rooms[r.def_id] as RoomDefinition).rarity == Rarity.Tier.COMMON, "the frigate's %s is a common room" % r.def_id)


func test_saves_keep_their_wrecks_of_retired_hulls() -> void:
	var p := PlayerProfile.new(2)
	DerelictField.record(p.derelicts, "earth", "Kestrel-class colossus", "colossus_battleship.json", 5, 0, 0.8, 1)
	DerelictField.record(p.derelicts, "earth", "Harrier-class frigate", "frigate_mk1.json", 5, 0, 0.8, 1)
	var errors := PackedStringArray()
	var back := PlayerProfile.from_dict(p.to_dict(), errors)
	var templates: Array = back.derelicts.map(func(r: Dictionary) -> String: return str(r.template))
	assert_true(errors.is_empty() and templates == ["battleship_mk1.json", "frigate_mk1.json"], "the retired hull's wreck is its replacement (%s)" % [templates])
	for f: String in BlueprintIO.RENAMED_TEMPLATES:
		assert_true(FileAccess.file_exists("%s/%s" % [BlueprintIO.TEMPLATE_DIR, BlueprintIO.current_template(f)]), "%s → a template that exists" % f)
