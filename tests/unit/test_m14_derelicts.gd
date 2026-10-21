extends TestCase
## Measures: Milestone 14 (part 2) — wrecks stay in their location's field,
## the newest few are found again, they decay each sortie and break up,
## a rebuilt derelict is wrecked to what was left of it (no power,
## reproducibly), each re-salvage yields half the last; v10 saves load with
## empty fields.


func _cat() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _systems(seed_bp: int = 3) -> ShipSystems:
	var template := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var bp := EnemyFactory.design(4, template, _cat(), seed_bp)
	var grid := ShipGrid.build(bp, _cat())
	var stats := ShipStats.compute(bp, grid)
	return ShipSystems.create(bp, grid, stats, stats.to_ship_config("x"))


func test_the_field_keeps_the_newest_and_finds_them_again() -> void:
	var field := []
	for i in 8:
		DerelictField.record(field, "earth", "Kestrel %d" % i, "frigate_mk1.json", 3, 0, 0.8, 1)
	DerelictField.record(field, "moon", "Merlin", "corvette_mk1.json", 4, 1, 0.5, 0)
	var earth := field.filter(func(d: Dictionary) -> bool: return d.location == "earth")
	assert_true(earth.size() == DerelictField.MAX_PER_LOCATION and str(earth[0].name) == "Kestrel 2", "six per place, the oldest gone")
	var found := DerelictField.at(field, "earth")
	assert_true(found.size() == DerelictField.SPAWN_PER_SORTIE and str(found[0].name) == "Kestrel 7", "a sortie finds the newest two")
	assert_true(DerelictField.at(field, "moon").size() == 1 and DerelictField.at(field, "mars").is_empty(), "each place its own")
	var off := DerelictField.spawn_offset(found[0])
	assert_true(off == DerelictField.spawn_offset(found[0]) and off.length() >= DerelictField.SPAWN_MIN_M - 1.0
		and off.length() <= DerelictField.SPAWN_MAX_M + 1.0, "found where it was left, %.1f km out" % (off.length() / 1000.0))


func test_derelicts_decay_and_break_up() -> void:
	var field := []
	DerelictField.record(field, "earth", "Fresh", "frigate_mk1.json", 3, 0, 0.9, 0)
	DerelictField.record(field, "earth", "Stripped", "frigate_mk1.json", 3, 1, 0.12, 2)
	var sorties := 0
	var gone := PackedStringArray()
	while not field.is_empty() and sorties < 20:
		sorties += 1
		gone.append_array(DerelictField.age_all(field))
	print("    measured: %s" % "; ".join(gone))
	assert_true(gone.size() == 2 and gone[0].contains("Stripped"), "the stripped one breaks up first")
	assert_true(sorties == DerelictField.MAX_AGE, "nothing outlasts %d sorties" % DerelictField.MAX_AGE)
	var one := []
	DerelictField.record(one, "earth", "A", "frigate_mk1.json", 3, 0, 0.8, 0)
	DerelictField.age_all(one)
	assert_near(float(one[0].intact), 0.8 * DerelictField.DECAY, 1e-6, "each sortie it loses 15 % of what is left")


func test_a_rebuilt_derelict_is_wrecked_to_what_was_left() -> void:
	var a := _systems()
	DerelictField.wreck_to(a, 0.4, 77)
	var b := _systems()
	DerelictField.wreck_to(b, 0.4, 77)
	print("    measured: wrecked to %.2f intact (asked 0.40): %s" % [a.intact_fraction(), a.disabled_reason()])
	assert_true(a.intact_fraction() <= 0.401 and a.intact_fraction() > 0.2, "down to what was left")
	assert_true(a.disabled_reason() == "no power", "dead in space: no power")
	assert_true(is_equal_approx(a.intact_fraction(), b.intact_fraction()) and JSON.stringify(a.condition()) == JSON.stringify(b.condition()),
		"the same record wrecks the same way")


func test_each_resalvage_yields_half() -> void:
	var first := DerelictField.resalvage_yield(2000, 4, 0)
	var second := DerelictField.resalvage_yield(2000, 4, 1)
	var third := DerelictField.resalvage_yield(2000, 4, 2)
	print("    measured: scrap %d → %d → %d cr; crates %d → %d → %d" % [first.scrap, second.scrap, third.scrap, first.pulls, second.pulls, third.pulls])
	assert_true(first.scrap == 1000 and second.scrap == 500 and third.scrap == 250, "scrap halves each time")
	assert_true(third.pulls >= 1, "always at least one crate")


func test_schema_11_migration() -> void:
	var path := "user://test_m14d_profile.json"
	for s in ["", ".bak", ".tmp", ".v10"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var p := PlayerProfile.new(5)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	var d := p.to_dict()
	d.schema_version = 10
	d.erase("derelicts")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	assert_true(q.loaded_schema == 10 and q.derelicts.is_empty() and FileAccess.file_exists(path + ".v10"), "a v10 save: no derelicts, original kept")
	DerelictField.record(q.derelicts, "earth", "Kestrel", "frigate_mk1.json", 3, 0, 0.7, 1)
	DerelictField.record(q.derelicts, "nowhere", "Ghost", "frigate_mk1.json", 3, 0, 0.7, 1)
	q.save(path)
	var r := PlayerProfile.load_file(path, PackedStringArray())
	assert_true(r.loaded_schema == PlayerProfile.SCHEMA_VERSION and PlayerProfile.SCHEMA_VERSION >= 11 and r.derelicts.size() == 1
		and str(r.derelicts[0].name) == "Kestrel", "saved; a record for an unknown place is dropped")
	for s in ["", ".bak", ".tmp", ".v10"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
