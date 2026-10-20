extends TestCase
## Measures: the second play-test batch — fuller launchers, salvo fire and
## its modes (all / conventional / EMP / nuclear / sequence), the
## saturation pod's swarm, missiles breaking up when shot down, cheap
## restocking, beaten ships left as silent derelicts, bigger boarding
## parties and who would go, and the crew roster's helpers.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _bp(path: String = BlueprintIO.DEFAULT_TEMPLATE) -> ShipBlueprint:
	return BlueprintIO.load_file(path, PackedStringArray())


func _armed(launchers: Array) -> ShipBlueprint:
	var bp := _bp()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for id in launchers:
		EnemyFactory._fit_launcher(bp, _catalog(), id, rng)
	return bp


func _ship(id: StringName, bp: ShipBlueprint, pos: Vector3 = Vector3.ZERO) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


## Shooter "a" with `launchers`, a cutter (no point defence) "b" far ahead.
func _duel(launchers: Array, range_m: float = 6000.0) -> WorldSimulation:
	var world := WorldSimulation.new(DT)
	world.add_ship(_ship(&"a", _armed(launchers)))
	world.add_ship(_ship(&"b", _bp("res://data/blueprints/cutter_mk1.json"), Vector3(0, 0, -range_m)))
	return world


func _fired_warheads(world: WorldSimulation) -> Array[int]:
	var out: Array[int] = []
	for m in world.missiles:
		out.append(m.missile.warhead)
	return out


func test_launchers_hold_more_and_restock_cheaply() -> void:
	var eq := _catalog().equipment
	assert_true(eq[&"missile_rack"].missile_capacity == 12 and eq[&"emp_launcher"].missile_capacity == 6
		and eq[&"nuclear_launcher"].missile_capacity == 3, "12 / 6 / 3 missiles")
	var pod: EquipmentDefinition = eq[&"saturation_pod"]
	assert_true(pod.validate().is_empty() and pod.missile_capacity == 48 and pod.missile_salvo == 8, "the saturation pod: 48, 8 a launch")
	assert_true(eq[&"missile_rack"].missile.unit_credits <= 10 and eq[&"emp_launcher"].missile.unit_credits <= 25
		and eq[&"nuclear_launcher"].missile.unit_credits <= 200 and pod.missile.unit_credits <= 3, "restocking costs little")


func test_the_saturation_pod_launches_a_swarm_of_weaker_missiles() -> void:
	var world := _duel([&"saturation_pod"])
	var sys := world.get_ship(&"a").systems
	assert_true(world.launch_missile(&"a", &"b") == "", "away")
	assert_true(world.missiles.size() == 8, "eight in one launch (%d)" % world.missiles.size())
	var spots := {}
	for m in world.missiles:
		spots[Vector3i(m.position.round())] = true
	assert_true(spots.size() == 8, "fanned out, not stacked")
	var pod_left := 0
	for e in sys.equipment:
		if e.def.id == &"saturation_pod":
			pod_left = sys.missiles_left(e)
	assert_true(pod_left == 40, "40 left")
	var small: MissileConfig = _catalog().equipment[&"saturation_pod"].missile
	var big: MissileConfig = _catalog().equipment[&"missile_rack"].missile
	assert_true(small.penetration_mm < big.penetration_mm * 0.5 and small.blast_hp < big.blast_hp * 0.5, "each hits far softer")
	# Small blasts are bursts, not big explosions with their own notices.
	var target := world.get_ship(&"b")
	target.systems.blast_at(Vector3.ZERO, small.blast_radius_m, small.blast_structure_fraction, small.blast_hp, "test")
	assert_true(target.systems.take_explosions().is_empty(), "no big explosion for a small warhead")


func test_salvo_modes_pick_their_warheads() -> void:
	var order := [MissileConfig.Warhead.NUCLEAR, MissileConfig.Warhead.EMP]
	assert_true(MissileSalvo.groups_for(MissileSalvo.Mode.ALL, order) == [-1], "all: any warhead")
	assert_true(MissileSalvo.groups_for(MissileSalvo.Mode.EMP, order) == [MissileConfig.Warhead.EMP], "EMP only")
	assert_true(MissileSalvo.groups_for(MissileSalvo.Mode.SEQUENCE, order) == [MissileConfig.Warhead.NUCLEAR, MissileConfig.Warhead.EMP,
		MissileConfig.Warhead.ANTI_SHIP], "sequence: the order, completed")
	assert_true(MissileSalvo.sanitize_order([7, 1, 1, "x"]) == [1, 0, 2], "a bad saved order is fixed up")
	assert_true(MissileSalvo.order_text(MissileSalvo.DEFAULT_ORDER) == "EMP → conventional → nuclear", "readable order")


