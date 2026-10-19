extends TestCase
## Measures: Milestone 6 — autonomous craft (spec §16 "Autonomous units"):
## the wing comes from the racks; launch needs a working rack and a steady
## carrier; strike, recon, escort, intercept and return directives; risk-
## based disengagement; communications fallback; craft hull damage, loss and
## persistence with replacement at the station.

const DT := 1.0 / 30.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


## `pd`: keep the template's point-defence turrets (off for a target the
## tests' craft must reach unharmed).
func _ship(id: StringName, pos: Vector3 = Vector3.ZERO, pd: bool = true) -> ShipState:
	var bp := _template()
	if not pd:
		for e in bp.equipment.duplicate():
			if e.def_id == &"point_defence":
				bp.remove(e.id)
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


## World with our carrier "c" (wing attached) and a passive target "t".
func _setup(target_pos: Vector3 = Vector3(0, 0, -3000)) -> Array:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c")
	var target := _ship(&"t", target_pos, false)
	world.add_ship(carrier)
	world.add_ship(target)
	var wing := AirWing.for_ship(carrier)
	wing.target_id = &"t"
	world.wings.append(wing)
	return [world, carrier, target, wing]


func _fighter(wing: AirWing) -> AirWing.Craft:
	for c in wing.crafts:
		if not c.is_drone():
			return c
	return null


func _drone(wing: AirWing) -> AirWing.Craft:
	for c in wing.crafts:
		if c.is_drone():
			return c
	return null


func _run(world: WorldSimulation, seconds: float, until: Callable = Callable()) -> float:
	var t := 0.0
	while t < seconds:
		if until.is_valid() and until.call():
			break
		world.step()
		t += DT
	return t


func test_the_wing_comes_from_the_racks() -> void:
	var wing := AirWing.for_ship(_ship(&"c"))
	assert_true(wing.crafts.size() == 2, "Frigate Mk I carries a fighter and a drone (%d craft)" % wing.crafts.size())
	assert_true(_fighter(wing).directive == CraftAI.Directive.STRIKE and _drone(wing).directive == CraftAI.Directive.RECON,
		"fighters default to strike, drones to recon")


func test_launch_needs_a_working_rack_and_a_steady_carrier() -> void:
	var s := _setup()
	var world: WorldSimulation = s[0]
	var carrier: ShipState = s[1]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	carrier.angular_velocity = Vector3(0, 0.3, 0)
	assert_true(wing.launch(world, f).contains("turning too fast"), "no launch while the carrier spins")
	carrier.angular_velocity = Vector3.ZERO
	assert_true(wing.launch(world, f) == "", "launched")
	var craft := world.get_ship(f.id)
	var frame := wing.rack_frame(world, f)
	assert_near(craft.position.distance_to(frame[0]), AirWing.LAUNCH_CLEAR_M, 1e-3, "clear of the rack (m)")
	assert_near((craft.velocity - carrier.velocity).length(), AirWing.LAUNCH_PUSH_MPS, 1e-4, "pushed off at (m/s)")
	var d := _drone(wing)
	carrier.systems.damage_equipment(carrier.systems.equipment_by_id(d.rack_id), 1000.0)
	assert_true(wing.launch(world, d).contains("rack"), "a destroyed rack launches nothing")


func test_strike_closes_and_hits_the_target() -> void:
	var s := _setup()
	var world: WorldSimulation = s[0]
	var target: ShipState = s[2]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	wing.launch(world, f)
	var hits := 0
	var closest := INF
	var t := 0.0
	while t < 120.0 and f.status == AirWing.Status.FLYING:
		world.step()
		t += DT
		if world.has_ship(f.id):
			closest = minf(closest, world.get_ship(f.id).position.distance_to(target.position))
		for ev in world.take_hit_events():
			if ev.shooter_id == f.id and ev.target_id == &"t":
				hits += 1
	assert_true(hits >= 5, "the fighter lands >= 5 hits on the target (%d hits)" % hits)
	assert_near(closest, CraftAI.STRIKE_RANGE_M, 250.0, "its gun runs bring it to its standoff range (closest, m)")
	assert_true("\n".join(wing.log).contains("ammunition low"), "magazine spent, it breaks off on its own:\n%s" % "\n".join(wing.log))


func test_strike_aims_at_the_chosen_subsystem() -> void:
	var target := _ship(&"t")
	var engines := CraftAI.aim_point(target, CraftAI.PRIORITY_NAMES.find("Engines"))
	var e29 := target.position + target.orientation * target.systems.equipment_by_id("e29").body_position
	assert_vec_near(engines, e29, 1e-4, "engines priority aims at a main engine")
	for e in target.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.MAIN_ENGINE:
			target.systems.damage_equipment(e, 1000.0)
	assert_vec_near(CraftAI.aim_point(target, 2), target.position + target.orientation * target.config.hit_box_center, 1e-4,
		"with every engine gone it aims at the hull")


func test_recon_keeps_its_distance_and_gives_a_close_look() -> void:
	var s := _setup(Vector3(0, 0, -8000))
	var world: WorldSimulation = s[0]
	var target: ShipState = s[2]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	f.directive = CraftAI.Directive.RECON
	assert_true(not wing.has_close_look(world, target), "at 8 km the carrier alone has no close look")
	wing.launch(world, f)
	_run(world, 200.0)
	var craft := world.get_ship(f.id)
	assert_near(craft.position.distance_to(target.position), CraftAI.RECON_RANGE_M, 300.0, "recon holds station (m)")
	assert_true(craft.rounds_fired == 0, "recon never fires")
	assert_true(wing.has_close_look(world, target), "the recon craft gives a close look")


