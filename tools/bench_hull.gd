extends SceneTree
## Capital-ship spike (Milestone 10): how the construction and damage code
## scales to a very large hull. Builds a ~300-module hull — a 2×2-block
## slab, two decks, a bridge and rooms along its length, reactors, engines,
## RCS and guns — and times validation, compile (grid, stats, flight
## config, systems), a flight-config recompute and hit tests.
##   godot --headless --path . -s res://tools/bench_hull.gd
## Measurement only: it decides whether anything must change before capital
## ships, it doesn't build them.

const MODULES_WIDE := 5
const MODULES_LONG := 30
const DECKS := 2


func _initialize() -> void:
	var r := run()
	for line in r.lines:
		print(line)
	quit()


static func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0


## The hull, and {lines, modules, rooms, equipment, cells, timings (ms)}.
static func run() -> Dictionary:
	var catalog := ConstructionCatalog.default_catalog()
	var bp := ShipBlueprint.new()
	bp.name = "Spike hull"
	for d in DECKS:
		for x in MODULES_WIDE:
			for z in MODULES_LONG:
				bp.add_module(&"hull_block", Vector3i(x * 2, d, z * 2), 0)
	# A room per block on deck 0 (bridge forward, then quarters, reactors,
	# magazines, engine rooms aft), a corridor deck above.
	var roles := [&"crew_quarters", &"reactor_room", &"magazine", &"crew_quarters", &"cargo_hold"]
	for x in MODULES_WIDE:
		for z in MODULES_LONG:
			var def: StringName = &"bridge" if z == 0 and x == 2 else (&"engine_room" if z == MODULES_LONG - 1 else roles[(x + z) % roles.size()])
			bp.add_room(def, 0, Rect2i(x * 2, z * 2, 2, 2))
			bp.add_room(&"corridor", 1, Rect2i(x * 2, z * 2, 2, 2))
	for i in bp.rooms.size():
		var r := bp.rooms[i]
		if r.def_id == &"reactor_room":
			bp.add_equipment(&"compact_reactor", Vector3i(r.rect.position.x, 0, r.rect.position.y), &"", 0)
	for x in MODULES_WIDE * 2:
		bp.add_equipment(&"main_engine", Vector3i(x, 0, MODULES_LONG * 2 - 1), &"aft", 0)
		bp.add_equipment(&"autocannon", Vector3i(x, 1, 2), &"dorsal", 0)
	for z in range(0, MODULES_LONG * 2, 4):
		bp.add_equipment(&"rcs_block", Vector3i(0, 0, z), &"port", 0)
		bp.add_equipment(&"rcs_block", Vector3i(MODULES_WIDE * 2 - 1, 0, z), &"starboard", 0)
		bp.add_equipment(&"radiator", Vector3i(z % (MODULES_WIDE * 2), 1, z), &"dorsal", 0)
	var timings := {}
	var t0 := Time.get_ticks_usec()
	var grid := ShipGrid.build(bp, catalog)
	timings["grid"] = _ms(t0)
	t0 = Time.get_ticks_usec()
	var stats := ShipStats.compute(bp, grid)
	timings["stats"] = _ms(t0)
	t0 = Time.get_ticks_usec()
	var report := ShipValidator.validate(bp, catalog, grid, stats)
	timings["validate"] = _ms(t0)
	t0 = Time.get_ticks_usec()
	var cfg := stats.to_ship_config(bp.name)
	var sys := ShipSystems.create(bp, grid, stats, cfg)
	timings["systems"] = _ms(t0)
	t0 = Time.get_ticks_usec()
	sys.invalidate()
	sys.effective_config()
	timings["recompute"] = _ms(t0)
	var ship := ShipState.create(&"spike", "spike", cfg)
	ship.attach_systems(sys)
	# Hit tests: rounds down the long axis (worst case: the whole length).
	var shots := 200
	var length_m := MODULES_LONG * 2 * ShipGrid.CELL_SIZE_M
	t0 = Time.get_ticks_usec()
	for i in shots:
		var y := 1.0 + 0.01 * i
		var a := Vector3(4.5, y, -length_m) - stats.center_of_mass_m
		var b := Vector3(4.5, y, length_m * 2.0) - stats.center_of_mass_m
		HitTest.round_vs_ship(a, b, ship)
		Penetration.first_hull_entry(sys, a, b)
	timings["hit_test_each"] = _ms(t0) / shots
	t0 = Time.get_ticks_usec()
	var pen := Penetration.apply(sys, Vector3(4.5, 1.5, -1.0) - stats.center_of_mass_m, Vector3(0, 0, 1), 5000.0)
	timings["penetration_full_length"] = _ms(t0)
	t0 = Time.get_ticks_usec()
	sys.solve_power()
	timings["power_solve"] = _ms(t0)
	var lines := PackedStringArray([
		"bench_hull: %d modules, %d rooms, %d equipment, %d hull cells, %.0f t; validation %d errors / %d warnings" % [
			bp.modules.size(), bp.rooms.size(), bp.equipment.size(), grid.module_at.size(), stats.mass_kg / 1000.0,
			report.errors().size(), report.issues.size() - report.errors().size()],
		"  grid build        %8.1f ms" % timings.grid,
		"  stats             %8.1f ms" % timings.stats,
		"  validation        %8.1f ms" % timings.validate,
		"  systems create    %8.1f ms" % timings.systems,
		"  config recompute  %8.1f ms (after damage)" % timings.recompute,
		"  power solve       %8.1f ms" % timings.power_solve,
		"  hit test          %8.3f ms per round (box + hull walk, full length)" % timings.hit_test_each,
		"  penetration walk  %8.1f ms (5 m round down the whole hull, %d events)" % [timings.penetration_full_length, pen.events.size()],
	])
	return {"lines": lines, "modules": bp.modules.size(), "rooms": bp.rooms.size(), "equipment": bp.equipment.size(),
		"cells": grid.module_at.size(), "timings": timings}
