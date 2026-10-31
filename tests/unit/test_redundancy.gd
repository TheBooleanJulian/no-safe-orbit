extends TestCase
## Measures: backup routes (2026-10-31) — the power bus and coolant loops
## are looped round every hull module the hull lets them be, so one wrecked
## block cuts nothing off; a reactor or distribution unit joins the conduit
## run to any of its cells, and a big part draws through any face it covers.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _systems(bp: ShipBlueprint) -> ShipSystems:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	return ShipSystems.create(bp, grid, stats, stats.to_ship_config("x"))


## [worst systems unpowered elsewhere by one wrecked module, where] over the
## modules that hold no reactor or distribution unit and aren't truss (a boom
## is one module thick: nothing goes round it).
func _worst_cut(bp: ShipBlueprint) -> Array:
	var sys := _systems(bp)
	var grid := sys.grid
	sys.solve_power()
	var powered := {}
	for e in sys.equipment:
		if e.powered:
			powered[e.id] = true
	var source := {}
	for e in sys.equipment:
		if e.def.kind in [EquipmentDefinition.Kind.REACTOR, EquipmentDefinition.Kind.POWER_DISTRIBUTION]:
			for c in grid.equipment_cells(e.index):
				source[grid.module_at.get(c, -1)] = true
	var worst := [0, ""]
	for i in sys.modules.size():
		if source.has(i) or not (grid.catalog.hull[bp.modules[i].def_id] as HullModuleDefinition).interior:
			continue
		var cells := {}
		for c in grid.module_cells(i):
			cells[c] = true
		var keep: float = sys.modules[i].structure
		sys.modules[i].structure = 0.0
		sys.solve_power()
		var lost := PackedStringArray()
		for e in sys.equipment:
			var on: Array = grid.external_cells(e.index) if e.def.is_external() else grid.equipment_cells(e.index)
			if powered.has(e.id) and not e.powered and not on.any(func(c: Vector3i) -> bool: return cells.has(c)):
				lost.append(e.id)
		if lost.size() > int(worst[0]):
			worst = [lost.size(), "%s at %s: %s" % [bp.modules[i].def_id, bp.modules[i].position, lost]]
		sys.modules[i].structure = keep
	sys.solve_power()
	return worst


func test_no_wrecked_block_blacks_out_a_roster_hull() -> void:
	for path in BlueprintIO.list_templates():
		var bp := BlueprintIO.load_file(path, PackedStringArray())
		var worst := _worst_cut(bp)
		assert_true(int(worst[0]) == 0, "%s: one wrecked block unpowers nothing elsewhere (%s)" % [bp.name, worst[1]])


func test_auto_route_loops_round_the_blocks() -> void:
	# A design from before the loops: its conduit is the old shortest-path
	# tree. Auto-routed again, it gains a way round every block.
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var before := _worst_cut(bp)
	var cells := bp.bus.size()
	var ed := ShipEditor.new(bp, _catalog())
	ed.auto_route_bus()
	ed.auto_route_coolant()
	var after := _worst_cut(ed.blueprint)
	print("    measured: worst block cuts %d systems on the old tree (%s), %d re-routed (%d → %d conduit cells)" % [before[0], before[1], after[0],
		cells, ed.blueprint.bus.size()])
	assert_true(int(before[0]) > 0 and int(after[0]) == 0, "the old tree had a weak block; the looped network has none")
	assert_true(ShipValidator.validate(ed.blueprint, _catalog()).errors().is_empty(), "still a valid design")


func test_a_big_part_draws_through_any_face() -> void:
	var bp := BlueprintIO.load_file("res://data/blueprints/destroyer_mk1.json", PackedStringArray())
	var sys := _systems(bp)
	var engine: ShipSystems.EquipmentState
	for e in sys.equipment:
		if e.def.id == &"capital_main_engine":
			engine = e
	sys.solve_power()
	assert_true(engine != null and engine.powered, "the destroyer's capital engine is powered")
	var anchor := ShipBlueprint.cell_key(bp.equipment[engine.index].cell)
	var on_bus := sys.grid.external_cells(engine.index).filter(func(c: Vector3i) -> bool: return bp.bus.has(ShipBlueprint.cell_key(c)))
	sys.bus_cut[anchor] = true
	sys.solve_power()
	assert_true(on_bus.size() > 1 and engine.powered, "the conduit under its anchor cut: it draws through another of its %d faces on the bus" % on_bus.size())


func test_a_reactor_joins_the_conduit_on_its_cells() -> void:
	# The frigate's reactor (2 × 2) with the conduit cut down to two pieces
	# that touch it on different cells: one network, both fed.
	var bp := BlueprintIO.load_file("res://data/blueprints/frigate_mk1.json", PackedStringArray())
	var sys := _systems(bp)
	var reactor: ShipSystems.EquipmentState
	for e in sys.equipment:
		if e.def.kind == EquipmentDefinition.Kind.REACTOR:
			reactor = e
	var cells := sys.grid.equipment_cells(reactor.index).filter(func(c: Vector3i) -> bool: return bp.bus.has(ShipBlueprint.cell_key(c)))
	assert_true(cells.size() >= 2, "the conduit runs to %d of its cells" % cells.size())
	sys.solve_power()
	var nets := {}
	for c in cells:
		nets[sys.bus_network.get(ShipBlueprint.cell_key(c), -1)] = true
	assert_true(nets.size() == 1 and not nets.has(-1), "all of them one network")
