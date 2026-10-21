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


func test_the_grapple_steadies_a_tumbling_hulk_and_siphons_it() -> void:
	var world := WorldSimulation.new(DT)
	var me := _ship(&"me")
	var hulk := _ship(&"hulk")
	# Alongside, port to port, 30 m apart, tumbling, drifting at 1 m/s.
	hulk.orientation = Quaternion(Vector3.UP, PI)
	var pa: Docking.Port = Docking.collars(me.systems)[0]
	var pb: Docking.Port = Docking.collars(hulk.systems, false)[0]
	hulk.position = pa.world_position(me) + pa.world_normal(me) * 30.0 - hulk.orientation * pb.position_body
	hulk.velocity = Vector3(0, 0, 1)
	hulk.angular_velocity = Vector3(0.3, 0.4, 0.1)
	hulk.systems.damage_equipment(hulk.systems.equipment_by_id("e41"), 1000.0)
	hulk.config = hulk.systems.effective_config()
	assert_true(hulk.systems.is_disabled(), "the hulk is disabled (%s)" % hulk.systems.disabled_reason())
	world.add_ship(me)
	world.add_ship(hulk)
	me.propellant_kg -= 5000.0
	var before := me.propellant_kg
	assert_true(world.grab(&"me", &"hulk") == "", "in reach: the arm grabs it")
	var docked_ok := false
	for i in roundi(90.0 / DT):
		world.step()
		var found := Docking.best(me, hulk)
		if not found.is_empty() and found.assessment.ok:
			docked_ok = true
			break
	var spin := (hulk.orientation * hulk.angular_velocity - me.orientation * me.angular_velocity).length()
	assert_true(spin < 0.02, "the tumble is gone (%.3f rad/s)" % spin)
	assert_true(docked_ok, "it is lined up for a gangway: %s" % str(Docking.best(me, hulk).assessment.problems))
	assert_true(me.propellant_kg > before, "propellant siphoned from the hulk (%.0f kg)" % (me.propellant_kg - before))
	assert_true(world.grapple_for(&"me") != null, "still holding")
	world.grapple_for(&"me").release()
	assert_true(world.grapple_for(&"me") == null, "released")


func _room_index(s: ShipSystems, role: StringName) -> int:
	for i in s.blueprint.rooms.size():
		if s.room_role(i) == role:
			return i
	return -1


func test_suited_crew_cross_vented_rooms_and_survive_venting() -> void:
	var s := _ship(&"s").systems
	var bridge := s.command_room()
	var magazine := _room_index(s, &"magazine")
	var corridor := _room_index(s, &"access")
	s.breach_room(corridor)
	assert_true(s.route(bridge, magazine).is_empty() or not s.route(bridge, magazine).has(corridor), "out of suits: no way through the vented corridor")
	s.suited = true
	assert_true(not s.route(bridge, magazine).is_empty(), "in suits: through it")
	var lsr := _room_index(s, &"life_support")
	var dead := func() -> int: return s.crew.members.filter(func(m: CrewRoster.Member) -> bool: return m.state != CrewRoster.State.FIT).size()
	var hurt_before: int = dead.call()
	var inside := s.crew.in_room(lsr, false).size()
	s.breach_room(lsr)
	assert_true(dead.call() == hurt_before, "suited crew come through a room venting unhurt (%d were in it)" % inside)


func test_damage_control_seals_breaches() -> void:
	var bp := _template()
	(bp.find("r9") as ShipBlueprint.PlacedRoom).def_id = &"workshop"
	var s := _ship(&"s", Vector3.ZERO, bp).systems
	assert_true(s.room_bonus(&"workshop") > 0.0, "a working workshop")
	var corridor := _room_index(s, &"access")
	s.breach_room(corridor)
	assert_true(not s.rooms[corridor].pressurized, "breached: vented")
	var t := 0.0
	while t < ShipSystems.HULL_SEAL_S + 2.0 and s.rooms[corridor].breached:
		s._advance_hull_sealing(0.5)
		t += 0.5
	assert_true(not s.rooms[corridor].breached and s.rooms[corridor].pressurized, "sealed and re-pressurised in %.0f s" % t)