func test_a_salvo_empties_the_chosen_launchers_and_nothing_else() -> void:
	var world := _duel([&"missile_rack", &"emp_launcher"])
	var sys := world.get_ship(&"a").systems
	var s := MissileSalvo.start(&"a", &"b", MissileSalvo.Mode.CONVENTIONAL, [])
	assert_true(s.available(sys) == 12, "twelve conventional ready")
	var t := 0.0
	while not s.done() and t < 30.0:
		s.step(world)
		world.step()
		t += DT
	assert_true(s.launched == 12 and sys.missiles_of(MissileConfig.Warhead.ANTI_SHIP) == 0, "the whole rack went (%d)" % s.launched)
	assert_true(sys.missiles_of(MissileConfig.Warhead.EMP) == 6, "EMP untouched")
	assert_true(t < 12 * ShipSystems.LAUNCHER_CYCLE_S + 1.0, "as fast as the tube cycles (%.1f s)" % t)


func test_a_sequence_salvo_fires_in_order() -> void:
	var world := _duel([&"missile_rack", &"emp_launcher"])
	var s := MissileSalvo.start(&"a", &"b", MissileSalvo.Mode.SEQUENCE, [MissileConfig.Warhead.EMP, MissileConfig.Warhead.ANTI_SHIP])
	var seen: Array[int] = []
	var t := 0.0
	while not s.done() and t < 30.0:
		var before := world.missiles.size()
		s.step(world)
		for m in world.missiles.slice(before):
			seen.append(m.missile.warhead)
		world.step()
		t += DT
	var first_conventional := seen.find(MissileConfig.Warhead.ANTI_SHIP)
	assert_true(seen.size() == 18 and first_conventional == 6, "six EMP first, then the twelve conventional (%s)" % [seen])


func test_a_salvo_stops_when_the_target_is_gone() -> void:
	var world := _duel([&"missile_rack"])
	var s := MissileSalvo.start(&"a", &"b", MissileSalvo.Mode.ALL, [])
	s.step(world)
	world.remove_ship(&"b")
	assert_true(s.step(world) == 0 and s.done(), "no target, no more launches")


func test_a_missile_shot_down_breaks_up_with_a_burst() -> void:
	var world := WorldSimulation.new(DT)
	world.add_ship(_ship(&"a", _armed([&"missile_rack"])))
	world.add_ship(_ship(&"b", _bp(), Vector3(0, 0, -4000)))  # two point-defence turrets
	world.launch_missile(&"a", &"b")
	var bursts: Array[Dictionary] = []
	var t := 0.0
	while not world.missiles.is_empty() and t < 40.0:
		world.step()
		bursts.append_array(world.take_bursts())
		t += DT
	var broke := bursts.filter(func(b: Dictionary) -> bool: return b.get("shot_down", false))
	assert_true(broke.size() == 1 and world.get_ship(broke[0].ship_id) != null, "one break-up burst, riding a ship (%s)" % [bursts])


func test_a_beaten_ship_stays_as_a_silent_derelict() -> void:
	var world := WorldSimulation.new(DT)
	var player := _ship(&"player", _bp())
	world.add_ship(player)
	var enemy := _ship(&"target_01", _armed([&"missile_rack"]), Vector3(0, 0, -1500))
	world.add_ship(enemy)
	var wing := AirWing.for_ship(enemy)
	wing.target_id = &"player"
	world.wings.append(wing)
	for c in wing.crafts:
		wing.launch(world, c)
		break
	world.step()
	world.launch_missile(&"target_01", &"player")
	var craft_ids := wing.flying().map(func(c: AirWing.Craft) -> StringName: return c.id)
	var wreck := world.retire_ship(&"target_01", &"wreck_01")
	assert_true(wreck == enemy and wreck.id == &"wreck_01" and wreck.derelict and world.has_ship(&"wreck_01")
		and not world.has_ship(&"target_01"), "kept, under a new id, derelict")
	assert_true(not world.wings.has(wing) and wing.carrier_id == &"wreck_01", "its wing no longer flies")
	for id in craft_ids:
		var renamed := StringName(String(id).replace("target_01", "wreck_01"))
		assert_true(world.has_ship(renamed) and world.get_ship(renamed).derelict and not world.has_ship(id), "craft %s → %s, derelict" % [id, renamed])
	assert_true(world.missiles.all(func(m: ShipState) -> bool: return m.missile_owner == &"wreck_01"), "its missile in flight keeps its owner")
	# Ordered to fire, it doesn't: commands and point defence are ignored.
	var input := GunneryAI.command(wreck, player)
	input.fire = true
	world.set_input(&"wreck_01", input)
	var fired := wreck.rounds_fired
	for i in 120:
		world.step()
	assert_true(wreck.rounds_fired == fired and Array(wreck.pd_rounds).all(func(r: int) -> bool: return r == wreck.config.pd_gun.magazine_rounds),
		"no rounds, no point defence")
	# A new contact can take the old id.
	world.add_ship(_ship(&"target_01", _bp(), Vector3(0, 0, -3000)))
	assert_true(world.has_ship(&"target_01") and world.has_ship(&"wreck_01"), "a new contact alongside the wreck")


