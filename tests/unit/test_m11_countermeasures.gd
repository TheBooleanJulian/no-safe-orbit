extends TestCase
## Measures: Milestone 11 — flares (launching, burning out, riding frame
## rebases), seekers chasing them by signature and discrimination (seeded:
## the same engagement always ends the same way), timing (flares fired too
## early burn out and the missile finds the ship again), jamming (track
## confidence and locks beyond burn-through, hardened masts, missiles losing
## lock), EW drones, auto-countermeasures in the policy, and flares
## restocked at the yard.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _fitted(parts: Array) -> ShipBlueprint:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var rng := RandomNumberGenerator.new()
	for id: StringName in parts:
		EnemyFactory._fit_launcher(bp, _catalog(), id, rng)
	return bp


## Without its point defence (so the countermeasure under test is alone).
func _no_pd(bp: ShipBlueprint) -> ShipBlueprint:
	for e in bp.equipment.duplicate():
		var def: EquipmentDefinition = _catalog().equipment.get(e.def_id)
		if def != null and def.kind == EquipmentDefinition.Kind.POINT_DEFENCE:
			bp.remove(e.id)
	return bp


func _ship(id: StringName, bp: ShipBlueprint, pos: Vector3, side: StringName) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.side = side
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _count(sys: ShipSystems, def_id: StringName) -> int:
	var n := 0
	for e in sys.equipment:
		if e.def.id == def_id:
			n += 1
	return n


## A missile duel: `a` (a missile rack) fires one anti-ship missile at `b`
## `range_m` away; `b` fires flares when the missile is `flare_at_s` out
## (< 0: never). Returns {hit, decoyed, lost, hull_before, hull_after}.
func _engagement(range_m: float, flare_at_s: float, b_parts: Array = [&"flare_launcher"], flares: int = 3) -> Dictionary:
	var world := WorldSimulation.new(DT)
	world.add_ship(_ship(&"a", _fitted([&"missile_rack"]), Vector3.ZERO, &"hostile"))
	var b := _ship(&"b", _no_pd(_fitted(b_parts)), Vector3(0, 0, -range_m), &"player")
	world.add_ship(b)
	var hull_before := _hull(b)
	assert_true(world.launch_missile(&"a", &"b") == "", "the missile is away")
	var flared := false
	var events := PackedStringArray()
	var t := 0.0
	while t < 60.0 and not world.missiles.is_empty():
		if not flared and flare_at_s >= 0.0 and Hud.missile_inbound_time(world, b) <= flare_at_s and Hud.missile_inbound_time(world, b) >= 0.0:
			flared = world.launch_decoys(&"b", flares) == ""
		world.step()
		events.append_array(world.take_link_events())
		t += DT
	var text := "\n".join(events)
	return {"hit": _hull(b) < hull_before, "decoyed": text.contains("decoyed by a flare"), "burst_on_flare": text.contains("burst on a flare"),
		"lost": text.contains("lost its flare") or text.contains("jammed"), "flared": flared, "events": text}


func _hull(s: ShipState) -> float:
	var h := 0.0
	for m in s.systems.modules:
		h += m.structure
	for e in s.systems.equipment:
		h += e.hp
	return h


func test_parts_are_valid_and_flares_are_standard_kit() -> void:
	var eq := _catalog().equipment
	for id in [&"flare_launcher", &"jammer", &"ew_drone_rack"]:
		assert_true(eq.has(id) and (eq[id] as EquipmentDefinition).validate().is_empty(), "%s exists and validates" % id)
	assert_true((eq[&"flare_launcher"] as EquipmentDefinition).rarity == Rarity.Tier.COMMON, "flares are common (always in the yard)")
	assert_true((eq[&"ew_drone_rack"] as EquipmentDefinition).craft.jam_strength > 0.0, "the EW drone jams")
	var bp := _fitted([&"flare_launcher", &"jammer"])
	assert_true(not ShipValidator.validate(bp, _catalog()).has_errors(), "a frigate with flares and a jammer validates")


func test_launching_flares() -> void:
	var world := WorldSimulation.new(DT)
	var s := _ship(&"s", _fitted([&"flare_launcher"]), Vector3.ZERO, &"player")
	world.add_ship(s)
	var before := s.systems.decoys_aboard()
	assert_true(world.launch_decoys(&"s") == "" and world.decoys.size() == 1, "one launch: the first flare at once (%d)" % world.decoys.size())
	for i in roundi(0.3 / DT):
		world.step()
	assert_true(world.decoys.size() == 2, "the next %.2f s later, not all at once (%d)" % [WorldSimulation.FLARE_INTERVAL_S, world.decoys.size()])
	for i in roundi(0.3 / DT):
		world.step()
	assert_true(world.decoys.size() == 3 and world.flares_queued(&"s") == 0, "three in all (%d)" % world.decoys.size())
	assert_true(s.systems.decoys_aboard() == before - 3, "taken from the magazine (%d → %d)" % [before, s.systems.decoys_aboard()])
	var spread := (world.decoys[0].position as Vector3).distance_to(world.decoys[1].position)
	for i in roundi(2.0 / DT):
		world.step()
	var later := (world.decoys[0].position as Vector3).distance_to(world.decoys[1].position)
	assert_true(later > spread + 20.0, "they fan out (%.0f m → %.0f m apart)" % [spread, later])
	assert_true(WorldSimulation.decoy_signature(world.decoys[0]) < 2.5, "and burn down")
	for i in roundi(5.0 / DT):
		world.step()
	assert_true(world.decoys.is_empty(), "gone after their %.0f s burn" % 6.0)
	assert_true(not s.systems.ready_decoy_launchers().is_empty(), "the launcher has cycled")