func test_bigger_rooms_work_faster() -> void:
	var s := _ship(&"s").systems
	var cells := 0
	for i in s.blueprint.rooms.size():
		if s.room_role(i) == &"command":
			cells += s.blueprint.rooms[i].rect.size.x * s.blueprint.rooms[i].rect.size.y
	assert_near(s.room_bonus(&"command"), minf(1.0 + ShipSystems.ROOM_BONUS_PER_CELL * (cells - 1), ShipSystems.ROOM_BONUS_MAX), 1e-6,
		"a %d-cell bridge" % cells)
	assert_near(s.room_bonus(&"workshop"), 0.0, 1e-9, "no workshop: no bonus")


func test_engines_on_any_face_with_an_engine_room_inside() -> void:
	var cat := _catalog()
	var bp := _template()
	var room := -1
	for i in bp.rooms.size():
		if bp.rooms[i].def_id == &"engine_room":
			room = i
	var grid := ShipGrid.build(bp, cat)
	var placed := false
	for cell in ShipGrid.room_cells(bp.rooms[room]):
		for face in [&"ventral", &"dorsal", &"port", &"starboard"]:
			if placed or not grid.is_exterior_face(cell, face) or grid.slope_faces(cell).has(face):
				continue
			var t := ShipBlueprint.from_dict(bp.to_dict(), PackedStringArray())
			t.add_equipment(&"main_engine", cell, face)
			t.bus[ShipBlueprint.cell_key(cell)] = true
			var r := ShipValidator.validate(t, cat)
			if r.has_code(&"engine_needs_engine_room") or r.has_code(&"equipment_overlap"):
				continue
			placed = true
			var before := ShipStats.compute(bp, grid).to_ship_config("a")
			var after := ShipStats.compute(t, ShipGrid.build(t, cat)).to_ship_config("b")
			var push: Vector3i = -ShipGrid.FACE_NORMALS[face]
			var axis := 0 if push.x != 0 else (1 if push.y != 0 else 2)
			var positive: bool = push[axis] > 0
			# Bigger engine rooms add thrust (play-test batch 9).
			var thrust: float = cat.equipment[&"main_engine"].thrust_n * ShipStats.compute(t, ShipGrid.build(t, cat)).engine_room_factor
			assert_near(after.max_thrust(axis, positive) - before.max_thrust(axis, positive), thrust, 1.0,
				"an engine on the %s face pushes the other way" % face)
			assert_near(after.max_thrust(axis, not positive), before.max_thrust(axis, not positive), 1.0, "and only that way")
	assert_true(placed, "a free face on the engine room")


func test_same_type_rooms_side_by_side_need_no_hatch() -> void:
	var bp := ShipBlueprint.new()
	bp.add_module(&"hull_block", Vector3i.ZERO)
	bp.add_module(&"hull_block", Vector3i(0, 0, 2))
	var a := bp.add_room(&"corridor", 0, Rect2i(0, 0, 1, 2))
	var b := bp.add_room(&"corridor", 0, Rect2i(0, 2, 1, 2))
	var c := bp.add_room(&"cargo_hold", 0, Rect2i(1, 0, 1, 2))
	var grid := ShipGrid.build(bp, _catalog())
	var ia := bp.rooms.find(a)
	var ib := bp.rooms.find(b)
	var ic := bp.rooms.find(c)
	assert_true((grid.open_rooms.get(ia, []) as Array).has(ib), "two corridors touching are one space")
	assert_true(not (grid.open_rooms.get(ia, []) as Array).has(ic), "a corridor and a hold still need a hatch")


func test_engines_trade_thrust_for_isp() -> void:
	var cat := _catalog()
	var budget := func(id: StringName) -> float: return cat.equipment[id].thrust_n * cat.equipment[id].isp_s
	var base: float = budget.call(&"main_engine")
	for id in [&"main_engine_high_isp", &"main_engine_high_thrust"]:
		var k: float = budget.call(id) / base
		assert_true(k > 1.0 and k < 1.4, "%s: an uncommon upgrade, a little more than the standard engine (%.2f×)" % [id, k])
	assert_true(cat.equipment[&"main_engine_high_thrust"].thrust_n > cat.equipment[&"main_engine"].thrust_n
		and cat.equipment[&"main_engine_high_thrust"].isp_s < cat.equipment[&"main_engine"].isp_s, "more thrust costs Isp")
	var torch: float = budget.call(&"torch_drive") / base
	assert_true(torch > 2.0 and torch < 4.0, "the legendary torch drive is better, not absurd (%.1f×)" % torch)
	var rcs: float = budget.call(&"rcs_block_heavy") / budget.call(&"rcs_block")
	assert_true(rcs > 1.0 and rcs < 1.4, "heavy RCS: double the thrust at a lower Isp (%.2f×)" % rcs)


