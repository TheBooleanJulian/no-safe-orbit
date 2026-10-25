extends TestCase
## Measures: play-test batch 6 — beam weapons. A pulse strikes the first
## hull on its line in the tick it is fired (no round in flight), out to its
## reach and no further, with penetration falling to half at full reach;
## fire control holds a beam until its target is in reach. On a ship a beam
## spends no rounds but draws power and makes heat; a craft's beam spends
## charges, recharged aboard from the carrier's power, not its magazine. A
## laser drone shoots down a missile. The parts exist for ships, fighters
## and drones and sort into the right palette sections; pulses are drawn.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


## The stock frigate, with every `from` part swapped for `to`.
func _frigate(swaps: Dictionary = {}) -> ShipBlueprint:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	for e in bp.equipment:
		if swaps.has(e.def_id):
			e.def_id = swaps[e.def_id]
	return bp


func _ship(id: StringName, pos: Vector3, side: StringName, bp: ShipBlueprint) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.side = side
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _craft(id: StringName, path: String, pos: Vector3, side: StringName) -> ShipState:
	var c := ShipState.create(id, String(id), load(path) as ShipConfig, pos)
	c.side = side
	c.propellant_kg = c.config.propellant_capacity_kg
	return c


func _laser_duel(range_m: float) -> Array:
	var world := WorldSimulation.new(DT)
	var me := _ship(&"me", Vector3.ZERO, &"player", _frigate({&"autocannon": &"laser_turret"}))
	var foe := _ship(&"foe", Vector3(0, 0, -range_m), &"hostile", _frigate())
	world.add_ship(me)
	world.add_ship(foe)
	return [world, me, foe]


func test_a_beam_strikes_in_the_tick_it_fires_out_to_its_reach() -> void:
	var duel := _laser_duel(3000.0)
	var world: WorldSimulation = duel[0]
	var me: ShipState = duel[1]
	var rounds_before := me.cannon_rounds
	var fired_tick := -1
	var hit: HitEvent = null
	for i in roundi(20.0 / DT):
		world.set_input(&"me", GunneryAI.command(me, duel[2]))
		var pulses := me.beam_pulses
		var this_tick := world.tick
		world.step()
		if me.beam_pulses > pulses and fired_tick < 0:
			fired_tick = this_tick
		for ev in world.take_hit_events():
			if hit == null and ev.shooter_id == &"me":
				hit = ev
		assert_true(world.round_count() == 0, "no round in flight")
		if hit != null:
			break
	assert_true(fired_tick >= 0 and hit != null, "the laser fired and struck")
	if hit == null:
		return
	var expected := 80.0 * lerpf(1.0, KineticCannonConfig.BEAM_FALLOFF, 3000.0 / 5000.0)
	print("    measured: first pulse at tick %d, struck at tick %d · %.1f mm at ~3 km (expected ≈ %.1f, 80 mm close in) · rounds %d → %d" % [
		fired_tick, hit.tick, hit.report.entry_pen_mm, expected, rounds_before, me.cannon_rounds])
	assert_true(hit.tick == fired_tick and hit.beam, "struck in the tick it fired (no travel time)")
	assert_true(absf(hit.report.entry_pen_mm - expected) < 2.0, "penetration falls with range (%.1f mm)" % hit.report.entry_pen_mm)
	assert_true(me.cannon_rounds == rounds_before, "no rounds spent")
	assert_true(not hit.report.ricochet, "a beam does not ricochet")
	# Beyond reach: fire control holds the beam.
	duel = _laser_duel(6000.0)
	world = duel[0]
	me = duel[1]
	for i in roundi(10.0 / DT):
		world.set_input(&"me", GunneryAI.command(me, duel[2]))
		world.step()
	assert_true(me.beam_pulses == 0, "held at 6 km, beyond the 5 km reach (%d pulses)" % me.beam_pulses)
	# Fired blind (no target): out to full reach, and nothing at 6 km is hit.
	for i in roundi(10.0 / DT):
		var input := GunneryAI.command(me, duel[2])
		input.lead_target_id = &""
		world.set_input(&"me", input)
		world.step()
	var beams := world.take_beams()
	print("    measured: blind at 6 km — %d pulses, %d hits, reach %.0f m" % [me.beam_pulses, world.beam_hits, Vector3(beams[0].to_body).length() if not beams.is_empty() else 0.0])
	assert_true(me.beam_pulses > 0 and world.beam_hits == 0, "a pulse stops at its reach")
	assert_true(not beams.is_empty() and absf(Vector3(beams[0].to_body).length() - 5000.0) < 1.0 and StringName(beams[0].target_id) == &"", "drawn out to its 5 km reach")


