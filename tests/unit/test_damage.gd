extends TestCase
## Measures: physical damage and ship systems (spec §16 "Damage", M3 exit
## criterion) — armour stops / obliquity, penetration path through systems,
## hull-cell hit detection, power networks, pressure and access, heat
## throttling, damage changing flight, and two layouts under one attack.

const CELL := ShipGrid.CELL_SIZE_M


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


## A ship state flying `bp` with live systems.
func _ship(bp: ShipBlueprint, id: StringName = &"s") -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


## Body-frame point for a grid-metre point.
func _body(ship: ShipState, grid_m: Vector3) -> Vector3:
	return grid_m - ship.systems.stats.center_of_mass_m


## Fire one round head-on into the nose along the line x = 3.5 cells at
## deck `deck`, travelling aft (+Z).
func _head_on(ship: ShipState, pen_mm: float, deck: int = 0) -> DamageReport:
	var p := _body(ship, Vector3(3.5 * CELL, (deck + 0.5) * CELL, 0.0))
	return Penetration.apply(ship.systems, p, Vector3(0, 0, 1), pen_mm)


func _room_index(bp: ShipBlueprint, id: String) -> int:
	for i in bp.rooms.size():
		if bp.rooms[i].id == id:
			return i
	return -1


# --- Armour ----------------------------------------------------------------------

func test_armour_stops_insufficient_penetration() -> void:
	var ship := _ship(_template())
	var r := _head_on(ship, 20.0)  # nose armour is 30 mm
	assert_true(r.stopped_by_armor and not r.penetrated, "20 mm round stopped by 30 mm nose armour:\n%s" % "\n".join(r.lines))
	assert_true(r.breached_rooms.is_empty() and r.damaged_ids.is_empty() and r.destroyed_ids.is_empty(), "nothing inside is touched")
	assert_near(ship.systems.modules[0].armor_mm, 29.0, 1e-6, "plate scuffed by 1 mm (mm)")


func test_oblique_hit_meets_thicker_armour() -> void:
	# 50 mm beats 30 mm head-on, but at 60° the plate is 60 mm effective.
	var head_on := _head_on(_ship(_template()), 50.0, 1)
	assert_true(head_on.penetrated, "50 mm penetrates head-on")
	var ship := _ship(_template())
	var dir := Vector3(sin(deg_to_rad(60.0)), 0, cos(deg_to_rad(60.0)))
	var p := _body(ship, Vector3(3.5 * CELL, 1.5 * CELL, 0.0))
	var oblique := Penetration.apply(ship.systems, p, dir, 50.0)
	assert_true(oblique.stopped_by_armor, "50 mm stopped at 60° obliquity:\n%s" % "\n".join(oblique.lines))


func test_penetrating_round_damages_systems_along_its_path() -> void:
	# Deck 0, x = 3: nose (empty) → lower corridor r14 → hatch h25 → reactor
	# room r15 → fusion reactor e28.
	var ship := _ship(_template())
	var r := _head_on(ship, 200.0)
	var text := "\n".join(r.lines)
	assert_true(r.penetrated, "penetrated the nose:\n%s" % text)
	assert_true(r.breached_rooms.has("r14") and r.breached_rooms.has("r15"), "corridor and reactor room breached:\n%s" % text)
	assert_true(r.destroyed_hatches.has("h25"), "hatch on the path destroyed:\n%s" % text)
	assert_true(r.damaged_ids.has("e28") or r.destroyed_ids.has("e28"), "reactor on the path hit:\n%s" % text)
	var reactor := ship.systems.equipment_by_id("e28")
	assert_near(reactor.hp, reactor.max_hp - reactor.def.shielding_mm(), 1e-6, "reactor took its shielding in damage (hp)")
	assert_true(not ship.systems.equipment_by_id("e33").destroyed(), "RCS off the path untouched")


func test_hits_use_hull_cells_not_the_bounding_box() -> void:
	var ship := _ship(_template())
	# Deck 2 above the nose is inside the bounding box but empty space.
	var a := _body(ship, Vector3(12.0, 7.5, -5.0))
	var b := _body(ship, Vector3(12.0, 7.5, 11.0))
	assert_near(Penetration.first_hull_entry(ship.systems, a, b), -1.0, 0.0, "path over the nose misses")
	var c := _body(ship, Vector3(12.0, 7.5, 20.0))
	assert_near(Penetration.first_hull_entry(ship.systems, a, c), (12.0 + 5.0) / 25.0, 1e-3, "path reaching the fuselage hits at its face")
	# Same thing through the world: a round crossing above the nose flies on.
	var world := WorldSimulation.new()
	world.add_ship(ship)
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"nobody"
	shot.position = _body(ship, Vector3(-30.0, 7.5, 4.5))
	shot.prev_position = shot.position
	shot.velocity = Vector3(1500, 0, 0)
	world.projectiles().append(shot)
	for i in 6:
		world.step()
	assert_true(world.take_hit_events().is_empty() and world.projectiles().size() == 1, "round passes through the empty corner")


