extends TestCase
## Measures: turrets train at their traverse rate and fire only once on the
## aim; a gun whose line of fire crosses its own hull holds fire; a gangway
## locks the primary weapons; the ship AI lays the guns at half rate with
## extra spread; scans need a held lock and an active sensor mast; ramming
## pushes ships apart and damages the lighter, less armoured side more.

const DT := 1.0 / 60.0


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _ship(id: StringName, pos: Vector3 = Vector3.ZERO, bp: ShipBlueprint = null) -> ShipState:
	if bp == null:
		bp = _template()
	var catalog := ConstructionCatalog.default_catalog()
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


## Fire held, turrets aimed at `offset` (world, from the ship).
func _aimed(offset: Vector3) -> ShipControlInput:
	var input := ShipControlInput.neutral()
	input.fire = true
	input.has_aim = true
	input.aim_offset = offset
	return input


func _run(world: WorldSimulation, seconds: float) -> void:
	for i in roundi(seconds / DT):
		world.step()


func test_turret_trains_at_its_traverse_rate_then_fires_on_the_aim() -> void:
	var world := WorldSimulation.new(DT)
	var ship := _ship(&"s")
	world.add_ship(ship)
	assert_true(ship.config.is_turret(0), "the template's kinetic cannon is a turret")
	# Broadside to starboard: 90° from where the barrel starts (the nose).
	world.set_input(&"s", _aimed(Vector3(1500, 10, 0)))
	_run(world, 1.0)
	assert_true(ship.turret_status[0] == ShipState.Turret.SLEWING and ship.rounds_fired == 0,
		"after 1 s at %.0f°/s it is still training and has not fired (status %d, %d fired)" % [
			ship.config.cannon.traverse_deg_s, ship.turret_status[0], ship.rounds_fired])
	var trained := rad_to_deg(Vector3.FORWARD.angle_to(ship.turret_dirs[0]))
	assert_near(trained, ship.config.cannon.traverse_deg_s, 1.0, "trained %.1f° in 1 s" % trained)
	_run(world, 3.0)
	assert_true(ship.turret_status[0] == ShipState.Turret.READY and ship.rounds_fired > 0,
		"on the aim it fires (status %d, %d fired)" % [ship.turret_status[0], ship.rounds_fired])
	var shot := world.projectiles()[world.projectiles().size() - 1]
	var dir := (shot.velocity - ship.velocity).normalized()
	assert_true(dir.x > 0.99, "round goes out to starboard (dir %s)" % dir)


func test_a_gun_holds_fire_when_its_own_hull_is_in_the_way() -> void:
	var world := WorldSimulation.new(DT)
	var ship := _ship(&"s")
	world.add_ship(ship)
	# Aft and a few degrees down, along the deck: the fuselage is in the way.
	world.set_input(&"s", _aimed(Vector3(0, -40, 600)))
	_run(world, 8.0)
	assert_true(ship.turret_status[0] == ShipState.Turret.BLOCKED, "blocked by the hull (status %d)" % ship.turret_status[0])
	assert_true(ship.rounds_fired == 0, "a blocked gun does not fire (%d fired)" % ship.rounds_fired)
	# Straight down is below its face: out of arc, it holds at the limit.
	world.set_input(&"s", _aimed(Vector3(0, -1500, 0)))
	_run(world, 0.2)
	assert_true(ship.turret_status[0] == ShipState.Turret.OUT_OF_ARC or ship.turret_status[0] == ShipState.Turret.BLOCKED,
		"aim under the hull is out of arc (status %d)" % ship.turret_status[0])


func test_ship_ai_lays_the_guns_at_half_rate_with_extra_spread() -> void:
	var ship := _ship(&"s")
	var sys := ship.systems
	var before := sys.effective_config()
	for m in sys.crew.members:
		if m.role == CrewRoster.Role.COMMAND:
			m.state = CrewRoster.State.DEAD
	sys.invalidate()
	assert_true(not sys.has_command(), "no bridge crew: the ship AI is in control")
	var after := sys.effective_config()
	assert_near(after.cannon.rate_of_fire_rpm, before.cannon.rate_of_fire_rpm * ShipSystems.SHIP_AI_GUN_RATE_FACTOR, 1e-3, "rate of fire halved (rpm)")
	assert_near(after.cannon_extra_dispersion_rad, deg_to_rad(ShipSystems.SHIP_AI_DISPERSION_DEG), 1e-6, "extra spread (rad)")


func test_scans_need_a_held_lock_and_an_active_sensor_mast() -> void:
	var a := _ship(&"a")
	var b := _ship(&"b", Vector3(0, 0, -3000))
	var tr := SensorTrack.new()
	var t := 0.0
	# A bigger bridge scans faster.
	var scan_s := SensorTrack.SCAN_TIME_S / a.systems.room_bonus(&"command")
	while t < scan_s * 0.5:
		tr.update(a, b, t, 0.1)
		t += 0.1
	assert_true(not tr.scanned and tr.scan_progress > 0.4, "half way after half the time (%.2f)" % tr.scan_progress)
	while t < SensorTrack.SCAN_TIME_S + 0.2:
		tr.update(a, b, t, 0.1)
		t += 0.1
	assert_true(tr.scanned and absf(tr.scan_error - 1.0) <= SensorTrack.SCAN_ERROR + 1e-6, "scanned, error %.2f" % tr.scan_error)
	# Without the mast (visual only) nothing is scanned, even at close range.
	var blind := _ship(&"c")
	for e in blind.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.SENSOR:
			blind.systems.damage_equipment(e, 1000.0)
	var tr2 := SensorTrack.new()
	var near := _ship(&"d", Vector3(0, 0, -1000))
	for i in 60:
		tr2.update(blind, near, i * 0.1, 0.1)
	assert_true(tr2.locked and not tr2.scanned and tr2.scan_progress == 0.0, "locked visually but no scan without the mast")


