extends TestCase
## Measures: the refit-bay pass (2026-10-26) — parts sized by tier (light
## 1, medium 2, large 3 cells across, standing that far out), landing legs,
## a size benefit for every room (corridors: faster crew), windows cut
## through armour and the hull name over it, and the roster's legs and
## sloped skirts.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _frigate() -> ShipBlueprint:
	return BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())


func _codes(bp: ShipBlueprint) -> Array:
	return ShipValidator.validate(bp, _catalog()).errors().map(func(i: ShipValidator.Issue) -> StringName: return i.code)


func test_parts_are_sized_by_tier() -> void:
	var eq := _catalog().equipment
	for want: Array in [[&"autocannon", 1], [&"kinetic_cannon", 2], [&"railgun", 3], [&"fibre_laser_turret", 1], [&"laser_turret", 2],
			[&"free_electron_laser_turret", 3], [&"main_engine", 1], [&"main_engine_high_thrust", 2], [&"torch_drive", 3],
			[&"missile_rack", 1], [&"saturation_pod", 2]]:
		assert_true((eq[want[0]] as EquipmentDefinition).size_cells == want[1], "%s is %d across" % want)
	# A heavy gun on a free 2 × 2 patch: four faces, standing two out.
	var bp := _frigate()
	var e := bp.add_equipment(&"kinetic_cannon", Vector3i(4, 2, 6), &"dorsal")
	var grid := ShipGrid.build(bp, _catalog())
	var i := bp.equipment.find(e)
	assert_true(grid.external_cells(i).size() == 4 and grid.standing_cells(i).size() == 8, "its patch and the space it stands in")
	assert_true(_codes(bp).is_empty(), "it fits: %s" % [_codes(bp)])
	# Over another part's face: overlap. Under a deck that stands over it: blocked.
	var tight := _frigate()
	tight.add_equipment(&"kinetic_cannon", Vector3i(4, 2, 4), &"dorsal")
	assert_true(_codes(tight).has(&"equipment_overlap"), "a 2 × 2 patch over the PD mount beside it overlaps")
	var under := _frigate()
	under.add_equipment(&"kinetic_cannon", Vector3i(2, 1, 13), &"dorsal")
	under.add_module(&"hull_block_1x1", Vector3i(3, 3, 14))
	assert_true(_codes(under).has(&"equipment_blocked"), "hull two cells over a 2 × 2 gun blocks it: %s" % [_codes(under)])
	# A turret stands as tall as it is wide: its barrel rides N m off the face.
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config("t")
	var k := cfg.cannon_mount_ids.find(e.id)
	assert_near(cfg.turret_height(k), 2.0 * WorldSimulation.TURRET_HEIGHT_M, 1e-6, "a medium turret's height (m)")
	assert_near(cfg.turret_height(cfg.cannon_mount_ids.find("e41")), WorldSimulation.TURRET_HEIGHT_M, 1e-6, "a light one's (m)")


func test_an_old_design_reseats_its_bigger_guns() -> void:
	# The fixture frigate's one gun (e41, dorsal on the spine) turned railgun
	# where it stood, as a design from before the sizes would have it: on load
	# it moves to the nearest anchor whose 3 × 3 patch still covers its cell.
	var bp := _frigate()
	var gun := bp.find("e41") as ShipBlueprint.PlacedEquipment
	var was := gun.cell
	gun.def_id = &"railgun"
	var text := BlueprintIO.to_json(bp)
	var loaded := BlueprintIO.from_json(text, PackedStringArray())
	var moved := BlueprintFix.fit_spans(loaded, _catalog())
	var now := (loaded.find("e41") as ShipBlueprint.PlacedEquipment).cell
	print("    measured: the railgun moved from %s to %s" % [was, now])
	assert_true(moved.has("e41") and ShipGrid.patch(now, &"dorsal", 3).has(was) and _codes(loaded).is_empty(),
		"re-seated over its old cell, and the design is clean: %s" % [_codes(loaded)])