# --- Power -----------------------------------------------------------------------

func test_wrecked_module_cuts_its_network_but_not_an_independent_one() -> void:
	var ship := _ship(_template())
	var sys := ship.systems
	assert_true(sys.count(EquipmentDefinition.Kind.MAIN_ENGINE, true) == 4, "all engines powered at start")
	sys.damage_module(2, 1e6)  # m3, the fuselage holding the only reactor
	ship.config = sys.effective_config()
	assert_true(sys.count(EquipmentDefinition.Kind.MAIN_ENGINE, true) == 0 and ship.config.thrust_forward_n == 0.0,
		"single reactor's junction cut: engines unpowered, no thrust")
	# Second reactor in the engine room: a separate network keeps the engines.
	var bp := _template()
	bp.add_equipment(&"fusion_reactor", Vector3i(2, 1, 13))
	assert_true(not ShipValidator.validate(bp, _catalog()).has_errors(), "two-reactor variant is valid")
	var redundant := _ship(bp)
	redundant.systems.damage_module(2, 1e6)
	redundant.config = redundant.systems.effective_config()
	assert_true(redundant.systems.count(EquipmentDefinition.Kind.MAIN_ENGINE, true) == 4, "engines on the second reactor stay powered")
	assert_true(redundant.systems.count(EquipmentDefinition.Kind.RCS, true) == 4,
		"only the 4 tail RCS stay powered; the nose RCS sit beyond the wrecked junction (%d)" % redundant.systems.count(EquipmentDefinition.Kind.RCS, true))


# --- Pressure and access ---------------------------------------------------------

func test_breach_seals_hatches_and_cuts_crew_access() -> void:
	var bp := _template()
	var ship := _ship(bp)
	var sys := ship.systems
	sys.breach_room(_room_index(bp, "r8"))  # main corridor
	assert_true(not sys.rooms[_room_index(bp, "r8")].pressurized, "corridor vented")
	assert_true(sys.rooms[_room_index(bp, "r7")].pressurized and sys.rooms[_room_index(bp, "r9")].pressurized,
		"bridge and quarters keep pressure behind sealed hatches")
	var cut := sys.cut_off_rooms()
	assert_true(cut.has("r9") and cut.has("r13") and not cut.has("r7"), "rooms behind the corridor cut off from the bridge: %s" % cut)
	sys.destroy_hatch("h18")  # bridge ↔ corridor
	assert_true(not sys.rooms[_room_index(bp, "r7")].pressurized, "bridge vents through its destroyed hatch")


# --- Heat ------------------------------------------------------------------------

func test_heat_throttles_then_scrams_the_reactor() -> void:
	var ship := _ship(_template())
	var sys := ship.systems
	for e in sys.equipment:
		if e.def.kind == EquipmentDefinition.Kind.RADIATOR:
			sys.damage_equipment(e, 1e6)
	ship.last_thrust_body = Vector3(0, 0, -ship.config.thrust_forward_n)
	var throttled_at := -1.0
	var scram_at := -1.0
	# Throttling cuts the reactor's waste heat, so the climb slows: ~3 min to
	# throttle, ~11 min to scram. Run 20 minutes at 0.1 s.
	for i in 12000:
		if sys.tick(ship, 0.1):
			ship.config = sys.effective_config()
		ship.last_thrust_body = Vector3(0, 0, -ship.config.thrust_forward_n)
		if throttled_at < 0.0 and sys.reactor_state == ShipSystems.Reactor.THROTTLED:
			throttled_at = i * 0.1
		if scram_at < 0.0 and sys.reactor_state == ShipSystems.Reactor.SCRAM:
			scram_at = i * 0.1
	assert_true(throttled_at > 0.0 and scram_at > throttled_at,
		"no radiators at full thrust: throttle at %.0f s, then scram at %.0f s" % [throttled_at, scram_at])
	assert_true(ship.config.thrust_forward_n == 0.0 or sys.reactor_state != ShipSystems.Reactor.SCRAM,
		"a scrammed reactor leaves the engines without power")
	# Intact radiators: the same burn stays cool.
	var cool := _ship(_template())
	cool.last_thrust_body = Vector3(0, 0, -cool.config.thrust_forward_n)
	for i in 6000:
		cool.systems.tick(cool, 0.1)
	assert_true(cool.systems.reactor_state == ShipSystems.Reactor.NORMAL and cool.systems.temperature_k < ShipSystems.THROTTLE_TEMP_K,
		"with radiators the reactor stays normal (%.0f K)" % cool.systems.temperature_k)