func test_seduction_odds() -> void:
	var p_ship := WorldSimulation.seduction_chance(2.5, 1.0, 1.0)
	var p_smart := WorldSimulation.seduction_chance(2.5, 1.0, 2.0)
	var p_dumb := WorldSimulation.seduction_chance(2.5, 1.0, 0.6)
	assert_near(p_ship, 2.5 / 3.5, 1e-6, "a fresh flare against a frigate, standard seeker")
	assert_true(p_smart < p_ship and p_ship < p_dumb, "a sharper seeker is fooled less (%.2f < %.2f < %.2f)" % [p_smart, p_ship, p_dumb])
	var burning := ShipState.create(&"x", "x", _ship(&"y", _fitted([]), Vector3.ZERO, &"").config)
	var cold := WorldSimulation.signature_of(burning)
	burning.last_thrust_body = Vector3(0, 0, -burning.config.thrust_forward_n)
	assert_true(WorldSimulation.signature_of(burning) > cold * 2.0, "engines at full burn: much brighter (%.2f → %.2f)" % [cold, WorldSimulation.signature_of(burning)])
	# The rolls are uniform and repeatable.
	var under := 0
	for i in 2000:
		if WorldSimulation._roll("k%d" % i) < 0.7:
			under += 1
	assert_near(under / 2000.0, 0.7, 0.04, "seeded rolls fall under 0.7 about 70 % of the time")
	assert_true(WorldSimulation._roll("same") == WorldSimulation._roll("same"), "the same key, the same roll")


func test_flares_defeat_a_missile_fired_on_time() -> void:
	var bare := _engagement(6000.0, -1.0)
	assert_true(bare.hit, "no flares: the missile hits")
	var flared := _engagement(6000.0, 3.5)
	print("    measured: flares 3.5 s out — flared %s, decoyed %s, burst on a flare %s, hit %s" % [flared.flared, flared.decoyed, flared.burst_on_flare, flared.hit])
	assert_true(flared.flared and flared.decoyed and not flared.hit, "flares at 3.5 s: the missile chases one and the ship is unhurt")
	var again := _engagement(6000.0, 3.5)
	assert_true(again.decoyed == flared.decoyed and again.hit == flared.hit, "seeded: the same engagement ends the same way")


func test_flares_fired_too_early_burn_out() -> void:
	# One flare (play-test batch 11: a staggered burst can hand the missile
	# from flare to flare until it loses the ship — bursts are put out on
	# time, by the policy, one missile's worth at a time).
	var early := _engagement(9000.0, 14.0, [&"flare_launcher"], 1)
	print("    measured: a flare 14 s out — decoyed %s, hit %s" % [early.decoyed, early.hit])
	assert_true(early.flared and early.hit, "a flare fired 14 s out burns out first; the missile finds the ship again")


func test_jamming_degrades_tracks_beyond_burn_through() -> void:
	var observer := _ship(&"o", _fitted([]), Vector3.ZERO, &"hostile")
	var far := _ship(&"t", _fitted([&"jammer"]), Vector3(0, 0, -8000), &"player")
	var jam := far.systems.jamming_strength()
	assert_true(jam >= 1.0, "a working jammer (%.1f)" % jam)
	var clear := SensorTrack.new()
	clear.update(observer, far, 0.0, DT, 0.0)
	var jammed := SensorTrack.new()
	jammed.update(observer, far, 0.0, DT, jam)
	print("    measured: 8 km — confidence %.2f clear, %.2f jammed; locked %s / %s" % [clear.confidence, jammed.confidence, clear.locked, jammed.locked])
	assert_true(clear.locked and not jammed.locked and jammed.confidence < clear.confidence * 0.5, "at 8 km the jammer breaks the lock")
	far.position = Vector3(0, 0, -2500)
	var close := SensorTrack.new()
	close.update(observer, far, 0.0, DT, jam)
	assert_true(close.locked and close.jammed == 0.0, "inside 3 km the radar burns through")
	far.position = Vector3(0, 0, -8000)
	var hardened := _ship(&"h", BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()), Vector3.ZERO, &"hostile")
	for e in hardened.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.SENSOR:
			e.def = _catalog().equipment[&"sensor_mast_hardened"]
	var filtered := SensorTrack.new()
	filtered.update(hardened, far, 0.0, DT, jam)
	assert_true(filtered.locked and filtered.confidence > jammed.confidence, "a hardened mast filters the noise and holds the lock (%.2f)" % filtered.confidence)


