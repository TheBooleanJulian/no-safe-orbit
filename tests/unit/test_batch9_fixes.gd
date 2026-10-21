extends TestCase
## Measures: play-test batch 9, part 1 — the escort's courier is on our
## side, so our point defence leaves it alone (unaligned, it was engaged);
## launchers show a white missile nose per loaded tube, fewer as they fire;
## heavy RCS blocks come armoured; artifacts show their orbit once surveyed
## and question marks before.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _frigate() -> ShipState:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config("me")
	var s := ShipState.create(&"me", "me", cfg, Vector3.ZERO)
	s.side = &"player"
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


## Point-defence rounds fired at `courier` over `seconds`, with it 400 m off.
func _pd_on(courier: ShipState, seconds: float) -> int:
	var world := WorldSimulation.new(DT)
	var me := _frigate()
	world.add_ship(me)
	world.add_ship(courier)
	var fired := 0
	for i in roundi(seconds / DT):
		world.step()
		for k in me.pd_targets.size():
			if me.pd_targets[k] == String(courier.id):
				fired += 1
	return fired


func test_point_defence_spares_the_escorted_courier() -> void:
	var ours := MissionChain.courier_ship(&"courier", Vector3(300, 60, -400), Vector3.ZERO, Quaternion.IDENTITY)
	var unaligned := ShipState.create(&"courier", "COURIER", MissionChain.courier_config(), Vector3(300, 60, -400))
	var before := _pd_on(unaligned, 5.0)
	var after := _pd_on(ours, 5.0)
	print("    measured: PD ticks on the courier in 5 s — unaligned %d (the bug), on our side %d; its side %s" % [before, after, ours.side])
	assert_true(before > 0, "unaligned, point defence took it for hostile craft (the play-test report)")
	assert_true(ours.side == &"player" and after == 0 and ours.hull_damage == 0.0, "on our side: left alone")


func test_launchers_show_the_missiles_left() -> void:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	EnemyFactory._fit_launcher(bp, _catalog(), &"missile_rack", RandomNumberGenerator.new())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config("m"))
	var view := ShipView.new()
	view.blueprint = bp
	view.grid = grid
	view.stats = stats
	view._ready()
	var rack: ShipSystems.EquipmentState = null
	for e in sys.equipment:
		if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER:
			rack = e
	assert_true(rack != null and view._missile_cones.has(rack.id), "the rack has its missile cones")
	if rack == null or not view._missile_cones.has(rack.id):
		view.free()
		return
	var cones: Array = view._missile_cones[rack.id]
	var shown := func() -> int: return cones.filter(func(c: Node3D) -> bool: return c.visible).size()
	view._show_damage(sys)
	var full: int = shown.call()
	sys.missiles_used[rack.id] = rack.def.missile_capacity / 2
	view._show_damage(sys)
	var half: int = shown.call()
	sys.missiles_used[rack.id] = rack.def.missile_capacity
	view._show_damage(sys)
	var empty: int = shown.call()
	print("    measured: %d tubes — full %d noses, half fired %d, empty %d; rack colour %s" % [cones.size(), full, half, empty, rack.def.color])
	assert_true(full == cones.size() and half == cones.size() / 2 and empty == 0, "a nose per loaded tube")
	assert_true(rack.def.color.r > 0.7 and rack.def.color.g < 0.3, "the missile rack is red")
	var pod: EquipmentDefinition = _catalog().equipment[&"saturation_pod"]
	assert_true(pod.color.g > 0.6 and pod.color.r < 0.4, "the saturation pod is green")
	view.free()


func test_heavy_rcs_blocks_come_armoured() -> void:
	var light: EquipmentDefinition = _catalog().equipment[&"rcs_block"]
	var heavy: EquipmentDefinition = _catalog().equipment[&"rcs_block_heavy"]
	print("    measured: RCS %.0f hp / %.0f mm; heavy %.0f hp / %.0f mm" % [light.max_hit_points(), light.shielding_mm(), heavy.max_hit_points(), heavy.shielding_mm()])
	assert_true(heavy.max_hit_points() >= 3.0 * light.max_hit_points() and heavy.shielding_mm() >= 40.0, "armoured: three times the hit points, 40 mm")


func test_artifacts_show_their_orbit_once_surveyed() -> void:
	var iss := Artifact.by_id("iss")
	var roadster := Artifact.by_id("roadster")
	var voyager := Artifact.by_id("voyager1")
	print("    measured: %s | %s | %s | before: %s" % [iss.orbit_summary(), roadster.orbit_summary(), voyager.orbit_summary(), iss.orbit_unknown()])
	assert_true(iss.orbit_summary().ends_with("Earth orbit") and iss.orbit_summary().contains("51.") and iss.orbit_summary().contains("km"), "the ISS: km, ~51.6°, Earth orbit")
	assert_true(roadster.orbit_summary().begins_with("1.66 × 0.99 AU"), "the Roadster: 1.66 × 0.99 AU about the Sun")
	assert_true(voyager.orbit_summary().begins_with("escaping"), "Voyager 1 is escaping")
	assert_true(iss.orbit_unknown() == "??? × ??? km · ???° incl · Earth orbit" and roadster.orbit_unknown().contains("??? AU"), "unknown until surveyed")
