extends TestCase
## Measures: player-routed power — conduit networks join face to face and
## between decks; a system is powered only on a network with a reactor and
## a working distribution unit; cutting a conduit (by a hit) isolates what
## lies beyond it; cuts persist and are re-run at the yard; the editor lays,
## removes and auto-routes conduit and the validator flags unrouted systems.

const CELL := ShipGrid.CELL_SIZE_M


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _systems(bp: ShipBlueprint) -> ShipSystems:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	return ShipSystems.create(bp, grid, stats, stats.to_ship_config(bp.name))


func test_the_template_routes_power_to_everything() -> void:
	var bp := _template()
	assert_true(not bp.bus.is_empty(), "the template has a routed bus (%d cells)" % bp.bus.size())
	var report := ShipValidator.validate(bp, _catalog())
	assert_true(not report.has_code(&"power_unrouted") and not report.has_code(&"bus_no_distribution"), "nothing unrouted:\n%s" % report.summary())
	var s := _systems(bp)
	var dark := s.equipment.filter(func(e: ShipSystems.EquipmentState) -> bool: return not e.powered)
	assert_true(dark.is_empty(), "every system powered (dark: %s)" % ", ".join(dark.map(func(e: ShipSystems.EquipmentState) -> String: return e.id)))


func test_a_network_without_its_distribution_unit_feeds_nothing() -> void:
	var s := _systems(_template())
	var pdu: ShipSystems.EquipmentState = s.equipment.filter(func(e: ShipSystems.EquipmentState) -> bool:
		return e.def.kind == EquipmentDefinition.Kind.POWER_DISTRIBUTION)[0]
	s.damage_equipment(pdu, 1000.0)
	s.solve_power()
	assert_true(s.power_supply_kw == 0.0, "distribution unit destroyed: no supply (%.0f kW)" % s.power_supply_kw)
	assert_true(not s.equipment_by_id("e41").powered, "the gun goes dark")


func test_cutting_a_conduit_isolates_what_lies_beyond() -> void:
	var s := _systems(_template())
	var gun_cell: Vector3i = s.blueprint.find("e41").cell
	assert_true(s.blueprint.bus.has(ShipBlueprint.cell_key(gun_cell)), "the gun's mount cell carries conduit")
	assert_true(s.cut_bus(gun_cell), "the conduit there is cut")
	assert_true(not s.equipment_by_id("e41").powered, "the gun beyond the cut has no power")
	assert_true(s.equipment_by_id("e29").powered, "the engines elsewhere still do")
	var cond := s.condition()
	assert_true((cond.get("bus_cut", []) as Array).has(ShipBlueprint.cell_key(gun_cell)), "the cut is saved with the vessel")
	var s2 := _systems(_template())
	s2.apply_condition(cond)
	assert_true(not s2.equipment_by_id("e41").powered, "and still cut next sortie")
	var vessel := ShipInstance.fresh(_template())
	vessel.condition = cond
	var jobs := ServiceYard.repair_jobs(vessel, _catalog())
	var bus_jobs := jobs.filter(func(j: ServiceYard.Job) -> bool: return j.kind == &"bus")
	assert_true(bus_jobs.size() == 1 and bus_jobs[0].cost == 1, "the yard re-runs it for 1 spare part")
	var p := PlayerProfile.new(3)
	ServiceYard.perform(bus_jobs, vessel, p)
	assert_true(not vessel.condition.has("bus_cut"), "re-run: no cuts left")


func test_a_round_through_a_conduit_cuts_it() -> void:
	var s := _systems(_template())
	var com := s.stats.center_of_mass_m
	var gun_cell: Vector3i = s.blueprint.find("e41").cell
	# Straight down through the gun deck at the gun's cell, until a round
	# severs the conduit there (a chance per crossing).
	var top := (Vector3(gun_cell) + Vector3(0.5, 1.0, 0.5)) * CELL - com
	var rounds := 0
	while rounds < 40 and not s.bus_cut.has(ShipBlueprint.cell_key(gun_cell)):
		Penetration.apply(s, top, Vector3(0, -1, 0), 300.0)
		rounds += 1
	assert_true(s.bus_cut.has(ShipBlueprint.cell_key(gun_cell)) and rounds > 0, "a round cuts the gun's conduit (after %d)" % rounds)
	assert_true(not s.equipment_by_id("e41").powered, "and the gun loses power")


func test_editor_lays_removes_and_auto_routes_conduit() -> void:
	var ed := ShipEditor.new(_template(), _catalog())
	var all := ed.blueprint.bus.size()
	var removed := ed.paint_bus(2, Rect2i(0, 0, 20, 20), false)
	assert_true(removed > 0 and ed.report.has_code(&"power_unrouted"), "pulling deck 2's conduit unpowers the gun:\n%s" % ed.report.summary())
	var laid := ed.paint_bus(2, Rect2i(3, 4, 1, 1), true)
	assert_true(laid == 1, "lays one cell")
	assert_true(ed.paint_bus(2, Rect2i(20, 0, 1, 1), true) == 0, "no conduit outside the hull")
	var n := ed.auto_route_bus()
	assert_true(n > 0 and not ed.report.has_code(&"power_unrouted"), "auto-route reconnects everything (%d cells, was %d)" % [n, all])
	var copy := BlueprintIO.from_json(BlueprintIO.to_json(ed.blueprint), PackedStringArray())
	assert_true(copy.bus == ed.blueprint.bus, "the bus is saved and loaded")
	var vessel := ShipInstance.fresh(_template())
	vessel.blueprint.bus.clear()
	var jobs := ServiceYard.refit_jobs(vessel, ed.blueprint, _catalog())
	assert_true(jobs.any(func(j: ServiceYard.Job) -> bool: return j.subject == "bus"), "new conduit is paid for at refit")