# --- Damage changes flight ------------------------------------------------------

func test_damage_reduces_thrust_torque_and_guns() -> void:
	var ship := _ship(_template())
	var sys := ship.systems
	var full := ship.config.thrust_forward_n
	sys.damage_equipment(sys.equipment_by_id("e29"), 1e6)  # lower-left engine
	sys.damage_equipment(sys.equipment_by_id("e31"), 1e6)  # upper-left engine
	ship.config = sys.effective_config()
	assert_near(ship.config.thrust_forward_n, full * 0.5, 1.0, "two of four engines lost: half thrust (N)")
	assert_true(absf(ship.config.thrust_torque_body.y) > 1e5, "one-sided engines now yaw the ship (%.0f N·m)" % ship.config.thrust_torque_body.y)
	# A destroyed cannon cannot fire.
	sys.damage_equipment(sys.equipment_by_id("e41"), 1e6)
	var world := WorldSimulation.new()
	world.add_ship(ship)
	var fire := ShipControlInput.neutral()
	fire.fire = true
	world.set_input(&"s", fire)
	world.step()
	assert_true(world.projectiles().is_empty(), "destroyed cannon does not fire")


func test_destroyed_tank_spills_its_share_of_propellant() -> void:
	var bp := _template()
	var ship := _ship(bp)
	var world := WorldSimulation.new()
	world.add_ship(ship)
	var before := ship.propellant_kg
	# Fire through the port pod's tanks (deck 0, x = 0.5 cell), side-on.
	var shot := ProjectileState.new()
	shot.id = 1
	shot.shooter_id = &"gun"
	shot.weapon = load("res://data/weapons/medium_kinetic_cannon.tres")
	var shooter := ShipState.create(&"gun", "G", load("res://data/ships/placeholder_frigate.tres"), Vector3(0, 0, 9e5))
	world.add_ship(shooter)
	var pod_cell_center := Vector3(0.5 * CELL, 0.5 * CELL, 7.5 * CELL)
	shot.position = _body(ship, pod_cell_center + Vector3(-60.0, 0, 0))
	shot.prev_position = shot.position
	shot.velocity = Vector3(1500, 0, 0)
	world.projectiles().append(shot)
	var report: DamageReport = null
	for i in 10:
		world.step()
		for ev in world.take_hit_events():
			report = ev.report
	assert_true(report != null, "round hit the pod")
	if report != null:
		var text := "\n".join(report.lines)
		assert_true(report.damaged_ids.has("e46") or report.destroyed_ids.has("e46"), "tank on the path hit:\n%s" % text)
	# Finish the tank off and check the spill.
	var tank := ship.systems.equipment_by_id("e46")
	var r := DamageReport.new()
	if not tank.destroyed():
		ship.systems.damage_equipment(tank, 1e6)
		r.propellant_lost_kg = tank.def.propellant_capacity_kg
		world._apply_damage(ship, r)
	assert_near(ship.propellant_kg, before * 0.75, before * 0.01, "one of four tanks lost: a quarter of the propellant gone (kg)")


# --- Exit criterion: layout matters ----------------------------------------------

func test_two_layouts_react_differently_to_the_same_attack() -> void:
	# Same parts; B moves the reactor into an engineering room in the nose.
	var a := _template()
	var b := _template()
	b.remove("e28")
	b.add_room(&"reactor_room", 0, Rect2i(2, 0, 4, 3))  # nose, lower deck, z 0–2
	b.add_room(&"corridor", 0, Rect2i(2, 3, 4, 1))       # nose, lower deck, z 3
	b.add_hatch(Vector3i(3, 0, 2), Vector3i(3, 0, 3))
	b.add_hatch(Vector3i(3, 0, 3), Vector3i(3, 0, 4))    # into the lower corridor r14
	b.add_equipment(&"fusion_reactor", Vector3i(3, 0, 0))
	var report_b := ShipValidator.validate(b, _catalog())
	assert_true(not report_b.has_errors(), "layout B is a valid design:\n%s" % report_b.summary())
	var ship_a := _ship(a, &"a")
	var ship_b := _ship(b, &"b")
	var last_a: DamageReport
	var last_b: DamageReport
	var log_b := PackedStringArray()
	for i in 6:  # identical volley: six 60 mm rounds, head-on, deck 0, x = 3
		last_a = _head_on(ship_a, 60.0)
		last_b = _head_on(ship_b, 60.0)
		log_b.append_array(last_b.lines)
	ship_a.config = ship_a.systems.effective_config()
	ship_b.config = ship_b.systems.effective_config()
	var reactor_a := ship_a.systems.equipment_by_id("e28")
	assert_true(reactor_a != null and not reactor_a.destroyed() and ship_a.config.thrust_forward_n > 0.0,
		"A: reactor behind the corridor survives, engines powered:\n%s" % "\n".join(last_a.lines))
	var destroyed_reactor := false
	for e in ship_b.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.REACTOR and e.destroyed():
			destroyed_reactor = true
	assert_true(destroyed_reactor and ship_b.config.thrust_forward_n == 0.0,
		"B: reactor in the nose destroyed, no power, no thrust:\n%s" % "\n".join(log_b))
	assert_true("\n".join(log_b).contains("Fusion reactor") and "\n".join(log_b).contains("destroyed"),
		"B's damage report explains why")