func test_a_ships_beam_costs_power_and_heat_not_rounds() -> void:
	var world := WorldSimulation.new(DT)
	var stock := _ship(&"stock", Vector3(0, 500, 0), &"player", _frigate())
	var duel := _laser_duel(2000.0)
	world = duel[0]
	var me: ShipState = duel[1]
	world.add_ship(stock)
	world.step()
	var extra := me.systems.power_demand_kw - stock.systems.power_demand_kw
	var turret: EquipmentDefinition = _catalog().equipment[&"laser_turret"]
	var autocannon: EquipmentDefinition = _catalog().equipment[&"autocannon"]
	print("    measured: power demand %.0f kW vs the stock frigate's %.0f kW (+%.0f; turret %.0f, autocannon %.0f)" % [
		me.systems.power_demand_kw, stock.systems.power_demand_kw, extra, -turret.power_kw, -autocannon.power_kw])
	assert_true(absf(extra - (autocannon.power_kw - turret.power_kw)) < 1.0, "the laser draws its power")
	var per_pulse_kw := turret.heat_kw * turret.cannon.fire_interval_s() / DT
	var jump := -1.0
	for i in roundi(20.0 / DT):
		world.set_input(&"me", GunneryAI.command(me, duel[2]))
		var pulses := me.beam_pulses
		var before := me.systems.heat_generation_kw
		world.step()
		if me.beam_pulses == pulses + 1 and i > 0:
			jump = me.systems.heat_generation_kw - before
			break
	print("    measured: heat on the pulse's tick +%.0f kW (expected %.0f kW: %.0f kW × %.1f s in one tick)" % [
		jump, per_pulse_kw, turret.heat_kw, turret.cannon.fire_interval_s()])
	assert_true(absf(jump - per_pulse_kw) < per_pulse_kw * 0.02, "each pulse is its heat_kw for one firing interval")


func test_a_laser_fighter_spends_charges_and_recharges_aboard() -> void:
	var world := WorldSimulation.new(DT)
	var me := _craft(&"lancer", "res://data/craft/lancer_fighter.tres", Vector3.ZERO, &"player")
	var pal := _craft(&"pal", "res://data/craft/wasp_fighter.tres", Vector3(0, 0, -400), &"player")
	var foe := _craft(&"foe", "res://data/craft/wasp_fighter.tres", Vector3(0, 0, -800), &"hostile")
	for s in [me, pal, foe]:
		world.add_ship(s)
	var charges := me.cannon_rounds
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.fire = true
	for i in roundi(2.0 / DT):
		world.set_input(&"lancer", input)
		world.step()
	var pulses := charges - me.cannon_rounds
	var per := 14.0 * lerpf(1.0, KineticCannonConfig.BEAM_FALLOFF, 795.0 / 1500.0)
	print("    measured: %d pulses in 2 s (90 rpm) · %d/%d charges left · foe hull damage %.1f (≈ %.1f a pulse) · friend %.1f" % [
		pulses, me.cannon_rounds, charges, foe.hull_damage, per, pal.hull_damage])
	assert_true(pulses >= 2 and me.beam_pulses == pulses, "each pulse spends a charge")
	assert_true(pal.hull_damage == 0.0 and foe.hull_damage > 0.0, "through the friendly craft (IFF) onto the foe")
	assert_true(absf(foe.hull_damage / pulses - per) < 0.5, "%.1f a pulse at 800 m" % (foe.hull_damage / pulses))
	# Aboard: charges come back from the carrier's power, its magazine untouched.
	var carrier := _ship(&"c", Vector3(0, 0, 3000), &"player", _frigate({&"fighter_bay": &"laser_fighter_bay"}))
	var wing := AirWing.for_ship(carrier)
	var lancer: AirWing.Craft = null
	for c in wing.crafts:
		if c.config.display_name == "Lancer laser fighter":
			lancer = c
	assert_true(lancer != null, "the laser fighter bay carries a Lancer")
	if lancer == null:
		return
	lancer.ammo = 0
	var magazine := carrier.cannon_rounds
	wing._resupply_from(carrier, lancer)
	assert_true(lancer.ammo == lancer.config.cannon.magazine_rounds and carrier.cannon_rounds == magazine,
		"recharged %d/%d, the carrier's magazine %d → %d" % [lancer.ammo, lancer.config.cannon.magazine_rounds, magazine, carrier.cannon_rounds])


