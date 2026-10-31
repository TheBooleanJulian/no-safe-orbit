extends TestCase
## Measures: the fourth play-test batch — M fires one launch from each
## relevant pod (volleys and their modes), cheaper restocking, automation
## never firing at wrecks, incoming rounds always drawn however many of our
## own are out, slope armour plates lying on the slope (contiguous on a
## long wedge, trimmed at the ridge), the nuclear burst's bigger, longer
## animation.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _armed(launchers: Array) -> ShipBlueprint:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var rng := RandomNumberGenerator.new()
	for id: StringName in launchers:
		EnemyFactory._fit_launcher(bp, _catalog(), id, rng)
	return bp


func _ship(id: StringName, bp: ShipBlueprint, pos: Vector3 = Vector3.ZERO) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _duel(launchers: Array) -> WorldSimulation:
	var world := WorldSimulation.new(DT)
	world.add_ship(_ship(&"a", _armed(launchers)))
	world.add_ship(_ship(&"b", BlueprintIO.load_file("res://tests/fixtures/cutter_mk1.json", PackedStringArray()), Vector3(0, 0, -6000)))
	return world


## Run a volley to completion; the warheads it launched.
func _fire(world: WorldSimulation, s: MissileSalvo) -> Array[int]:
	var before := world.missiles.size()
	var t := 0.0
	while not s.done() and t < 10.0:
		s.step(world)
		world.step()
		t += DT
	var out: Array[int] = []
	for m in world.missiles.slice(before):
		out.append(m.missile.warhead)
	return out


func test_m_fires_one_launch_from_each_relevant_pod() -> void:
	var world := _duel([&"missile_rack", &"emp_launcher", &"saturation_pod"])
	var sys := world.get_ship(&"a").systems
	var all := MissileSalvo.volley(&"a", &"b", MissileSalvo.Mode.ALL, [], sys)
	assert_true(all.volley_ids.size() == 3 and all.volley_missiles(sys) == 10, "ALL: three pods, 1 + 1 + a swarm of 8 (%d pods, %d missiles)" % [
		all.volley_ids.size(), all.volley_missiles(sys)])
	var fired := _fire(world, all)
	print("    measured: one press launched %d (rack 11/12, EMP 5/6, pod 40/48 left: %d, %d, %d)" % [fired.size(),
		sys.missiles_of(MissileConfig.Warhead.ANTI_SHIP) - 40, sys.missiles_of(MissileConfig.Warhead.EMP), 40])
	assert_true(fired.size() == 10, "one press: 10 missiles, not the 66 aboard (%d)" % fired.size())
	assert_true(sys.missiles_of(MissileConfig.Warhead.EMP) == 5 and sys.missiles_of(MissileConfig.Warhead.ANTI_SHIP) == 11 + 40,
		"each pod gave one launch (EMP %d left, conventional %d left)" % [sys.missiles_of(MissileConfig.Warhead.EMP), sys.missiles_of(MissileConfig.Warhead.ANTI_SHIP)])
	var conv := MissileSalvo.volley(&"a", &"b", MissileSalvo.Mode.CONVENTIONAL, [], sys)
	var w := _fire(world, conv)
	assert_true(w.size() == 9 and not w.has(MissileConfig.Warhead.EMP), "CONVENTIONAL: the rack and the pod, not the EMP launcher (%s)" % [w])


func test_sequence_presses_walk_the_order() -> void:
	var world := _duel([&"missile_rack", &"emp_launcher"])
	var sys := world.get_ship(&"a").systems
	var order := [MissileConfig.Warhead.EMP, MissileConfig.Warhead.ANTI_SHIP, MissileConfig.Warhead.NUCLEAR]
	var seen := []
	var index := 0
	for press in 3:
		var s := MissileSalvo.volley(&"a", &"b", MissileSalvo.Mode.SEQUENCE, order, sys, index)
		index = s.next_sequence_index
		seen.append(_fire(world, s))
	assert_true(seen == [[MissileConfig.Warhead.EMP], [MissileConfig.Warhead.ANTI_SHIP], [MissileConfig.Warhead.EMP]],
		"EMP, then conventional, then (no nuclear aboard) EMP again: %s" % [seen])


func test_restocking_is_cheap() -> void:
	var eq := _catalog().equipment
	var rack: EquipmentDefinition = eq[&"missile_rack"]
	var nuke: EquipmentDefinition = eq[&"nuclear_launcher"]
	var pod: EquipmentDefinition = eq[&"saturation_pod"]
	var emp: EquipmentDefinition = eq[&"emp_launcher"]
	var costs := [rack.missile_capacity * rack.missile.unit_credits, emp.missile_capacity * emp.missile.unit_credits,
		nuke.missile_capacity * nuke.missile.unit_credits, pod.missile_capacity * pod.missile.unit_credits]
	print("    measured: refills — rack %d cr, EMP %d cr, nuclear %d cr, saturation pod %d cr" % costs)
	assert_true(costs.max() <= 100, "every refill is under a mission's reward (≤ 100 cr; %s)" % [costs])


func test_automation_never_fires_at_a_wreck() -> void:
	var p := ShipPolicy.preset("Aggressive")
	p.autofire_enabled = true
	assert_true(p.autofire(true, true, 0.0, true), "a live hostile on the solution: fire")
	assert_true(not p.autofire(true, true, 0.0, false), "a wreck: hold")
	assert_true(not p.salvo_due(true, 1.0, 5000.0, true, 100.0, 0.0, false), "no auto-salvo at a wreck")
	assert_true(p.trigger(true, true, 0.0, false), "the player's own trigger still fires")
	var live := _ship(&"live", _armed([]))
	var wreck := _ship(&"wreck", _armed([]))
	wreck.derelict = true
	var beaten := _ship(&"beaten", _armed([]))
	for e in beaten.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.REACTOR or e.def.kind == EquipmentDefinition.Kind.MAIN_ENGINE:
			e.hp = 0.0
	beaten.systems.invalidate()
	assert_true(Main.is_fightable(live) and not Main.is_fightable(wreck), "a derelict is not fightable")
	assert_true(beaten.systems.disabled_reason() == "" or not Main.is_fightable(beaten),
		"a disabled ship is not fightable (%s)" % beaten.systems.disabled_reason())