# --- Enemy gunnery ---------------------------------------------------------------

func test_gunnery_ai_turns_onto_target_and_hits() -> void:
	# Hostile frigate starts 40° off a target crossing at 40 m/s, 2 km away; within 30 s it must
	# swing onto the lead, fire and land a round on the player's hull.
	var world := WorldSimulation.new()
	var gunner := _ship(_template(), &"a_gunner")
	gunner.orientation = Quaternion(Vector3.UP, deg_to_rad(40.0))
	gunner.snapshot_previous()
	var victim := _ship(_template(), &"b_victim")
	victim.position = Vector3(0, 0, -2000)
	victim.velocity = Vector3(40, 0, 0)  # LOS turns 0.02 rad/s: P-only aim would lag ~0.6°
	victim.snapshot_previous()
	world.add_ship(gunner)
	world.add_ship(victim)
	var first_hit := -1.0
	var hits_total := 0
	var report: DamageReport = null
	for i in 30 * 60:
		world.set_input(&"a_gunner", GunneryAI.command(gunner, victim))
		world.step()
		for ev in world.take_hit_events():
			hits_total += 1
			if first_hit < 0.0:
				first_hit = world.sim_time
				report = ev.report
	assert_true(first_hit > 0.0 and first_hit < 20.0, "AI gunner hit the target within 20 s (first hit %.1f s)" % first_hit)
	assert_true(report != null and not report.lines.is_empty(), "the hit produced a damage report")
	# Sustained tracking: a lagging aim stops firing once settled; this one keeps
	# landing rounds, and fires only when aligned.
	assert_true(hits_total >= 20, "sustained hits on a crossing target (%d)" % hits_total)
	assert_true(float(hits_total) / maxf(gunner.rounds_fired, 1) > 0.6,
		"fires only when aligned: %d hits from %d rounds" % [hits_total, gunner.rounds_fired])


# --- Reactor explosion ------------------------------------------------------------

func test_reactor_at_zero_explodes_and_wrecks_its_surroundings() -> void:
	var ship := _ship(_template())
	var s := ship.systems
	var reactor := s.equipment_by_id("e28")
	var near := s.equipment_by_id("e46")   # propellant tank beside the reactor room
	var far := s.equipment_by_id("e35")    # RCS on the nose
	s.damage_equipment(reactor, 1000.0)
	var blasts := s.take_explosions()
	assert_true(blasts.size() == 1 and blasts[0].lines[0].contains("CONTAINMENT FAILURE"), "reactor at 0 % explodes")
	assert_true(near.hp < near.max_hp, "a tank %.0f m away is damaged (%.0f / %.0f hp)" % [near.body_position.distance_to(reactor.body_position), near.hp, near.max_hp])
	assert_near(far.hp, far.max_hp, 1e-6, "the nose RCS %.0f m away is untouched (hp)" % far.body_position.distance_to(reactor.body_position))
	var reactor_room := _room_index(s.blueprint, "r15")
	assert_true(s.rooms[reactor_room].breached, "the reactor room is blown open")
	assert_true(s.crew.in_room(reactor_room).is_empty(), "nobody left standing in the reactor room")


func test_a_round_that_kills_the_reactor_reports_the_explosion() -> void:
	var ship := _ship(_template())
	ship.systems.damage_equipment(ship.systems.equipment_by_id("e28"), 59.0)  # 1 hp left
	var p := _body(ship, Vector3(3.5 * CELL, 0.5 * CELL, 9.0 * CELL))
	var r := Penetration.apply(ship.systems, p + Vector3(0, 40, 0), Vector3(0, -1, 0), 400.0)
	assert_true(r.destroyed_ids.has("e28") and r.events.any(func(e: Dictionary) -> bool: return e.kind == &"explosion"),
		"the hit report includes the explosion:
%s" % "
".join(r.lines))
