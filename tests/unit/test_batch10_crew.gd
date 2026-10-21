extends TestCase
## Measures: play-test batch 10 — crew under fire. With a workshop aboard,
## crew in a damaged room patch what is damaged in it first, where they
## stand, and no damage-control team is sent to it; foam bottles work
## without power and are per sortie; boarding takes half the time.


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _systems(workshop: bool) -> ShipSystems:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	if workshop:
		(bp.find("r9") as ShipBlueprint.PlacedRoom).def_id = &"workshop"
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	return ShipSystems.create(bp, grid, stats, stats.to_ship_config("c"))


## A damaged internal system in a room with fit crew in it: [system, room].
func _damaged_with_crew(s: ShipSystems) -> Array:
	for e in s.equipment:
		if e.def.is_external():
			continue
		var room: int = s.grid.room_at.get(s.blueprint.equipment[e.index].cell, -1)
		if room >= 0 and s.crew.in_room(room, true).size() > 0:
			e.hp = 0.3 * e.max_hp
			return [e, room]
	return []


func test_crew_patch_their_own_room_first() -> void:
	var s := _systems(true)
	var found := _damaged_with_crew(s)
	assert_true(not found.is_empty(), "a damaged system with crew beside it")
	if found.is_empty():
		return
	var e: ShipSystems.EquipmentState = found[0]
	var room: int = found[1]
	var hands := s.crew.in_room(room, true).size()
	s._advance_in_place_repairs(0.1)
	assert_true(int(s.in_place_repairs.get(e.id, 0)) == hands, "every fit hand in %s on it (%d)" % [s.blueprint.rooms[room].id, hands])
	assert_true(s.field_repair_target() != e, "no damage-control team sent to it")
	var t := 0.0
	while e.hp < ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp - 1e-6 and t < 600.0:
		s._advance_in_place_repairs(0.5)
		t += 0.5
	print("    measured: %s %s 30 %% → %d %% in %.0f s by %d crew in %s (workshop bonus %.2f)" % [e.def.display_name, e.id,
		roundi(100.0 * e.hp / e.max_hp), t, hands, s.blueprint.rooms[room].id, s.room_bonus(&"workshop")])
	assert_near(e.hp, ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp, 1e-6, "patched to the field limit, no further (hp)")
	# No workshop aboard: nothing.
	var bare := _systems(false)
	var f := _damaged_with_crew(bare)
	bare._advance_in_place_repairs(10.0)
	assert_near((f[0] as ShipSystems.EquipmentState).hp, 0.3 * (f[0] as ShipSystems.EquipmentState).max_hp, 1e-9, "no workshop: no patching (hp)")


func test_foam_needs_no_power_and_is_per_sortie() -> void:
	var s := _systems(false)
	var room := -1
	for i in s.blueprint.rooms.size():
		if s.room_role(i) == &"engineering":
			room = i
	s.rooms[room].powered = false
	s.fires[room] = {"burn_s": 0.0, "smoulder_s": 0.0}
	s._advance_fires(ShipSystems.FOAM_DELAY_S + 0.1)
	print("    measured: unpowered %s — fire %s, %d charge(s) left; saved condition has foam: %s" % [s.blueprint.rooms[room].id,
		"burning" if s.fires.has(room) else "out", s.foam_left(room), s.condition().has("foam_used")])
	assert_true(not s.fires.has(room) and s.foam_left(room) == ShipSystems.FOAM_CHARGES - 1, "unpowered: foamed all the same")
	assert_true(not s.condition().has("foam_used"), "not carried into the next sortie")
	var old := s.condition()
	old["foam_used"] = {s.blueprint.rooms[room].id: ShipSystems.FOAM_CHARGES}
	var next := _systems(false)
	next.apply_condition(old)
	assert_true(next.foam_left(room) == ShipSystems.FOAM_CHARGES, "an older save's used charges: full again")


func test_boarding_takes_half_the_time() -> void:
	print("    measured: crossing %.1f s, a locked hatch %.0f s, a room %.1f s (crew %.1f s), fight rate %.2f" % [BoardingAction.GANGWAY_CROSS_S,
		BoardingAction.HATCH_CUT_S, BoardingAction.BOARDER_TRANSIT_S, CrewRoster.ROOM_TRANSIT_S, BoardingAction.KILL_RATE])
	assert_near(BoardingAction.GANGWAY_CROSS_S, 2.5, 1e-9, "crossing (s)")
	assert_near(BoardingAction.HATCH_CUT_S, 10.0, 1e-9, "cutting a hatch (s)")
	assert_near(BoardingAction.BOARDER_TRANSIT_S, CrewRoster.ROOM_TRANSIT_S * 0.5, 1e-9, "a room (s)")
	assert_near(BoardingAction.KILL_RATE, 0.16, 1e-9, "fights twice as fast")
	assert_near(Docking.COLLAR_SEAL_S, 5.0, 1e-9, "the gangway mates (s)")
	assert_near(Docking.HULL_CUT_S, 22.5, 1e-9, "the gangway cuts in (s)")