func test_a_laser_drone_shoots_down_a_missile() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", Vector3.ZERO, &"player", _frigate())
	var no_pd := ShipPolicy.preset("Hold")
	no_pd.pd_enabled = false
	carrier.policy = no_pd  # the drone's kill, not the carrier's point defence
	world.add_ship(carrier)
	var bp := _frigate()
	EnemyFactory._fit_launcher(bp, _catalog(), &"missile_rack", RandomNumberGenerator.new())
	var shooter := _ship(&"enemy", Vector3(0, 0, -7000), &"hostile", bp)
	world.add_ship(shooter)
	var drone := _craft(&"c_drone", "res://data/craft/laser_drone.tres", Vector3(0, 30, -200), &"player")
	world.add_ship(drone)
	world.launch_missile(&"enemy", &"c")
	var friends: Array[ShipState] = [carrier, drone]
	var events := ""
	for i in roundi(30.0 / DT):
		var no_hostiles: Array[ShipState] = []
		world.set_input(&"c_drone", CraftAI.command(drone, CraftAI.Directive.ESCORT, carrier, Vector3.ZERO, shooter, no_hostiles, 0, 0,
			friends, world.missiles.duplicate(), DT))
		world.step()
		events += "\n".join(world.take_link_events())
		if world.missiles.is_empty():
			break
	print("    measured: laser drone vs missile — %s · %d pulses, %d hits" % [
		"shot down" if events.contains("shot down") else events.right(120), drone.beam_pulses, world.beam_hits])
	assert_true(events.contains("shot down") and world.beam_hits > 0, "the laser drone shoots the missile down")


func test_beam_parts_exist_and_sort_into_their_sections() -> void:
	var cat := _catalog()
	var want := {
		&"laser_turret": ["Weapons", "Guns"], &"laser_fighter_bay": ["Hangars & craft", "Fighters"],
		&"laser_drone_rack": ["Hangars & craft", "Drones"], &"fighter_bay": ["Hangars & craft", "Fighters"],
		&"interceptor_rack": ["Hangars & craft", "Fighters"], &"drone_rack": ["Hangars & craft", "Drones"],
		&"ew_drone_rack": ["Hangars & craft", "Drones"],
	}
	for id: StringName in want:
		var def: EquipmentDefinition = cat.equipment.get(id)
		assert_true(def != null, "%s in the catalog" % id)
		if def != null:
			assert_true(def.validate().is_empty(), "%s valid: %s" % [id, def.validate()])
			assert_true(Shipyard.palette_place("equipment", def) == want[id], "%s under %s (was %s)" % [id, want[id], Shipyard.palette_place("equipment", def)])
	for id: StringName in [&"laser_turret", &"laser_fighter_bay", &"laser_drone_rack"]:
		var def: EquipmentDefinition = cat.equipment[id]
		var gun := def.cannon if def.cannon != null else def.craft.cannon
		assert_true(gun.is_beam() and def.rarity != Rarity.Tier.COMMON, "%s is a beam, and rarer than common" % id)
	var bp := _frigate({&"autocannon": &"laser_turret", &"fighter_bay": &"laser_fighter_bay", &"drone_rack": &"laser_drone_rack"})
	var r := ShipValidator.validate(bp, cat)
	assert_true(not r.has_errors(), "a frigate refitted with all three is valid:\n%s" % r.summary())


func test_a_pulse_is_drawn_between_muzzle_and_hit() -> void:
	var world := WorldSimulation.new(DT)
	var me := _craft(&"a", "res://data/craft/lancer_fighter.tres", Vector3.ZERO, &"player")
	var foe := _craft(&"b", "res://data/craft/wasp_fighter.tres", Vector3(0, 0, -600), &"hostile")
	world.add_ship(me)
	world.add_ship(foe)
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.fire = true
	world.set_input(&"a", input)
	world.step()
	var view := BeamView.new()
	view._ready()
	view.add(world.take_beams())
	view.sync(world, 1.0, Vector3.ZERO, Vector3(0, 50, 0), DT)
	var shown := 0
	var length := 0.0
	for m in view._meshes:
		if m.visible:
			shown += 1
			length = m.transform.basis.y.length()
	print("    measured: %d pulse drawn, %.0f m long (muzzle 6 m ahead, foe's hull ~595 m out)" % [shown, length])
	assert_true(shown == 1 and absf(length - 589.0) < 6.0, "one line from the muzzle to the hit")
	view.sync(world, 1.0, Vector3.ZERO, Vector3(0, 50, 0), BeamView.LIFE_S)
	assert_true(view.active_count() == 0, "and gone after %.2f s" % BeamView.LIFE_S)
	view.free()
