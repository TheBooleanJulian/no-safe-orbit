extends TestCase
## Measures: play-test batch 9, part 7 — effects and the opening range. A
## part an EMP has reset crackles with static until it recovers; holding B
## spools rings of light up around the hull; the berth has the docking hall
## behind it; the encounter's lead starts 4 km out; craft guns fire at half
## their old rate.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _view_and_systems() -> Array:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config("e"))
	var view := ShipView.new()
	view.blueprint = bp
	view.grid = grid
	view.stats = stats
	view._ready()
	return [view, sys]


func test_emp_static_until_recovery() -> void:
	var a := _view_and_systems()
	var view: ShipView = a[0]
	var sys: ShipSystems = a[1]
	view._show_emp(sys, 1.0)
	assert_true(view.emp_sparking.is_empty() and view._emp_mesh == null, "nothing reset: no static")
	var reset := sys.emp(1.0)
	view._show_emp(sys, 1.0)
	print("    measured: EMP at 1.0 — %d parts reset, %d crackling, %d arcs of static (the hull's too)" % [reset.size(), view.emp_sparking.size(), view.emp_arcs])
	assert_true(reset.size() > 0 and view.emp_sparking.size() == reset.size(), "every part reset crackles")
	assert_true(view._emp_mesh != null and view._emp_mesh.visible and view.emp_arcs >= reset.size() * ShipView.EMP_ARCS_PER_PART, "drawn")
	# Recovered: gone.
	for e in sys.equipment:
		e.disrupted_s = 0.0
	view._show_emp(sys, 1.0)
	assert_true(view.emp_sparking.is_empty() and not view._emp_mesh.visible, "recovered: the static stops")
	view.free()


func test_jump_spool_up() -> void:
	var view: ShipView = _view_and_systems()[0]
	view._update_spool(0.1)
	assert_true(view._spool == null, "not holding B: nothing")
	view.jump_spool = 0.1
	view._update_spool(0.1)
	var early := absf(view._spool_rings[0].position.z)
	var alpha_early := view._spool_mat.albedo_color.a
	view.jump_spool = 0.95
	view._update_spool(0.1)
	var late := absf(view._spool_rings[0].position.z)
	print("    measured: %d rings; the end ring %.1f m → %.1f m from the middle; glow %.2f → %.2f" % [
		view._spool_rings.size(), early, late, alpha_early, view._spool_mat.albedo_color.a])
	assert_true(view._spool.visible and view._spool_rings.size() == ShipView.SPOOL_RINGS, "rings round the hull")
	assert_true(late < early and view._spool_mat.albedo_color.a > alpha_early, "closing in and brightening")
	view.jump_spool = 0.0
	view._update_spool(0.1)
	assert_true(not view._spool.visible, "let go: gone")
	view.free()


func test_the_berth_has_the_hall_behind_it() -> void:
	var p := ShipPreview3D.new()
	p.berth = true
	p._ready()
	assert_true(p._env.background_mode == Environment.BG_COLOR, "before the berth: plain")
	p._build_berth(Vector3(10, 5, 30))
	var mat := p._env.sky.sky_material as ShaderMaterial if p._env.sky != null else null
	assert_true(p._env.background_mode == Environment.BG_SKY and mat != null and mat.shader == ShipPreview3D.INTERIOR_SKY, "the hall as the sky")
	assert_true(ShipPreview3D.INTERIOR_SKY.get_mode() == Shader.MODE_SKY, "a sky shader")
	p.free()


func test_the_lead_starts_further_out_and_craft_fire_slower() -> void:
	var nearest := INF
	for o: Vector3 in Main.CONTACT_OFFSETS:
		nearest = minf(nearest, o.length())
	var hornet: KineticCannonConfig = load("res://data/weapons/interceptor_gun.tres")
	var wasp: KineticCannonConfig = load("res://data/weapons/fighter_gun.tres")
	print("    measured: nearest contact starts %.1f km out; Hornet %.0f rpm, Wasp %.0f rpm" % [nearest / 1000.0, hornet.rate_of_fire_rpm, wasp.rate_of_fire_rpm])
	assert_true(nearest >= 4000.0, "the lead 4 km out, not 2.5")
	assert_true(nearest > CraftAI.ESCORT_ENGAGE_M * 1.5, "outside an escort's engage range at the start")
	assert_near(hornet.rate_of_fire_rpm, 300.0, 1e-6, "Hornet gun (rpm)")
	assert_near(wasp.rate_of_fire_rpm, 150.0, 1e-6, "Wasp gun (rpm)")