func test_incoming_rounds_are_drawn_before_our_own() -> void:
	var view := ProjectileView.new()
	view._ready()
	var rounds: Array[ProjectileState] = []
	for i in ProjectileView.MAX_TRACERS + 500:
		var r := ProjectileState.new()
		r.shooter_id = &"player"
		r.position = Vector3(float(i % 50) * 3.0, 20.0, -float(i / 50) * 3.0)
		r.prev_position = r.position
		r.velocity = Vector3(0, 0, -900)
		rounds.append(r)
	var incoming := ProjectileState.new()
	incoming.shooter_id = &"target_01"
	incoming.position = Vector3(500, -40, 300)
	incoming.prev_position = incoming.position
	incoming.velocity = Vector3(0, 0, 3000)
	rounds.append(incoming)
	var order := ProjectileView.draw_order(rounds, {&"player": true})
	assert_true(order.has(incoming) and order.size() == ProjectileView.MAX_TRACERS,
		"the enemy round is drawn although %d of ours are out (%d drawn)" % [rounds.size() - 1, order.size()])
	assert_true(not ProjectileView.draw_order(rounds, {}).has(incoming), "(without the own-side list it would have been cut)")
	view.sync(rounds, 1.0, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, {&"player": true})
	assert_true(view.drawn == ProjectileView.MAX_TRACERS, "the cap holds (%d)" % view.drawn)
	view._sparks.free()
	view.free()


func test_slope_plates_lie_on_the_slope() -> void:
	var cat := _catalog()
	var bp := ShipBlueprint.new()
	bp.add_module(&"hull_block", Vector3i(0, 0, 2))
	bp.add_module(&"wedge_short", Vector3i(0, 0, 1))
	bp.add_module(&"wedge_long", Vector3i(0, 0, 4), 2)
	var grid := ShipGrid.build(bp, cat)
	for cell: Vector3i in grid.module_at:
		for face in grid.plateable_faces(cell):
			bp.armor[ShipBlueprint.plate_key(cell, face)] = 80.0
	grid = ShipGrid.build(bp, cat)
	var c := ShipGrid.CELL_SIZE_M
	var model := ShipModelBuilder.build(bp, grid, Vector3.ZERO)
	var long_plates: Array[MeshInstance3D] = []
	var worst := 0.0
	for key: String in model.plates:
		var cf := ShipBlueprint.parse_plate_key(key)
		var cell: Vector3i = cf[0]
		if not grid.is_wedge_cell(cell) or not grid.slope_faces(cell).has(cf[1] as StringName):
			continue
		var mi: int = grid.module_at[cell]
		var n := grid.wedge_normal(mi)
		var center := (Vector3(bp.modules[mi].position) + Vector3(grid.module_size(mi)) * 0.5) * c
		var node: MeshInstance3D = model.plates[key]
		var depth := (node.mesh as BoxMesh).size.y
		# The plate's centre is half its thickness above the slope plane.
		worst = maxf(worst, absf((node.position - center).dot(n) - depth * 0.5))
		if bp.modules[mi].def_id == &"wedge_long":
			long_plates.append(node)
	print("    measured: slope plates %.4f m off the slope at worst" % worst)
	assert_true(worst < 0.01, "every slope plate lies on its slope (worst %.3f m off)" % worst)
	assert_true(long_plates.size() == 2, "the long wedge has two slope plates")
	# Where the long wedge's two cells meet on the slope, their panels butt
	# with a slim seam (like flat plates), neither overlapping nor apart.
	var dist := long_plates[0].position.distance_to(long_plates[1].position)
	var half_lengths := ((long_plates[0].mesh as BoxMesh).size.z + (long_plates[1].mesh as BoxMesh).size.z) * 0.5
	var seam := dist - half_lengths
	print("    measured: long-wedge seam %.3f m" % seam)
	assert_true(seam > 0.0 and seam < 0.2, "the long wedge's panels meet with a slim seam (%.3f m)" % seam)
	model.root.free()


func test_the_nuclear_burst_is_bigger_and_longer() -> void:
	var reactor := ReactorExplosion.new()
	reactor.setup(&"x", Vector3.ZERO, 160.0, 1)
	var nuke := ReactorExplosion.new()
	nuke.setup(&"x", Vector3.ZERO, 160.0, 1, true)
	var world := WorldSimulation.new(DT)
	var t := 0.0
	var reach := 0.0
	while not nuke.finished() and t < 20.0:
		nuke.step(world, 1.0, Vector3.ZERO, 0.05)
		reactor.step(world, 1.0, Vector3.ZERO, 0.05)
		for r in nuke._rings:
			if (r.node as Node3D).visible:
				reach = maxf(reach, (r.node as Node3D).scale.x)
		t += 0.05
	print("    measured: nuclear burst %.1f s, rings to %.0f m (radius 160 m)" % [t, reach])
	assert_true(reactor.finished() and t >= 7.9, "the nuclear burst outlasts a reactor's (%.1f s)" % t)
	assert_true(reach >= 1400.0, "its shockwave reaches ~1.6 km (%.0f m)" % reach)
	assert_true(nuke._lobes.size() == ReactorExplosion.NUKE_LOBES and nuke._rings.size() == 3, "more fireball lobes, three rings")
	reactor.free()
	nuke.free()
