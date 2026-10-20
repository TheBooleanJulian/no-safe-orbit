extends TestCase
## Measures: play-test batch 5 — fighters never fire with a friend in the
## line of fire and their rounds spare their own side (IFF), keep apart from
## each other; interceptors shoot down missiles, bombers fire from long
## range, EW drones hold station between the carrier and the threat; harder
## ramming, worse for the lighter ship; flares fire on their own once an
## inbound missile is armed; every role and directive is explained in game.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _ship(id: StringName, pos: Vector3, side: StringName, bp: ShipBlueprint = null) -> ShipState:
	if bp == null:
		bp = BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.side = side
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _craft(id: StringName, path: String, pos: Vector3, side: StringName) -> ShipState:
	var c := ShipState.create(id, String(id), load(path) as ShipConfig, pos)
	c.side = side
	return c


func test_no_shot_through_a_friend_and_iff_rounds_spare_their_side() -> void:
	var me := _craft(&"me", "res://data/craft/wasp_fighter.tres", Vector3.ZERO, &"player")
	var friend := _craft(&"pal", "res://data/craft/wasp_fighter.tres", Vector3(0, 0, -300), &"player")
	var foe := _craft(&"foe", "res://data/craft/wasp_fighter.tres", Vector3(0, 0, -600), &"hostile")
	var friends: Array[ShipState] = [me, friend]
	assert_true(not CraftAI.clear_shot(me, Vector3(0, 0, -1), 600.0, friends, foe), "a friend in the line of fire: hold")
	friend.position = Vector3(80, 0, -300)
	assert_true(CraftAI.clear_shot(me, Vector3(0, 0, -1), 600.0, friends, foe), "moved 80 m aside: clear")
	# IFF: a craft's round through a friendly craft carries on.
	var world := WorldSimulation.new(DT)
	world.add_ship(me)
	friend.position = Vector3(0, 0, -300)
	world.add_ship(friend)
	var shot := ProjectileState.new()
	shot.shooter_id = &"me"
	shot.iff_side = &"player"
	shot.weapon = load("res://data/weapons/fighter_gun.tres")
	shot.position = Vector3(0, 0, -250)
	shot.prev_position = shot.position
	shot.velocity = Vector3(0, 0, -900)
	shot.age_s = 1.0
	world._rounds.append(shot)
	for i in 10:
		world.step()
	assert_true(friend.hull_damage == 0.0 and world.take_hit_events().is_empty(), "the IFF interlock spares the friendly craft")


func test_escorts_keep_apart() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", Vector3.ZERO, &"player")
	world.add_ship(carrier)
	var wing := AirWing.for_ship(carrier)
	world.wings.append(wing)
	for c in wing.crafts:
		c.directive = CraftAI.Directive.ESCORT
	wing.launch_all(world)
	var closest := INF
	for i in roundi(60.0 / DT):
		world.step()
		var flying := wing.flying()
		for a in flying.size():
			for b in range(a + 1, flying.size()):
				var sa := world.get_ship(flying[a].id)
				var sb := world.get_ship(flying[b].id)
				if sa != null and sb != null and i > 300:
					closest = minf(closest, sa.position.distance_to(sb.position))
	print("    measured: escorts never closer than %.0f m" % closest)
	assert_true(closest > 25.0, "craft keep apart (closest %.0f m)" % closest)