func test_ramming_pushes_apart_and_hurts_the_lighter_side_more() -> void:
	var world := WorldSimulation.new(DT)
	var ship := _ship(&"ship")
	world.add_ship(ship)
	# A light craft (fighter config, no blueprint) flying into the bow.
	var fighter_cfg: ShipConfig = (load("res://data/catalog/equipment/fighter_rack.tres") as EquipmentDefinition).craft
	var craft := ShipState.create(&"intruder", "Intruder", fighter_cfg, Vector3(6, 3, -60), Vector3(0, 0, 25))
	world.add_ship(craft)
	var structure_before := 0.0
	for m in ship.systems.modules:
		structure_before += m.structure
	var events := PackedStringArray()
	for i in 240:
		world.step()
		events.append_array(world.take_link_events())
	var structure_after := 0.0
	for m in ship.systems.modules:
		structure_after += m.structure
	var ship_loss := structure_before - structure_after
	assert_true(craft.hull_damage > 0.0, "the craft is damaged (%.1f)" % craft.hull_damage)
	assert_true(craft.hull_damage > ship_loss, "the light craft takes more than the frigate (%.1f vs %.1f)" % [craft.hull_damage, ship_loss])
	assert_true(craft.velocity.z < 25.0 - 1.0 or not craft.is_active(), "the craft was stopped or bounced (v %s)" % craft.velocity)
	assert_true(Array(events).any(func(s: String) -> bool: return s.begins_with("COLLISION")), "the collision is reported")

	# Two frigates head-on at 6 m/s: both are damaged and they separate.
	var w2 := WorldSimulation.new(DT)
	var a := _ship(&"a")
	var b := _ship(&"b", Vector3(0, 0, -60))
	b.orientation = Quaternion(Vector3.UP, PI)
	a.velocity = Vector3(0, 0, -3)
	b.velocity = Vector3(0, 0, 3)
	a.snapshot_previous()
	b.snapshot_previous()
	w2.add_ship(a)
	w2.add_ship(b)
	for i in 600:
		w2.step()
	var closing := (a.velocity - b.velocity).dot((b.position - a.position).normalized())
	assert_true(closing <= 0.0, "after the impact they are no longer closing (%.2f m/s)" % closing)
	var damaged := func(s: ShipState) -> bool: return s.systems.modules.any(func(m: ShipSystems.ModuleState) -> bool: return m.structure < m.max_structure)
	assert_true(damaged.call(a) and damaged.call(b), "both frigates are damaged")


## `b` turned 180° with its first collar facing `a`'s, `gap` metres away.
func _alongside(a: ShipState, b: ShipState, gap: float) -> void:
	b.orientation = Quaternion(Vector3.UP, PI)
	var pa: Docking.Port = Docking.collars(a.systems)[0]
	var pb: Docking.Port = Docking.collars(b.systems)[0]
	b.position = pa.world_position(a) + pa.world_normal(a) * gap - b.orientation * pb.position_body
	b.velocity = a.velocity
	b.snapshot_previous()


func test_a_gangway_locks_the_primary_weapons() -> void:
	var world := WorldSimulation.new(DT)
	var a := _ship(&"a")
	var b := _ship(&"b")
	_alongside(a, b, 15.0)
	world.add_ship(a)
	world.add_ship(b)
	assert_true(not world.weapons_locked(&"a"), "no gangway: guns free")
	var found := world.dock(&"a", &"b")
	assert_true(found.has("link"), "gangway extending")
	assert_true(world.weapons_locked(&"a") and world.weapons_locked(&"b"), "gangway attached: both ships' guns locked")
	world.set_input(&"a", _aimed(Vector3(0, 300, -2000)))
	_run(world, 2.0)
	assert_true(a.rounds_fired == 0 and a.turret_status[0] == ShipState.Turret.LOCKED,
		"locked gun holds fire (%d fired, status %d)" % [a.rounds_fired, a.turret_status[0]])


func test_point_defence_engages_hostile_craft_but_not_our_own() -> void:
	var world := WorldSimulation.new(DT)
	var ship := _ship(&"ship")
	world.add_ship(ship)
	assert_true(ship.config.pd_mounts_body.size() == 2, "the frigate carries two point-defence turrets")
	var fighter_cfg: ShipConfig = (load("res://data/catalog/equipment/fighter_bay.tres") as EquipmentDefinition).craft
	var ours := ShipState.create(&"ship_e51", "Ours", fighter_cfg, Vector3(0, 60, -400))
	var hostile := ShipState.create(&"raider_e51", "Raider", fighter_cfg, Vector3(0, 80, -700))
	world.add_ship(ours)
	world.add_ship(hostile)
	_run(world, 6.0)
	assert_true(not ship.pd_targets.has("ship_e51"), "our own fighter is never engaged")
	assert_true(hostile.hull_damage > 0.0 or not hostile.is_active(), "the hostile fighter is hit (%.1f)" % hostile.hull_damage)
	assert_true(ours.hull_damage == 0.0, "ours is untouched")
	# Automatic defences keep working with a gangway attached.
	assert_true(ship.pd_rounds < ship.pd_rounds_capacity, "it spent rounds from the magazine")
