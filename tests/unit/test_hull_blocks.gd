extends TestCase
## Measures: hull building blocks and angled armour — wedge solids and slope
## normals under rotation and flipping; a level shot meets a 45° slope as
## √2 × the plate and a long (26.6°) slope deflects it; painted plates add
## mass, cost refits, wear and persist; editing carries plates with their
## module; the block-built template flies and validates.

const CELL := ShipGrid.CELL_SIZE_M


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


## A lone column of `wedge` (or a block) in front of a 2×2 block, so it is
## attached; returns the blueprint.
func _test_hull(front_def: StringName, flip: bool = false, rotation: int = 0) -> ShipBlueprint:
	var bp := ShipBlueprint.new()
	bp.name = "Test hull"
	bp.add_module(&"hull_block", Vector3i(0, 0, 2))
	bp.add_module(front_def, Vector3i(0, 0, 0), rotation, flip)
	return bp


func _systems(bp: ShipBlueprint) -> ShipSystems:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	return ShipSystems.create(bp, grid, stats, cfg)


func test_wedge_solid_and_slope_normal_follow_rotation_and_flip() -> void:
	var grid := ShipGrid.build(_test_hull(&"wedge_short"), _catalog())
	var w := 1  # the wedge's module index
	assert_true(grid.is_wedge(w) and grid.is_wedge_cell(Vector3i(0, 0, 0)), "a wedge cell")
	assert_vec_near(grid.wedge_normal(w), Vector3(0, 1, -1).normalized(), 1e-6, "45° slope faces up and forward")
	assert_true(not grid.wedge_contains(w, Vector3(0.5, 0.9, 0.1)), "fore-top corner is empty")
	assert_true(grid.wedge_contains(w, Vector3(0.5, 0.1, 0.9)), "aft-bottom corner is solid")
	var flipped := ShipGrid.build(_test_hull(&"wedge_short", true), _catalog())
	assert_vec_near(flipped.wedge_normal(w), Vector3(0, -1, -1).normalized(), 1e-6, "flipped: faces down and forward")
	assert_true(flipped.slope_faces(Vector3i(0, 0, 0)) == [&"fore", &"ventral"], "flipped slope replaces fore and underside")
	var turned := ShipGrid.build(_test_hull(&"wedge_short", false, 1), _catalog())
	assert_vec_near(turned.wedge_normal(w), Vector3(-1, 1, 0).normalized(), 1e-6, "a quarter turn: up and to port")
	var long := ShipGrid.build(_test_hull(&"wedge_long", false, 0), _catalog())
	assert_vec_near(long.wedge_normal(1), Vector3(0, 2, -1).normalized(), 1e-6, "1×2 wedge: a 26.6° slope")


