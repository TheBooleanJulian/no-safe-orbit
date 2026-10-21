extends TestCase
## Measures: enemies field the newer kit (after Milestone 15) — pulse lasers,
## laser and repair drones, Lancer laser fighters — each from its mission,
## never before it (by the mission a ship is fitted as), always in a valid
## design whose reactors carry a laser's draw; the same mission gives the
## same ships.

const KIT := {&"laser_turret": EnemyFactory.LASER_FROM_MISSION, &"laser_drone_rack": EnemyFactory.LASER_DRONE_FROM_MISSION,
	&"repair_drone_rack": EnemyFactory.REPAIR_DRONE_FROM_MISSION, &"laser_fighter_bay": EnemyFactory.LASER_FIGHTER_FROM_MISSION}


func test_enemies_field_the_newer_kit_from_their_missions() -> void:
	var cat := ConstructionCatalog.default_catalog()
	var tpl := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var first := {}
	for m in range(1, 13):
		for v in 3:
			var bp := EnemyFactory.design(m, tpl, cat, v)
			assert_true(not ShipValidator.validate(bp, cat).has_errors(), "m%d v%d is valid" % [m, v])
			var fitted := EnemyFactory.kit_mission(m, v)
			for e in bp.equipment:
				if KIT.has(e.def_id):
					assert_true(fitted >= int(KIT[e.def_id]), "m%d v%d: %s only from mission %d (fitted as %d)" % [m, v, e.def_id, KIT[e.def_id], fitted])
					if not first.has(e.def_id):
						first[e.def_id] = "m%d v%d" % [m, v]
					if e.def_id == &"laser_turret":
						var stats := ShipStats.compute(bp, ShipGrid.build(bp, cat))
						assert_true(stats.power_draw_kw <= stats.power_generation_kw, "m%d v%d: the reactors carry the laser (%.0f / %.0f kW)" % [
							m, v, stats.power_draw_kw, stats.power_generation_kw])
	print("    measured: first seen (missions 1–12, three ships each) — %s" % first)
	for id: StringName in KIT:
		assert_true(first.has(id), "%s turns up by mission 12" % id)
	var a := BlueprintIO.to_json(EnemyFactory.design(11, tpl, cat, 2))
	assert_true(a == BlueprintIO.to_json(EnemyFactory.design(11, tpl, cat, 2)), "the same mission, the same ship")
