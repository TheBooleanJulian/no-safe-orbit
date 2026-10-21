extends TestCase
## Measures: play-test batch 6 — "hangar fighters should automatically
## target the next combat-ready enemy once their target is taken down, and
## automatically return (or when recalled) to dock to refuel and rearm":
## strikes move on from a beaten target to the nearest combat-ready one; an
## empty gun brings a craft home whatever its risk setting; a craft that
## came home on its own goes back out once rearmed, one recalled stays.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _ship(id: StringName, pos: Vector3, side: StringName) -> ShipState:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.side = side
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _disable(s: ShipState) -> void:
	for e in s.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.REACTOR:
			e.hp = 0.0
	s.systems.invalidate()
	s.systems.solve_power()


func _fighter(wing: AirWing) -> AirWing.Craft:
	for c in wing.crafts:
		if not c.is_drone():
			return c
	return null


func test_strikes_move_on_to_the_next_combat_ready_enemy() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", Vector3.ZERO, &"player")
	var near := _ship(&"t1", Vector3(0, 0, -3000), &"hostile")
	var far := _ship(&"t2", Vector3(0, 0, -6000), &"hostile")
	for s in [carrier, near, far]:
		world.add_ship(s)
	var wing := AirWing.for_ship(carrier)
	wing.target_id = &"t1"
	wing.candidate_ids.assign([&"t1", &"t2"])
	assert_true(wing.strike_target(world) == near, "the chosen target while it fights")
	_disable(near)
	assert_true(not AirWing.combat_ready(near) and wing.strike_target(world) == far, "beaten: on to the next combat-ready one")
	_disable(far)
	assert_true(wing.strike_target(world) == null, "nothing left: no strike target")
	# A fighter out on a strike with nothing left heads home, on its own.
	world.wings.append(wing)
	var f := _fighter(wing)
	f.directive = CraftAI.Directive.STRIKE
	assert_true(wing.launch(world, f) == "", "launched")
	for i in 30:
		world.step()
	assert_true(f.came_back_itself and f.override_reason.contains("nothing left"), "it turns for home (%s)" % f.override_reason)


func test_an_empty_gun_brings_a_craft_home_whatever_the_risk() -> void:
	var cfg: ShipConfig = load("res://data/craft/wasp_fighter.tres")
	var craft := ShipState.create(&"w", "w", cfg, Vector3.ZERO)
	craft.propellant_kg = cfg.propellant_capacity_kg
	craft.set_rounds(0)
	for risk in [CraftAI.Risk.CONSERVATIVE, CraftAI.Risk.BALANCED, CraftAI.Risk.AGGRESSIVE]:
		assert_true(CraftAI.disengage_reason(craft, risk) != "", "risk %d: an empty gun goes home" % risk)
	craft.set_rounds(cfg.cannon.magazine_rounds)
	assert_true(CraftAI.disengage_reason(craft, CraftAI.Risk.AGGRESSIVE) == "", "full: it stays")


func test_back_out_after_rearming_but_not_after_a_recall() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", Vector3.ZERO, &"player")
	var enemy := _ship(&"t1", Vector3(0, 0, -4000), &"hostile")
	world.add_ship(carrier)
	world.add_ship(enemy)
	var wing := AirWing.for_ship(carrier)
	wing.target_id = &"t1"
	wing.candidate_ids.assign([&"t1"])
	world.wings.append(wing)
	var f := _fighter(wing)
	f.came_back_itself = true
	f.service_left_s = 0.0
	world.step()
	assert_true(f.status == AirWing.Status.FLYING, "came home on its own, rearmed: back out")
	wing.recall(f)
	assert_true(not f.came_back_itself and f.directive == CraftAI.Directive.RETURN, "recalled: it stays home")
	# Back aboard after a recall: not relaunched.
	world.remove_ship(f.id)
	f.status = AirWing.Status.DOCKED
	world.step()
	assert_true(f.status == AirWing.Status.DOCKED, "a recalled craft is not relaunched")
	f.came_back_itself = true
	wing.auto_relaunch = false
	world.step()
	assert_true(f.status == AirWing.Status.DOCKED, "with the wing's setting off, nobody goes back out")
	wing.auto_relaunch = true
	_disable(enemy)
	world.step()
	assert_true(f.status == AirWing.Status.DOCKED, "and not when nothing is left to fight")
