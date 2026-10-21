extends TestCase
## Measures: Milestone 15 — repair and salvage drones. A repair drone flies
## to a damaged system outside its carrier's hull and patches it to the
## field-repair limit (never past it, never a destroyed one); a salvage
## drone carries the salvage beacon — G reaches a wreck 8 km off instead of
## 2 km while one is on the wing, and it cuts nothing off by itself (play-
## test batch 9); with nothing to do they escort; the racks are in the
## catalog under Drones and their roles are explained.

const DT := 1.0 / 60.0


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


## The stock frigate with its recon drone rack swapped for `rack`.
func _carrier(id: StringName, pos: Vector3, side: StringName, rack: StringName = &"") -> ShipState:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	for e in bp.equipment:
		if e.def_id == &"drone_rack" and rack != &"":
			e.def_id = rack
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg, pos)
	s.side = side
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _worker(wing: AirWing, role: StringName) -> AirWing.Craft:
	for c in wing.crafts:
		if c.config.craft_role == role:
			return c
	return null


func test_a_repair_drone_patches_systems_outside_the_hull() -> void:
	var world := WorldSimulation.new(DT)
	var me := _carrier(&"me", Vector3.ZERO, &"player", &"repair_drone_rack")
	world.add_ship(me)
	var wing := AirWing.for_ship(me)
	world.wings.append(wing)
	var drone := _worker(wing, &"repair")
	assert_true(drone != null and drone.is_drone() and drone.is_worker(), "the rack carries a repair drone (%s)" % (drone.label if drone != null else "none"))
	if drone == null:
		return
	# Two damaged systems outside the hull and one destroyed; the drone isn't one of them.
	var hurt: Array[ShipSystems.EquipmentState] = []
	var gone: ShipSystems.EquipmentState = null
	for e in me.systems.equipment:
		if not e.def.is_external() or e.id == drone.rack_id or e.def.kind == EquipmentDefinition.Kind.CRAFT_MOUNT:
			continue
		if gone == null and e.def.kind == EquipmentDefinition.Kind.SENSOR:
			e.hp = 0.0
			gone = e
		elif hurt.size() < 2 and e.def.kind in [EquipmentDefinition.Kind.CANNON, EquipmentDefinition.Kind.RADIATOR]:
			e.hp = 0.2 * e.max_hp
			hurt.append(e)
	assert_true(hurt.size() == 2 and gone != null, "set up: two systems at 20 %, the mast destroyed")
	assert_true(wing.launch(world, drone) == "", "launched")
	var t := 0.0
	while t < 240.0 and not hurt.all(func(e: ShipSystems.EquipmentState) -> bool: return e.hp >= ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp - 1e-3):
		world.step()
		t += DT
	var patched := "\n".join(wing.log).count("patched")
	print("    measured: both patched to %d %% / %d %% in %.0f s (%.1f hp/s on station); the mast stays at %.0f hp; log: %d patched; crew repair %s" % [
		roundi(100.0 * hurt[0].hp / hurt[0].max_hp), roundi(100.0 * hurt[1].hp / hurt[1].max_hp), t, AirWing.REPAIR_HP_PER_S, gone.hp,
		patched, "never started" if me.systems.repair_task == null else "started"])
	for e in hurt:
		assert_near(e.hp, ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp, 1e-3, "%s patched to the field limit, no further (hp)" % e.id)
	assert_true(gone.destroyed(), "a destroyed system needs the yard")
	assert_true(patched == 2 and me.systems.repair_task == null, "the drone did it, not the crew")
	# Nothing left to patch: it escorts.
	for i in 240:
		world.step()
	assert_true(drone.status == AirWing.Status.FLYING and drone.override_reason == "", "no work: it flies its escort slot")


func test_a_salvage_drone_carries_the_beacon_further() -> void:
	var world := WorldSimulation.new(DT)
	var me := _carrier(&"me", Vector3.ZERO, &"player", &"salvage_drone_rack")
	var wreck := _carrier(&"wreck", Vector3(0, 0, -5000), &"hostile")
	world.add_ship(me)
	world.add_ship(wreck)
	var wing := AirWing.for_ship(me)
	wing.target_id = &"wreck"
	world.wings.append(wing)
	var drone := _worker(wing, &"salvage")
	assert_true(drone != null, "the rack carries a salvage drone")
	if drone == null:
		return
	for e in wreck.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.REACTOR:
			e.hp = 0.0
	wreck.systems.solve_power()
	wreck.systems._state_changed()
	assert_true(wreck.systems.is_disabled(), "the hostile is disabled (%s)" % wreck.systems.disabled_reason())
	var plain := AirWing.for_ship(_carrier(&"plain", Vector3.ZERO, &"player"))
	var with_drone := Salvage.block_reason(me, wreck, wing.beacon_reach_m())
	var without := Salvage.block_reason(me, wreck, plain.beacon_reach_m())
	print("    measured: beacon reach %.0f km with a salvage drone, %.0f km without; at 5 km: \"%s\" / \"%s\"" % [
		wing.beacon_reach_m() / 1000.0, plain.beacon_reach_m() / 1000.0, with_drone, without])
	assert_true(with_drone == "" and without.contains("salvage drone"), "5 km off: only with the drone (and the hint says so)")
	wreck.position = Vector3(0, 0, -9000)
	assert_true(Salvage.block_reason(me, wreck, wing.beacon_reach_m()).contains("close to"), "not past 8 km")
	# Out, it cuts nothing off by itself: it escorts.
	var intact := wreck.systems.intact_fraction()
	wing.auto_relaunch = false
	assert_true(wing.launch(world, drone) == "", "launched")
	for i in 60 * 60:
		world.step()
	print("    measured: after 60 s out, the wreck %d %% → %d %% intact; drone: %s" % [roundi(intact * 100.0),
		roundi(wreck.systems.intact_fraction() * 100.0), drone.override_reason if drone.override_reason != "" else "escorting"])
	assert_near(wreck.systems.intact_fraction(), intact, 1e-9, "nothing cut off (intact fraction)")
	assert_true(drone.status == AirWing.Status.FLYING and wing.beacon_reach_m() == AirWing.SALVAGE_RANGE_M, "out, it still carries the beacon")
	drone.status = AirWing.Status.LOST
	assert_near(wing.beacon_reach_m(), Salvage.BEACON_RANGE_M, 1e-6, "lost: back to the 2 km beacon (m)")


func test_drone_racks_in_the_catalog() -> void:
	var cat := _catalog()
	for id: StringName in [&"repair_drone_rack", &"salvage_drone_rack"]:
		var def: EquipmentDefinition = cat.equipment.get(id)
		assert_true(def != null and def.validate().is_empty() and def.craft != null and def.craft.cannon == null, "%s: an unarmed drone rack" % id)
		if def != null:
			assert_true(Shipyard.palette_place("equipment", def) == ["Hangars & craft", "Drones"], "%s under Drones" % id)
			assert_true(str(CraftAI.ROLE_HELP.get(def.craft.craft_role, "")) != "", "its role is explained")
			assert_true(def.rarity != Rarity.Tier.COMMON, "rarer than common: loot and the quartermaster")