func test_coolant_loops_feed_radiators() -> void:
	var bp := _template()
	var grid := ShipGrid.build(bp, _catalog())
	var before := ShipStats.compute(bp, grid).heat_rejection_kw
	var ed := ShipEditor.new(bp, _catalog())
	assert_true(ed.auto_route_coolant() > 0, "the loop is piped")
	var piped := ShipStats.compute(ed.blueprint, ShipGrid.build(ed.blueprint, _catalog()))
	assert_near(piped.heat_rejection_kw, before, 1e-3, "every radiator on the loop: the same cooling")
	assert_true(not ShipValidator.validate(ed.blueprint, _catalog()).has_code(&"radiator_uncooled"), "no cold radiators")
	var back := ShipBlueprint.from_dict(ed.blueprint.to_dict(), PackedStringArray())
	assert_true(back.coolant.size() == ed.blueprint.coolant.size(), "pipes survive save and load")
	# Cut the pipe next to a radiator: it goes cold.
	var ship := _ship(&"s", Vector3.ZERO, ed.blueprint)
	var s := ship.systems
	var rad: ShipSystems.EquipmentState
	for e in s.equipment:
		if e.def.kind == EquipmentDefinition.Kind.RADIATOR:
			rad = e
	assert_true(s.radiator_cooled(rad), "on the loop")
	for c in s.grid.external_cells(rad.index):
		s.cut_coolant(c)
	assert_true(not s.radiator_cooled(rad), "its pipe cut: cold")
	assert_true(s.condition().has("coolant_cut"), "the cut is saved with the vessel")


func test_foam_puts_out_fires_until_it_runs_out() -> void:
	var ship := _ship(&"s")
	var s := ship.systems
	var room := _room_index(s, &"engineering")
	s.fires[room] = {"burn_s": 0.0, "smoulder_s": 0.0}
	for i in 10:
		s._advance_fires(0.5)
	assert_true(not s.fires.has(room) and s.foam_left(room) == ShipSystems.FOAM_CHARGES - 1, "foamed in seconds, a charge used")
	s.foam_used[room] = ShipSystems.FOAM_CHARGES
	s.fires[room] = {"burn_s": 0.0, "smoulder_s": 0.0}
	s._advance_fires(ShipSystems.FOAM_DELAY_S + 1.0)
	assert_true(s.fires.has(room), "no foam left: it keeps burning")
	assert_true(s.condition().has("foam_used"), "the used charges are saved for the yard to recharge")
	s.breach_room(room)
	for i in roundi(ShipSystems.SMOULDER_S / 5.0) + 1:
		s._advance_fires(5.0)
	assert_true(not s.fires.has(room), "vented: it smoulders out")


func test_templates_of_every_size_use_only_standard_parts() -> void:
	var cat := _catalog()
	var masses := []
	for path in BlueprintIO.list_templates():
		var bp := BlueprintIO.load_file(path, PackedStringArray())
		var r := ShipValidator.validate(bp, cat)
		assert_true(not r.has_errors(), "%s is valid:\n%s" % [bp.name, r.summary()])
		# Common parts only, apart from the rarer parts the dealer sells with
		# a capital ship (play-test batch 6).
		var fresh := PlayerProfile.new(1)
		var units := ServiceYard.rare_units(bp, cat)
		for id: StringName in units:
			fresh.inventory[String(id)] = int(units[id])
		var rep := ShipValidator.Report.new()
		fresh.check_design(bp, cat, rep)
		assert_true(not rep.has_errors(), "%s flies on a new profile (common parts, plus the rarer parts sold with it):\n%s" % [bp.name, rep.summary()])
		masses.append(ShipStats.compute(bp, ShipGrid.build(bp, cat)).wet_mass_kg())
	masses.sort()
	assert_true(masses.size() >= 3 and masses[-1] > masses[0] * 2.0, "light to heavy (%s t)" % [masses.map(func(m: float) -> int: return roundi(m / 1000.0))])