func test_jamming_breaks_missile_locks() -> void:
	var lost_jammed := 0
	var lost_clear := 0
	for k in 8:
		var world := WorldSimulation.new(DT)
		world.add_ship(_ship(&"a", _fitted([&"missile_rack"]), Vector3.ZERO, &"hostile"))
		world.add_ship(_ship(&"b", _no_pd(_fitted([&"jammer"])), Vector3(0, 0, -9000), &"player"))
		world._next_missile_id = 100 * k
		world.launch_missile(&"a", &"b")
		var events := ""
		for i in roundi(30.0 / DT):
			world.step()
			events += "\n".join(world.take_link_events())
			if world.missiles.is_empty():
				break
		if events.contains("jammed"):
			lost_jammed += 1
		var calm := WorldSimulation.new(DT)
		calm.add_ship(_ship(&"a", _fitted([&"missile_rack"]), Vector3.ZERO, &"hostile"))
		calm.add_ship(_ship(&"b", _no_pd(_fitted([])), Vector3(0, 0, -9000), &"player"))
		calm._next_missile_id = 100 * k
		calm.launch_missile(&"a", &"b")
		var calm_events := ""
		for i in roundi(30.0 / DT):
			calm.step()
			calm_events += "\n".join(calm.take_link_events())
			if calm.missiles.is_empty():
				break
		if calm_events.contains("jammed"):
			lost_clear += 1
	print("    measured: missiles losing lock at 9 km — %d/8 against a jammer, %d/8 without" % [lost_jammed, lost_clear])
	assert_true(lost_jammed >= 2 and lost_jammed <= 7 and lost_clear == 0,
		"jamming breaks some locks beyond burn-through, not all (%d/8), none without (%d/8)" % [lost_jammed, lost_clear])


func test_an_ew_drone_covers_its_carrier() -> void:
	var world := WorldSimulation.new(DT)
	var carrier := _ship(&"c", _fitted([&"ew_drone_rack"]), Vector3.ZERO, &"player")
	world.add_ship(carrier)
	var wing := AirWing.for_ship(carrier)
	world.wings.append(wing)
	assert_near(world.jamming_of(carrier), 0.0, 1e-6, "docked: no cover")
	wing.launch_all(world)
	var drone: ShipState = null
	for c in wing.flying():
		var s := world.get_ship(c.id)
		if s != null and s.config.jam_strength > 0.0:
			drone = s
	assert_true(drone != null and drone.config.jam_strength > 0.0, "the EW drone is out")
	if drone == null:
		return
	drone.position = carrier.position + Vector3(0, 0, -1000)
	assert_true(world.jamming_of(carrier) > 0.5, "within 3 km it jams for the carrier (%.1f)" % world.jamming_of(carrier))
	drone.position = carrier.position + Vector3(0, 0, -5000)
	assert_near(world.jamming_of(carrier), 0.0, 1e-6, "5 km off: no cover")


func test_policy_auto_countermeasures() -> void:
	# Play-test: "flares and countermeasures should auto deploy once armed":
	# on in every preset, Hold included (flares only defend).
	for name in ShipPolicy.PRESETS:
		assert_true(ShipPolicy.preset(name).cm_auto, "%s fires flares on its own" % name)
	var p := ShipPolicy.preset("Standard")
	assert_true(p.cm_due(3.0) and not p.cm_due(8.0) and not p.cm_due(-1.0), "inside the lead time only (%.0f s)" % p.cm_lead_s)
	var q := ShipPolicy.from_dict(p.to_dict())
	assert_true(q.cm_auto == p.cm_auto and q.cm_lead_s == p.cm_lead_s, "saved and loaded")
	var old := p.to_dict()
	old.erase("cm_auto")
	old.erase("cm_lead_s")
	old["preset_name"] = "Defensive"
	assert_true(ShipPolicy.from_dict(old).cm_auto, "a vessel saved before Milestone 11 takes its preset's (additive, no migration)")
	assert_true(EnemyFactory.policy(4, 0).cm_auto, "enemies fire flares")
	var d4 := EnemyFactory.design(4, BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray()), _catalog())
	assert_true(d4.equipment.any(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == &"flare_launcher"), "from mission 3 enemies carry flares")


func test_flares_restock_at_the_yard() -> void:
	var p := PlayerProfile.new(5)
	var v := p.ensure_vessel(_fitted([&"flare_launcher"]))
	var launcher := ""
	for e in v.blueprint.equipment:
		if e.def_id == &"flare_launcher":
			launcher = e.id
	v.condition["missiles_used"] = {launcher: 9}
	var need := ServiceYard.missile_needs(v, _catalog())
	assert_true(need.count == 9 and need.credits == 9 * ServiceYard.FLARE_CREDITS, "9 flares to restock for %d cr (%s)" % [9 * ServiceYard.FLARE_CREDITS, need])
