extends TestCase
## Measures: play-test batch 11, part 1 — combat rules and craft. No hostile
## toggle any more; craft fly their role's default; fighters aim at weak
## spots, come home earlier and with the propellant to get there, and take
## twice the punishment; lasers come in three tiers; flares go out one at a
## time and trail sparks; at battle stations the emergency doors shut and the
## crew spread through the ship.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _ship(id: StringName, swap: Dictionary = {}, template: String = BlueprintIO.DEFAULT_TEMPLATE) -> ShipState:
	var bp := BlueprintIO.load_file(template, PackedStringArray())
	for e in bp.equipment:
		if swap.has(e.def_id):
			e.def_id = swap[e.def_id]
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg)
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func test_no_hostile_toggle() -> void:
	assert_true(not InputMap.has_action(&"toggle_target_ai"), "no T action")
	for row: Array in InputBindings.ACTIONS:
		assert_true(row[0] != &"toggle_target_ai", "not in the bindings list")


func test_craft_default_to_their_role() -> void:
	var seen := {}
	for f in DirAccess.get_files_at("res://data/craft"):
		if not f.ends_with(".tres"):
			continue
		var cfg: ShipConfig = load("res://data/craft/" + f)
		seen[String(cfg.craft_role)] = CraftAI.DIRECTIVE_NAMES[CraftAI.default_directive(cfg)]
	print("    measured: defaults — %s" % seen)
	assert_true(seen["repair"] == "Escort" and seen["salvage"] == "Escort", "repair and salvage drones stay by the carrier")
	assert_true(seen["recon"] == "Recon" and seen["ew"] == "Recon", "recon and EW drones watch")
	assert_true(seen["fighter"] == "Strike" and seen["bomber"] == "Strike" and seen["interceptor"] == "Intercept", "fighters strike, interceptors screen")
	var carrier := _ship(&"c", {&"drone_rack": &"repair_drone_rack"})
	var wing := AirWing.for_ship(carrier)
	for c in wing.crafts:
		assert_true(c.directive == CraftAI.default_directive(c.config), "%s starts on its default" % c.label)
		if c.config.cannon != null:
			assert_true(c.priority == CraftAI.WEAK_SPOT, "%s aims at weak spots" % c.label)


func test_weak_spots_and_coming_home() -> void:
	var target := _ship(&"t")
	var worst: ShipSystems.EquipmentState = null
	for e in target.systems.equipment:
		if e.def.is_external():
			worst = e
	worst.hp = worst.max_hp * 0.2
	var aim := CraftAI.aim_point(target, CraftAI.WEAK_SPOT)
	assert_true(aim.is_equal_approx(target.position + target.orientation * worst.body_position), "the most damaged exposed system (%s)" % worst.id)
	# Coming home: the hull earlier, and the propellant for the trip.
	var wasp: ShipConfig = load("res://data/craft/wasp_fighter.tres")
	var f := ShipState.create(&"f", "f", wasp)
	f.hull_damage = wasp.hull_hp * 0.55
	print("    measured: Wasp %.0f hull points; at %d %% hull — \"%s\"" % [wasp.hull_hp, roundi(f.hull_fraction() * 100.0),
		CraftAI.disengage_reason(f, CraftAI.Risk.BALANCED)])
	assert_true(wasp.hull_hp >= 80.0 and CraftAI.disengage_reason(f, CraftAI.Risk.BALANCED).begins_with("hull"), "twice the hull; home at half")
	var g := ShipState.create(&"g", "g", wasp)
	g.propellant_kg = wasp.propellant_capacity_kg * 0.3
	var near := CraftAI.disengage_reason(g, CraftAI.Risk.BALANCED, 50.0)
	var far := CraftAI.disengage_reason(g, CraftAI.Risk.BALANCED, 600.0)
	print("    measured: 30 %% propellant — 50 m/s home: \"%s\"; 600 m/s home: \"%s\"" % [near, far])
	assert_true(near == "" and far == "propellant for the trip home", "it turns back while it can still make it")