func test_named_crew_are_hired_and_the_dead_leave_their_berths() -> void:
	var cat := _catalog()
	var p := PlayerProfile.new(5)
	p.ensure_vessel(_template())
	p.vessel.ensure_crew(cat)
	var berths := p.berths(cat)
	assert_true(p.vessel.crew.size() == berths and str(p.vessel.crew[0].name) != "", "the standard complement, named (%d)" % berths)
	p.refresh_station(cat)
	assert_true(p.hire(0, cat).contains("no free berth"), "full ship: no hiring")
	p.dismiss(berths - 1)
	p.credits = 1000
	var name: String = p.hire_pool[0].name
	assert_true(p.hire(0, cat) == "" and p.vessel.crew[-1].name == name, "hired %s into the free berth" % name)
	var roster := CrewRoster.from_plan(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, cat),
		ShipStats.compute(p.vessel.blueprint, ShipGrid.build(p.vessel.blueprint, cat)), p.vessel.crew)
	assert_true(roster.members.size() == berths and roster.members[-1].name == name, "flies with them aboard")
	# Killed in action: they leave the roster at the station.
	var first: String = p.vessel.crew[0].name
	var role: int = p.vessel.crew[0].role
	var lost := p.dock({"crew": {"dead": {CrewRoster.ROLE_NAMES[role]: 1}}}, cat)
	assert_true(p.vessel.crew.size() == berths - 1 and not p.vessel.condition.has("crew"), "a berth is free again")
	assert_true(", ".join(lost).contains(first), "the debrief names them (%s)" % ", ".join(lost))
	assert_true(ServiceYard.repair_jobs(p.vessel, cat).filter(func(j: ServiceYard.Job) -> bool: return j.kind == &"recruit").is_empty(),
		"no anonymous recruits: hire from the station")


func test_crew_can_be_reassigned_mid_fight() -> void:
	var s := _ship(&"s").systems
	var gunner: CrewRoster.Member
	for m in s.crew.members:
		if m.role == CrewRoster.Role.SECURITY:
			gunner = m
	assert_true(s.reassign(gunner.id, CrewRoster.Role.WEAPONS) == "", "sent to the guns")
	for i in 60:
		s._advance_crew_orders(1.0)
	assert_true(gunner.role == CrewRoster.Role.WEAPONS and s.room_role(gunner.location) == &"magazine", "now a gunner, at the magazine")


func test_the_quartermaster_and_the_upgrades() -> void:
	var cat := _catalog()
	var p := PlayerProfile.new(8)
	p.ensure_vessel(_template())
	p.refresh_station(cat)
	assert_true(p.vendor_stock.size() == PlayerProfile.VENDOR_STOCK_SIZE, "stock on the shelves")
	var item: Dictionary = p.vendor_stock[0]
	p.credits = int(item.price)
	assert_true(p.buy_stock(0, cat) == "" and p.owned(StringName(item.id)) == 1 and p.credits == 0, "bought one %s" % item.id)
	p.credits = 300
	assert_true(p.buy_tech("thrusters") == "" and p.tech_level("thrusters") == 1, "an upgrade level")
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	assert_true(q.tech_level("thrusters") == 1 and q.hire_pool.size() == p.hire_pool.size(), "kept in the save")
	var ship := _ship(&"s")
	var base := ship.systems.effective_config().thrust_forward_n
	ship.systems.tech = q.tech
	ship.systems.invalidate()
	assert_near(ship.systems.effective_config().thrust_forward_n / base, 1.05, 1e-6, "+5 % thrust")


## A top-deck cell with its top face open and nothing above it, for a plate
## that a new block can then cover.
func _open_top_cell(ed: ShipEditor) -> Vector3i:
	var top := -(1 << 20)
	for c: Vector3i in ed.grid.module_at:
		top = maxi(top, c.y)
	for c: Vector3i in ed.grid.module_at:
		if c.y == top and ed.grid.plateable_faces(c).has(&"dorsal") and not ed.grid.is_wedge_cell(c):
			return c
	return Vector3i(1 << 20, 0, 0)


func test_a_plate_covered_by_a_new_block_goes_with_its_mass() -> void:
	var ed := ShipEditor.new(_template(), _catalog())
	var c := _open_top_cell(ed)
	assert_true(c.x != 1 << 20, "found an open top face")
	var plain := ShipEditor.new(_template(), _catalog())
	ed.paint_armor(c.y, Rect2i(c.x, c.z, 1, 1), ShipBlueprint.PLATE_THICK_MM, ShipEditor.PlateFaces.TOP)
	var key := ShipBlueprint.plate_key(c, &"dorsal")
	assert_true(ed.blueprint.armor.has(key), "plated %s" % key)
	ed.place_module(&"hull_block", c + Vector3i.UP, 0)
	plain.place_module(&"hull_block", c + Vector3i.UP, 0)
	assert_true(not ed.blueprint.armor.has(key) and not ed.report.has_code(&"armor_buried"), "the covered plate is gone")
	assert_near(ed.stats.mass_kg, plain.stats.mass_kg, 1e-3, "and so is its mass")
	assert_true(ed.undo() and ed.blueprint.armor.has(key), "one undo brings back the plate with the block gone")