func test_an_interceptor_shoots_down_a_missile() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", Vector3.ZERO, &"player")
	world.add_ship(carrier)
	var shooter := _ship(&"enemy", Vector3(0, 0, -7000), &"hostile")
	EnemyFactory._fit_launcher(shooter.systems.blueprint, _catalog(), &"missile_rack", RandomNumberGenerator.new())
	var bp := shooter.systems.blueprint
	world.remove_ship(&"enemy")
	shooter = _ship(&"enemy", Vector3(0, 0, -7000), &"hostile", bp)
	world.add_ship(shooter)
	var hornet := _craft(&"c_hornet", "res://data/craft/hornet_interceptor.tres", Vector3(0, 30, -200), &"player")
	world.add_ship(hornet)
	hornet.propellant_kg = hornet.config.propellant_capacity_kg
	world.launch_missile(&"enemy", &"c")
	var missiles: Array[ShipState] = world.missiles.duplicate()
	var friends: Array[ShipState] = [carrier, hornet]
	var events := ""
	for i in roundi(30.0 / DT):
		var no_hostiles: Array[ShipState] = []
		world.set_input(&"c_hornet", CraftAI.command(hornet, CraftAI.Directive.ESCORT, carrier, Vector3.ZERO, shooter, no_hostiles, 0, 0,
			friends, world.missiles.duplicate(), DT))
		world.step()
		events += "\n".join(world.take_link_events())
		if world.missiles.is_empty():
			break
	print("    measured: interceptor vs missile — %s" % ("shot down" if events.contains("shot down") else events.right(120)))
	assert_true(events.contains("shot down") and not events.contains("hit c"), "the Hornet shoots the missile down before it reaches the ship")


func test_a_bomber_fires_from_long_range() -> void:
	var world := WorldSimulation.new(DT)
	var target := _ship(&"t", Vector3(0, 0, -3000), &"hostile")
	world.add_ship(target)
	var bomber := _craft(&"b", "res://data/craft/mantis_bomber.tres", Vector3.ZERO, &"player")
	bomber.propellant_kg = bomber.config.propellant_capacity_kg
	world.add_ship(bomber)
	var first_shot := -1.0
	var no_hostiles: Array[ShipState] = []
	for i in roundi(90.0 / DT):
		world.set_input(&"b", CraftAI.command(bomber, CraftAI.Directive.STRIKE, null, Vector3.ZERO, target, no_hostiles, 0, 0, [bomber], [], DT))
		var before := bomber.cannon_rounds
		world.step()
		if bomber.cannon_rounds < before and first_shot < 0.0:
			first_shot = bomber.position.distance_to(target.position)
	print("    measured: the bomber opened fire at %.0f m" % first_shot)
	assert_true(first_shot > 800.0, "it opens fire from long range (%.0f m)" % first_shot)


func test_an_ew_drone_holds_station_towards_the_threat() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", Vector3.ZERO, &"player")
	world.add_ship(carrier)
	var threat := _ship(&"t", Vector3(6000, 0, 0), &"hostile")
	world.add_ship(threat)
	var drone := _craft(&"c_ew", "res://data/craft/ew_drone.tres", Vector3(0, 30, 50), &"player")
	drone.propellant_kg = drone.config.propellant_capacity_kg
	world.add_ship(drone)
	var no_hostiles: Array[ShipState] = []
	for i in roundi(90.0 / DT):
		world.set_input(&"c_ew", CraftAI.command(drone, CraftAI.Directive.ESCORT, carrier, Vector3.ZERO, threat, no_hostiles, 0, 0, [carrier, drone], [], DT))
		world.step()
	var off := drone.position - carrier.position
	print("    measured: EW drone %.0f m out, %.0f° off the line to the threat" % [off.length(), rad_to_deg(off.angle_to(threat.position - carrier.position))])
	assert_near(off.length(), CraftAI.EW_STATION_M, 300.0, "about 1.2 km out (m)")
	assert_true(rad_to_deg(off.angle_to(threat.position - carrier.position)) < 25.0, "between the carrier and the threat")
	assert_true(off.length() <= WorldSimulation.EW_ESCORT_M, "close enough for its jamming to cover the carrier")