func test_landing_legs_let_a_ship_touch_down_faster() -> void:
	var moon := OrbitalBody.new()
	for f in Location.FILES:
		var loc: Location = load(f)
		if loc.id == "moon":
			moon = loc.body
	var legged := _frigate()
	for c in [Vector3i(2, 0, 1), Vector3i(5, 0, 1), Vector3i(2, 0, 14), Vector3i(5, 0, 14)]:
		legged.add_equipment(&"landing_leg", c, &"ventral")
	assert_true(_codes(legged).is_empty(), "four legs on the keel fit: %s" % [_codes(legged)])
	var results := {}
	for spec: Array in [["legs", legged, Quaternion.IDENTITY], ["none", _frigate(), Quaternion.IDENTITY],
			["legs on its side", legged, Quaternion(Vector3.BACK, PI * 0.5)]]:
		var bp: ShipBlueprint = spec[1]
		var grid := ShipGrid.build(bp, _catalog())
		var stats := ShipStats.compute(bp, grid)
		var cfg := stats.to_ship_config("lander")
		var ship := ShipState.create(&"lander", "lander", cfg, Vector3.ZERO)
		ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
		ship.orientation = spec[2]
		var map := moon.terrain()
		var ground := moon.radius_m + map.height_at(Vector3(0, 1, 0)) + ship.contact_radius_m()
		var sink := moon.safe_landing_mps * 2.0
		var w := WorldSimulation.new(DT)
		w.set_central_body(moon, Vec3d.new(0, ground + 0.5, 0), Vec3d.new(0, -sink, 0))
		w.terrain = map
		w.anchor_id = ship.id
		w.add_ship(ship)
		var safe := w.safe_landing_mps(ship)
		for t in 30:
			w.step()
		results[spec[0]] = [safe, ship.landed, ship.is_active()]
	print("    measured: safe touchdown %s" % results)
	assert_near(results.legs[0], moon.safe_landing_mps * WorldSimulation.LEG_TOUCHDOWN_FACTOR, 1e-6, "with legs down: ×3 (m/s)")
	assert_true(results.legs[1] and results.legs[2], "lands at twice the bare limit on its legs")
	assert_true(results.none[0] == moon.safe_landing_mps and not results.none[2], "without legs, the same speed is a crash")
	assert_true(results["legs on its side"][0] == moon.safe_landing_mps, "legs turned away from the ground don't count")


func test_corridors_move_the_crew_faster() -> void:
	var bp := _frigate()
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config("c"))
	var cells := 0
	for r in bp.rooms:
		if r.def_id == &"corridor":
			cells += r.rect.size.x * r.rect.size.y
	assert_near(sys.room_transit_s(), CrewRoster.ROOM_TRANSIT_S * (1.0 - minf(ShipSystems.CORRIDOR_PER_CELL * cells, ShipSystems.CORRIDOR_MAX)), 1e-6,
		"%d corridor cells: a room crossed faster (s)" % cells)
	for i in bp.rooms.size():
		if bp.rooms[i].def_id == &"corridor":
			sys.breach_room(i)
	assert_near(sys.room_transit_s(), CrewRoster.ROOM_TRANSIT_S, 1e-6, "vented corridors don't help (s)")


func test_windows_show_through_armour_and_the_name_over_it() -> void:
	var bp := BlueprintIO.load_file("res://data/blueprints/battleship_mk1.json", PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var model := ShipModelBuilder.build(bp, grid, grid.hull_bounds_m().get_center(), Color.WHITE, "NEWTON")
	var plated := 0
	for w in model.windows:
		var node: Node3D = w.node
		var p := node.position + grid.hull_bounds_m().get_center()
		var cell := Vector3i((p / ShipGrid.CELL_SIZE_M).floor())
		for face: StringName in [&"port", &"starboard"]:
			var inner: Vector3i = cell - ShipGrid.FACE_NORMALS[face]
			if bp.armor.has(ShipBlueprint.plate_key(inner, face)):
				plated += 1
	var labels := model.root.get_children().filter(func(n: Node) -> bool: return n is Label3D)
	var outer := 0.0
	for l: Label3D in labels:
		outer = maxf(outer, absf(l.position.x))
	print("    measured: %d windows, %d on plated flanks; the name %.2f m off centre (hull half-beam %.1f m)" % [model.windows.size(), plated,
		outer, grid.hull_bounds_m().size.x * 0.5])
	assert_true(plated > 0, "windows on armoured flanks are drawn (cut through the plate)")
	assert_true(labels.size() == 2 and outer > grid.hull_bounds_m().size.x * 0.5 - ShipGrid.CELL_SIZE_M + ShipModelBuilder.plate_depth(ShipBlueprint.PLATE_THICK_MM),
		"the name stands proud of the thickest plate on both flanks")
	model.root.free()


func test_every_hull_stands_on_legs_and_wears_skirts() -> void:
	for path in BlueprintIO.list_templates():
		var bp := BlueprintIO.load_file(path, PackedStringArray())
		var legs := bp.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == &"landing_leg" and e.face == &"ventral")
		assert_true(legs.size() >= WorldSimulation.LEGS_FOR_FOOTING, "%s stands on %d legs" % [bp.name, legs.size()])
		if path.contains("freighter"):
			continue
		var sloped := bp.modules.filter(func(m: ShipBlueprint.PlacedModule) -> bool:
			return m.def_id in [&"wedge_short", &"wedge_long"] and (m.rotation == 1 or m.rotation == 3))
		var prow := bp.modules.filter(func(m: ShipBlueprint.PlacedModule) -> bool: return m.def_id == &"wedge_long" and m.rotation == 0)
		assert_true(not sloped.is_empty() or not prow.is_empty(), "%s: sloped skirts or a chisel prow (%d, %d)" % [bp.name, sloped.size(), prow.size()])