func test_clear_all_armour_and_undo() -> void:
	var ed := ShipEditor.new(_template(), _catalog())
	var c := _open_top_cell(ed)
	ed.paint_armor(c.y, Rect2i(c.x, c.z, 1, 1), ShipBlueprint.PLATE_THIN_MM)
	var before := ed.blueprint.armor.duplicate()
	assert_true(not before.is_empty(), "some armour to clear")
	assert_true(ed.clear_armor() == before.size() and ed.blueprint.armor.is_empty(), "every plate stripped")
	assert_true(ed.undo() and ed.blueprint.armor == before, "undo puts them all back")
	assert_true(ed.clear_armor() > 0 and ed.clear_armor() == 0, "nothing left to clear the second time")


func test_loading_drops_buried_plates() -> void:
	var bp := _template()
	var grid := ShipGrid.build(bp, _catalog())
	var inner := Vector3i(1 << 20, 0, 0)
	for c: Vector3i in grid.module_at:
		if grid.is_hull(c + Vector3i.UP):
			inner = c
			break
	bp.armor[ShipBlueprint.plate_key(inner, &"dorsal")] = 40
	bp.armor[ShipBlueprint.plate_key(Vector3i(99, 99, 99), &"dorsal")] = 40
	assert_true(BlueprintFix.prune_plates(bp, grid) == 2, "a covered face and a cell with no hull")
	var p := PlayerProfile.new(3)
	p.ensure_vessel(_template())
	p.vessel.blueprint.armor[ShipBlueprint.plate_key(inner, &"dorsal")] = 40
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	assert_true(not q.vessel.blueprint.armor.has(ShipBlueprint.plate_key(inner, &"dorsal")), "pruned when the profile loads")


func test_deleting_a_room_takes_its_hatches() -> void:
	var ed := ShipEditor.new(_template(), _catalog())
	var room: ShipBlueprint.PlacedRoom
	var touching: Array[String] = []
	for r in ed.blueprint.rooms:
		var cells := ShipGrid.room_cells(r)
		touching.clear()
		for h in ed.blueprint.hatches:
			if cells.has(h.a) or cells.has(h.b):
				touching.append(h.id)
		if not touching.is_empty():
			room = r
			break
	assert_true(room != null, "a room with hatches")
	var hatches_before := ed.blueprint.hatches.size()
	assert_true(ed.remove(room.id), "room deleted")
	assert_true(ed.blueprint.hatches.size() == hatches_before - touching.size()
		and touching.all(func(id: String) -> bool: return ed.blueprint.find(id) == null), "its %d hatches went with it" % touching.size())
	assert_true(ed.undo() and ed.blueprint.find(room.id) != null
		and touching.all(func(id: String) -> bool: return ed.blueprint.find(id) != null), "one undo brings back room and hatches")


func test_engine_and_rcs_fractions_for_the_sound() -> void:
	var cfg := ShipConfig.new()
	cfg.thrust_forward_n = 1000.0
	cfg.thrust_reverse_n = 100.0
	cfg.thrust_lateral_n = 100.0
	cfg.engine_thrust_n = PackedFloat64Array([0, 0, 0, 0, 900, 0])
	var full_fwd := ShipDynamics.thrust_fractions(cfg, Vector3(0, 0, -1000), Vector3.ZERO)
	assert_near(full_fwd.x, 1.0, 1e-6, "full main burn")
	var reverse := ShipDynamics.thrust_fractions(cfg, Vector3(0, 0, 500), Vector3.ZERO)
	assert_near(reverse.x, 0.5, 1e-6, "reverse engines count as engines")
	var strafe := ShipDynamics.thrust_fractions(cfg, Vector3(50, 0, 0), Vector3.ZERO)
	assert_true(strafe.x == 0.0 and absf(strafe.y - 0.5) < 1e-6, "a strafe is RCS (%s)" % strafe)
	var turn := ShipDynamics.thrust_fractions(cfg, Vector3.ZERO, cfg.max_torque_nm * 0.25)
	assert_near(turn.y, 0.25, 1e-6, "turning is RCS too")