func test_ramming_is_harder_and_worse_for_the_lighter_ship() -> void:
	var world := WorldSimulation.new(DT)
	var big := _ship(&"big", Vector3.ZERO, &"a", BlueprintIO.load_file("res://data/blueprints/destroyer_mk1.json", PackedStringArray()))
	var small := _ship(&"small", Vector3(0, 0, -120), &"b", BlueprintIO.load_file("res://data/blueprints/cutter_mk1.json", PackedStringArray()))
	small.velocity = Vector3(0, 0, 8)
	world.add_ship(big)
	world.add_ship(small)
	var before := {}
	for s in [big, small]:
		var t := 0.0
		for m in s.systems.modules:
			t += m.structure
		before[s.id] = t
	for i in roundi(20.0 / DT):
		world.step()
	var lost := {}
	var hit_modules := {}
	for s in [big, small]:
		var t := 0.0
		var n := 0
		for m in s.systems.modules:
			t += m.structure
			if m.structure < m.max_structure:
				n += 1
		lost[s.id] = (float(before[s.id]) - t) / float(before[s.id])
		hit_modules[s.id] = n
	print("    measured: 8 m/s ram — destroyer lost %.1f %% of its structure (%d modules), the cutter %.1f %% (%d modules)" % [
		float(lost.big) * 100.0, hit_modules.big, float(lost.small) * 100.0, hit_modules.small])
	assert_true(float(lost.small) > float(lost.big) * 3.0, "the lighter cutter takes far more of the blow")
	assert_true(int(hit_modules.small) >= 2 and float(lost.big) > 0.0, "it spreads through the hull; both are hurt")


func test_flares_fire_once_a_missile_is_armed() -> void:
	var world := WorldSimulation.new(DT)
	var me := _ship(&"me", Vector3.ZERO, &"player")
	# Its point defence off, so the missile lives long enough to be flared.
	var no_pd := ShipPolicy.preset("Hold")
	no_pd.pd_enabled = false
	me.policy = no_pd
	world.add_ship(me)
	var foe := _ship(&"foe", Vector3(0, 0, -700), &"hostile")
	world.add_ship(foe)
	EnemyFactory._fit_launcher(foe.systems.blueprint, _catalog(), &"missile_rack", RandomNumberGenerator.new())
	var bp := foe.systems.blueprint
	world.remove_ship(&"foe")
	foe = _ship(&"foe", Vector3(0, 0, -700), &"hostile", bp)
	world.add_ship(foe)
	world.launch_missile(&"foe", &"me")
	var policy := ShipPolicy.preset("Hold")
	var unarmed := Hud.missile_inbound_time(world, me, true)
	assert_true(unarmed < 0.0 and Hud.missile_inbound_time(world, me) >= 0.0, "a missile off the rail is not yet a threat to answer")
	assert_true(not policy.cm_due(unarmed), "so no flares yet, even in Hold")
	var due_at := -1.0
	var armed_at := -1.0
	for i in roundi(30.0 / DT):
		world.step()
		var t := Hud.missile_inbound_time(world, me, true)
		if t >= 0.0 and armed_at < 0.0:
			armed_at = world.sim_time
		if policy.cm_due(t):
			due_at = t
			break
	print("    measured: armed at %.1f s; flares due %.1f s before impact" % [armed_at, due_at])
	assert_true(armed_at > 0.0 and due_at > 0.0 and due_at <= policy.cm_lead_s, "once armed and inside the lead, flares are due")


func test_roles_and_directives_are_explained() -> void:
	for role in [&"fighter", &"interceptor", &"bomber", &"recon", &"ew"]:
		assert_true(str(CraftAI.ROLE_HELP.get(role, "")).length() > 20, "%s is explained" % role)
	assert_true(CraftAI.DIRECTIVE_HELP.size() == CraftAI.DIRECTIVE_NAMES.size(), "every directive is explained")
	for path in ["res://data/craft/hornet_interceptor.tres", "res://data/craft/mantis_bomber.tres", "res://data/craft/ew_drone.tres", "res://data/craft/recon_drone.tres"]:
		assert_true(CraftAI.ROLE_HELP.has((load(path) as ShipConfig).craft_role), "%s has a known role" % path)
	assert_true(Hud.HELP_TEXT.contains("Space flares") and Hud.HELP_TEXT.contains("burns through"), "the help card explains flares and jamming")
	var eq := _catalog().equipment
	for id in [&"interceptor_rack", &"bomber_bay"]:
		assert_true(eq.has(id) and (eq[id] as EquipmentDefinition).validate().is_empty(), "%s is a valid part" % id)