func test_a_level_shot_meets_the_slope_at_its_angle() -> void:
	# 40 mm plate on a 45° prow: skin + plate count √2 thicker against a level shot.
	var bp := _test_hull(&"wedge_short")
	bp.armor[ShipBlueprint.plate_key(Vector3i(0, 0, 0), &"dorsal")] = 40
	var s := _systems(bp)
	var com := s.stats.center_of_mass_m
	var from := Vector3(0.5 * CELL, 0.5 * CELL, -10.0) - com
	var to := Vector3(0.5 * CELL, 0.5 * CELL, 10.0) - com
	var t := Penetration.first_hull_entry(s, from, to)
	assert_true(t > 0.0, "hits the slope")
	var hit := from.lerp(to, t)
	assert_near((hit + com).z / CELL, 0.5, 0.02, "enters where the slope crosses the shot's height (half way into the cell)")
	var skin := s.modules[1].armor_mm
	var needed := (skin + 40.0) * sqrt(2.0)
	var stopped := Penetration.apply(s, hit, Vector3(0, 0, 1), needed - 5.0)
	assert_true(not stopped.penetrated and " ".join(stopped.lines).contains("45°"),
		"%.0f mm is stopped by %.0f mm at 45° (%.0f effective)\n%s" % [needed - 5.0, skin + 40.0, needed, "\n".join(stopped.lines)])
	assert_vec_near(stopped.entry_normal_body, Vector3(0, 1, -1).normalized(), 1e-4, "the entry normal is the slope's")
	var s2 := _systems(bp)
	var through := Penetration.apply(s2, hit, Vector3(0, 0, 1), needed + 10.0)
	assert_true(through.penetrated, "%.0f mm gets through" % (needed + 10.0))
	# The same round on a 26.6° slope (63.4° incidence) is deflected.
	var long := _test_hull(&"wedge_long")
	long.armor[ShipBlueprint.plate_key(Vector3i(0, 0, 0), &"dorsal")] = 40
	var s3 := _systems(long)
	var com3 := s3.stats.center_of_mass_m
	var from3 := Vector3(0.5 * CELL, 0.3 * CELL, -10.0) - com3
	var to3 := Vector3(0.5 * CELL, 0.3 * CELL, 20.0) - com3
	var hit3 := from3.lerp(to3, Penetration.first_hull_entry(s3, from3, to3))
	var r3 := Penetration.apply(s3, hit3, Vector3(0, 0, 1), needed - 5.0)
	assert_true(r3.ricochet, "a long, shallow slope ricochets it:\n%s" % "\n".join(r3.lines))


func test_painted_plates_add_mass_cost_and_persist() -> void:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	var ed := ShipEditor.new(bp, _catalog())
	var mass := ed.stats.mass_kg
	var plates := ed.blueprint.armor.size()
	# Thick plates down the starboard side of the pods, sides only.
	var n := ed.paint_armor(0, Rect2i(7, 6, 1, 6), ShipBlueprint.PLATE_THICK_MM, ShipEditor.PlateFaces.SIDES)
	assert_true(n > 0 and ed.blueprint.armor.size() == plates + n, "%d plates painted" % n)
	assert_near(ed.stats.mass_kg - mass, n * ShipStats.plate_mass(80.0), 1.0, "each 80 mm plate adds %.0f kg" % ShipStats.plate_mass(80.0))
	assert_true(ed.blueprint.armor.keys().all(func(k: String) -> bool: return not (k.ends_with("dorsal") and k.begins_with("7,0"))), "sides only: no tops")
	# A refit pays for them.
	var vessel := ShipInstance.fresh(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors))
	var jobs := ServiceYard.refit_jobs(vessel, ed.blueprint, _catalog())
	assert_true(jobs.size() == 1 and jobs[0].cost == n * ServiceYard.plate_cost(80.0), "refit: %d plates for %d parts" % [n, n * ServiceYard.plate_cost(80.0)])
	# Saved and loaded intact (schema 2).
	var copy := BlueprintIO.from_json(BlueprintIO.to_json(ed.blueprint), errors)
	assert_true(copy != null and copy.armor == ed.blueprint.armor and copy.modules.any(func(m: ShipBlueprint.PlacedModule) -> bool: return m.flip),
		"plates and flipped wedges round-trip (%s)" % ", ".join(errors))
	# Moving a module carries its plates.
	var pod := ed.blueprint.modules.filter(func(m: ShipBlueprint.PlacedModule) -> bool: return m.position == Vector3i(6, 0, 6))[0] as ShipBlueprint.PlacedModule
	var before := ed.blueprint.armor.has(ShipBlueprint.plate_key(Vector3i(7, 0, 6), &"starboard"))
	ed.move(pod.id, Vector3i(0, 0, -1))
	assert_true(before and ed.blueprint.armor.has(ShipBlueprint.plate_key(Vector3i(7, 0, 5), &"starboard")), "the plate moved with its block")
	# Removing paints them off.
	var removed := ed.paint_armor(0, Rect2i(7, 0, 1, 20), 0, ShipEditor.PlateFaces.ALL)
	assert_true(removed > 0, "remove tool strips %d plates" % removed)