func test_escort_stays_with_the_carrier() -> void:
	var s := _setup()
	var world: WorldSimulation = s[0]
	var carrier: ShipState = s[1]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	f.directive = CraftAI.Directive.ESCORT
	wing.launch(world, f)
	carrier.velocity = Vector3(5, 0, 0)  # the carrier drifts off
	_run(world, 60.0)
	assert_less_equal(world.get_ship(f.id).position.distance_to(carrier.position), 250.0, "escort within (m) after 60 s")


func test_return_recovers_and_services_the_craft() -> void:
	var s := _setup()
	var world: WorldSimulation = s[0]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	wing.launch(world, f)
	_run(world, 20.0)
	f.directive = CraftAI.Directive.RETURN
	var t := _run(world, 180.0, func() -> bool: return f.status == AirWing.Status.DOCKED)
	assert_true(f.status == AirWing.Status.DOCKED and not world.has_ship(f.id), "recovered after %.0f s" % t)
	assert_true(f.service_left_s > 0.0 and wing.launch(world, f).contains("rearmed"), "it must be serviced before flying again")
	_run(world, AirWing.SERVICE_S + 1.0)
	assert_true(f.service_left_s == 0.0 and f.propellant_fraction == 1.0, "serviced: full tanks")


func test_risk_tolerance_decides_when_to_break_off() -> void:
	for risk in [CraftAI.Risk.CONSERVATIVE, CraftAI.Risk.AGGRESSIVE]:
		var s := _setup()
		var world: WorldSimulation = s[0]
		var wing: AirWing = s[3]
		var f := _fighter(wing)
		f.risk = risk
		wing.launch(world, f)
		world.get_ship(f.id).hull_damage = 0.5 * f.config.hull_hp
		_run(world, 1.0)
		var broke_off := "\n".join(wing.log).contains("disengaging")
		if risk == CraftAI.Risk.CONSERVATIVE:
			assert_true(broke_off, "conservative: half a hull is enough — it breaks off:
%s" % "\n".join(wing.log))
		else:
			assert_true(not broke_off and f.status == AirWing.Status.FLYING, "aggressive: it fights on at half a hull")


func test_lost_comms_fall_back_to_return() -> void:
	var s := _setup()
	var world: WorldSimulation = s[0]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	wing.launch(world, f)
	wing.jammed = true
	_run(world, AirWing.COMMS_FALLBACK_S - 1.0)
	assert_true(f.override_reason == "", "it keeps its orders for a while without contact")
	_run(world, 2.0)
	assert_true(f.override_reason.contains("no comms"), "then falls back to returning: %s" % f.override_reason)
	wing.jammed = false
	_run(world, 0.5)
	assert_true(f.override_reason == "", "contact back: it resumes its directive")


func test_rounds_wreck_a_craft_and_it_stays_lost() -> void:
	var s := _setup()
	var world: WorldSimulation = s[0]
	var wing: AirWing = s[3]
	var f := _fighter(wing)
	wing.launch(world, f)
	var craft := world.get_ship(f.id)
	var gun: KineticCannonConfig = load("res://data/weapons/medium_kinetic_cannon.tres")
	var shot := ProjectileState.new()
	shot.id = 999
	shot.shooter_id = &"t"
	shot.weapon = gun
	shot.age_s = 10.0
	shot.position = craft.position + Vector3(0, 0, -200)
	shot.prev_position = shot.position
	shot.velocity = craft.velocity + Vector3(0, 0, gun.muzzle_velocity_mps)
	world.projectiles().append(shot)
	_run(world, 1.0)
	assert_true(f.status == AirWing.Status.LOST and not world.has_ship(f.id), "a 60 mm round through a 40 hp fighter: lost")
	var p := PlayerProfile.new(1)
	p.ensure_vessel(_template())
	p.vessel.wing = wing.state()
	var job: ServiceYard.Job
	for j in ServiceYard.repair_jobs(p.vessel, _catalog()):
		if j.kind == &"craft":
			job = j
	assert_true(job != null and job.label.contains("Replace lost") and job.cost == 10, "the station replaces it for 10 spare parts")
	var again := AirWing.for_ship(_ship(&"c"))
	again.apply_state(p.vessel.wing)
	assert_true(_fighter(again).status == AirWing.Status.LOST and again.launch(world, _fighter(again)).contains("lost"),
		"next sortie it is still lost until replaced")
	var one: Array[ServiceYard.Job] = [job]
	p.spare_parts = 100
	ServiceYard.perform(one, p.vessel, p)
	assert_true(p.vessel.wing.is_empty(), "replaced")


func test_intercept_goes_after_hostile_craft() -> void:
	var s := _setup(Vector3(0, 0, -4000))
	var world: WorldSimulation = s[0]
	var target: ShipState = s[2]
	var wing: AirWing = s[3]
	var enemy := AirWing.for_ship(target)
	enemy.target_id = &"c"
	world.wings.append(enemy)
	var theirs := _fighter(enemy)
	enemy.launch(world, theirs)
	wing.hostile_ids = [theirs.id]
	var ours := _fighter(wing)
	ours.directive = CraftAI.Directive.INTERCEPT
	wing.launch(world, ours)
	var hits_on_them := 0
	var t := 0.0
	while t < 120.0 and theirs.status == AirWing.Status.FLYING:
		world.step()
		t += DT
		for ev in world.take_hit_events():
			if ev.shooter_id == ours.id and ev.target_id == theirs.id:
				hits_on_them += 1
	assert_true(hits_on_them > 0, "our interceptor hits the enemy fighter (%d hits; enemy %s)" % [hits_on_them, AirWing.STATUS_NAMES[theirs.status]])