func test_three_laser_tiers() -> void:
	var eq := _catalog().equipment
	var tiers := []
	for id: StringName in [&"fibre_laser_turret", &"laser_turret", &"free_electron_laser_turret"]:
		var def: EquipmentDefinition = eq[id]
		assert_true(def.validate().is_empty() and def.cannon.is_beam(), "%s is a laser" % id)
		tiers.append([def.display_name, def.cannon.penetration_mm, def.cannon.beam_range_m, def.power_kw])
	print("    measured: %s" % [tiers])
	assert_true(tiers[0][1] < tiers[1][1] and tiers[1][1] < tiers[2][1] and tiers[0][2] < tiers[2][2], "light, medium, heavy")
	for f in ["fighter_laser", "drone_laser"]:
		var gun: KineticCannonConfig = load("res://data/weapons/%s.tres" % f)
		assert_true(gun.display_name.begins_with("Yb-fibre") and gun.penetration_mm <= tiers[0][1], "craft carry the light tier (%s)" % gun.display_name)


func test_flares_one_at_a_time_with_trails() -> void:
	var world := WorldSimulation.new(DT)
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var r := RandomNumberGenerator.new()
	EnemyFactory._fit_launcher(bp, _catalog(), &"flare_launcher", r)
	EnemyFactory._fit_launcher(bp, _catalog(), &"flare_launcher", r)
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var s := ShipState.create(&"s", "s", stats.to_ship_config("s"))
	s.attach_systems(ShipSystems.create(bp, grid, stats, s.config))
	world.add_ship(s)
	world.launch_decoys(&"s", 4)
	var times := []
	var owners := {}
	var t := 0.0
	var seen := 0
	while t < 2.0:
		if world.decoys.size() > seen:
			times.append(snappedf(t, 0.01))
			seen = world.decoys.size()
		world.step()
		t += DT
	for d in world.decoys:
		owners[(d.position as Vector3).snapped(Vector3.ONE * 2.0)] = true
	print("    measured: 4 flares out at %s s, from %d places on the hull" % [times, owners.size()])
	assert_true(times.size() == 4 and times[3] - times[0] >= 3 * WorldSimulation.FLARE_INTERVAL_S - 0.02, "one at a time, %.2f s apart" % WorldSimulation.FLARE_INTERVAL_S)
	var view := DecoyView.new()
	view._ready()
	for k in 10:
		view.sync(world.decoys, Vector3.ZERO, Vector3(0, 0, 50), k * 0.1)
	var trail := view._trail_mesh.multimesh.visible_instance_count
	view.sync(world.decoys, Vector3.ZERO, Vector3(0, 0, 50), 10.0)
	print("    measured: trail sparks %d after 1 s; %d after 10 s" % [trail, view._trail_mesh.multimesh.visible_instance_count - world.decoys.size()])
	assert_true(trail >= 10, "a trail behind each flare")
	view.free()


func test_battle_stations_shut_doors_and_spread_the_crew() -> void:
	# The destroyer: its corridors, deck over deck, are one space.
	var destroyer := "res://data/blueprints/destroyer_mk1.json"
	var s := _ship(&"s", {}, destroyer).systems
	var pair := []
	for a: int in s.grid.open_rooms:
		if not (s.grid.open_rooms[a] as Array).is_empty():
			pair = [a, (s.grid.open_rooms[a] as Array)[0]]
			break
	assert_true(not pair.is_empty(), "two rooms open into each other")
	if pair.is_empty():
		return
	s.suited = true
	s.breach_room(pair[0])
	assert_true(not s.rooms[pair[0]].pressurized and s.rooms[pair[1]].pressurized, "at battle stations the door between them holds")
	var fresh := _ship(&"f", {}, destroyer).systems
	fresh.breach_room(pair[0])
	assert_true(not fresh.rooms[pair[1]].pressurized, "without it, both vent (as before)")
	# Spread: rooms with systems get a hand each.
	var t := _ship(&"t").systems
	var empty_before := _unmanned(t)
	var moved := t.spread_crew(true)
	print("    measured: %d rooms with systems and nobody in them; %d hands moved; %d left empty" % [empty_before, moved, _unmanned(t)])
	assert_true(moved > 0 and _unmanned(t) < empty_before, "the crew spread out")
	var back := t.spread_crew(false)
	assert_true(back == moved, "and go back at stand-down (%d)" % back)


func _unmanned(s: ShipSystems) -> int:
	var manned := {}
	for m in s.crew.members:
		if m.fit():
			manned[m.location] = true
	var rooms := {}
	for e in s.equipment:
		if not e.def.is_external():
			var r: int = s.grid.room_at.get(s.blueprint.equipment[e.index].cell, -1)
			if r >= 0 and not manned.has(r):
				rooms[r] = true
	return rooms.size()