func test_boarding_parties_can_be_bigger_and_we_see_who_would_go() -> void:
	assert_true(BoardingAction.MAX_TEAM > 8, "the party limit is past 8 (%d)" % BoardingAction.MAX_TEAM)
	var sys := _ship(&"p", _bp()).systems
	var collars := Docking.collars(sys)
	assert_true(not collars.is_empty(), "the template has a collar")
	var everyone := BoardingAction.candidates(sys, collars[0].room, BoardingAction.MAX_TEAM)
	var fighters := sys.crew.members.filter(func(m: CrewRoster.Member) -> bool:
		return m.role == CrewRoster.Role.SECURITY or m.role == CrewRoster.Role.GENERAL)
	assert_true(everyone.size() == mini(fighters.size(), BoardingAction.MAX_TEAM) and everyone.size() > 0, "every security and general hand (%d)" % everyone.size())
	assert_true(everyone[0].role == CrewRoster.Role.SECURITY, "security first")
	assert_true(BoardingAction.candidates(sys, collars[0].room, 3).size() == mini(3, everyone.size()), "no more than the party size")


func test_the_crew_roster_helpers() -> void:
	assert_true(CrewRoster.ROLE_COLORS.size() == CrewRoster.ROLE_NAMES.size() and CrewRoster.ROLE_SHORT.size() == CrewRoster.ROLE_NAMES.size(),
		"a colour and a short name per post")
	var distinct := {}
	for c in CrewRoster.ROLE_COLORS:
		distinct[(c as Color).to_html(false)] = true
	assert_true(distinct.size() == CrewRoster.ROLE_COLORS.size(), "every post its own colour")
	assert_true(CrewRoster.suggested(1)[CrewRoster.Role.WEAPONS] == 1 and CrewRoster.suggested(5)[CrewRoster.Role.WEAPONS] == 2, "gunners by guns")
	var sys := _ship(&"p", _bp()).systems
	var m := sys.crew.members[0]
	assert_true(TacticalOverview.crew_status(sys, m) == "fit", "at post: fit")
	m.state = CrewRoster.State.WOUNDED
	m.location = -1
	assert_true(TacticalOverview.crew_status(sys, m) == "wounded · boarding party", TacticalOverview.crew_status(sys, m))


func test_missile_mode_and_order_are_saved() -> void:
	var p := PlayerProfile.new(1)
	p.missile_mode = MissileSalvo.Mode.SEQUENCE
	p.missile_order = [MissileConfig.Warhead.NUCLEAR, MissileConfig.Warhead.ANTI_SHIP, MissileConfig.Warhead.EMP]
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	assert_true(q.missile_mode == MissileSalvo.Mode.SEQUENCE and q.missile_order == p.missile_order, "kept: %s" % [q.missile_order])
	var old := p.to_dict()
	old.erase("missile_mode")
	old.erase("missile_order")
	var r := PlayerProfile.from_dict(old, PackedStringArray())
	assert_true(r.missile_mode == MissileSalvo.Mode.ALL and r.missile_order == MissileSalvo.DEFAULT_ORDER, "older saves: all, default order")


func test_missile_hits_are_not_gun_hits_in_the_debrief() -> void:
	var world := _duel([&"missile_rack"], 2000.0)
	var log := CombatLog.begin(world.get_ship(&"a"), 0.0)
	world.launch_missile(&"a", &"b")
	var t := 0.0
	while not world.missiles.is_empty() and t < 30.0:
		world.step()
		for ev in world.take_hit_events():
			log.note_hit(ev, &"a", world.sim_time, world)
		t += DT
	assert_true(log.missile_hits == 1 and log.hits_scored == 0, "one missile hit, no gun hits (%d / %d)" % [log.missile_hits, log.hits_scored])
	log.missiles_launched = 1
	log.finish(world.get_ship(&"a"), "test", world.sim_time)
	var d := log.to_dict()
	var text := "\n".join(CombatLog.summary(d)) + "\n".join(CombatLog.insights(d))
	assert_true(text.contains("1 missile launched, 1 struck") and not text.contains("Accuracy"), "accuracy counts rounds only:\n%s" % text)