func test_worn_plates_are_remembered_and_replated_at_the_yard() -> void:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	var s := _systems(bp)
	var key := ShipBlueprint.plate_key(Vector3i(2, 2, 6), &"port")
	assert_true(s.plates.has(key), "the template has a belt plate on the port flank")
	var com := s.stats.center_of_mass_m
	Penetration.apply(s, Vector3(2.0 * CELL, 2.5 * CELL, 6.5 * CELL) - com, Vector3(1, 0, 0), 30.0)
	assert_true(s.plates[key] < 40.0, "a stopped round scuffs the plate (%.0f mm left)" % s.plates[key])
	var cond := s.condition()
	assert_true(cond.has("plates") and (cond.plates as Dictionary).has(key), "worn plates are in the saved condition")
	var s2 := _systems(bp)
	s2.apply_condition(cond)
	assert_near(s2.plates[key], s.plates[key], 1e-4, "and restored next sortie (mm)")
	var vessel := ShipInstance.fresh(bp)
	vessel.condition = cond
	var jobs := ServiceYard.repair_jobs(vessel, _catalog())
	assert_true(jobs.any(func(j: ServiceYard.Job) -> bool: return j.kind == &"plates"), "the yard offers to re-plate")


func test_the_block_built_template_flies() -> void:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	var catalog := _catalog()
	assert_true(bp.modules.all(func(m: ShipBlueprint.PlacedModule) -> bool: return not catalog.hull[m.def_id].legacy),
		"the template is built only from current blocks")
	assert_true(bp.modules.any(func(m: ShipBlueprint.PlacedModule) -> bool: return catalog.hull[m.def_id].is_wedge()), "it has sloped armour")
	var report := ShipValidator.validate(bp, catalog)
	assert_true(not report.has_errors(), "validates:\n%s" % report.summary())
	var pool := LootRoller.build_pool(catalog)
	assert_true(pool.all(func(d: LootRoller.Drop) -> bool: return d.kind != &"hull" or not catalog.hull[d.def_id].legacy), "legacy sections no longer drop")


func test_radiators_span_two_cells_and_fighters_launch_from_a_hangar() -> void:
	var errors := PackedStringArray()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	var catalog := _catalog()
	var grid := ShipGrid.build(bp, catalog)
	var rad := bp.equipment.find(bp.find("e42"))
	assert_true(grid.external_cells(rad).size() == 2, "a radiator panel spans two cells")
	# A second radiator overlapping its aft cell is refused.
	var clash := bp.duplicate_blueprint()
	clash.add_equipment(&"radiator", Vector3i(2, 2, 11), &"dorsal")
	assert_true(ShipValidator.validate(clash, catalog).has_code(&"equipment_overlap"), "overlapping spans are refused")
	# Turned, it runs across the ship.
	var turned := bp.duplicate_blueprint()
	var e := turned.add_equipment(&"radiator", Vector3i(3, 2, 6), &"dorsal", 1)
	var tg := ShipGrid.build(turned, catalog)
	assert_true(tg.external_cells(turned.equipment.find(e)) == [Vector3i(3, 2, 6), Vector3i(4, 2, 6)], "turned: across the ship")
	# The fighter lives in an internal bay; it leaves through the hangar's underside.
	var bay := bp.find("e51") as ShipBlueprint.PlacedEquipment
	assert_true(bay.def_id == &"fighter_bay" and not catalog.equipment[bay.def_id].is_external(), "the fighter bay is internal")
	var s := _systems(bp)
	var door := s.launch_door(s.equipment_by_id("e51"))
	assert_vec_near(door[1], Vector3.DOWN, 1e-6, "its door opens downwards")
	assert_true(not catalog.equipment[&"fighter_rack"].is_external() or catalog.equipment[&"fighter_rack"].legacy, "the old external rack is legacy")
