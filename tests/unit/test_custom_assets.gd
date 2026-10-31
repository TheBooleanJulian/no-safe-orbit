extends TestCase
## Measures: your own sounds, textures and models (2026-10-31) — a file in
## data/custom/ takes its slot over; with none, nothing changes. The
## fixtures (tests/fixtures/custom/) are Godot text resources, which load
## without an import.

const CUSTOM_FIXTURES := "res://tests/fixtures/custom/"


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _use(dir: String) -> void:
	CustomAssets.dir = dir
	CustomAssets.reset()


func _audio() -> ShipAudio:
	var a := ShipAudio.new()
	a._ready()
	return a


func _model() -> Array:
	var bp := BlueprintIO.load_file("res://data/blueprints/frigate_mk1.json", PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	return [bp, ShipModelBuilder.build(bp, grid, grid.hull_bounds_m().get_center())]


func _first(bp: ShipBlueprint, def_id: StringName) -> String:
	for e in bp.equipment:
		if e.def_id == def_id:
			return e.id
	return ""


func test_with_no_files_nothing_changes() -> void:
	_use("res://tests/fixtures/custom_none/")
	var a := _audio()
	assert_true(a.custom.is_empty() and a.sampled.has("gun"), "the game's own samples play (custom: %s)" % a.custom)
	a.free()
	assert_true(CustomAssets.texture("hull_plates") == null and ShipModelBuilder._plates() is ImageTexture, "the generated plating")
	var built := _model()
	var leg: Node3D = (built[1] as ShipModelBuilder.Model).parts[_first(built[0], &"landing_leg")]
	assert_true(leg.get_node_or_null("CustomModel") == null, "the built leg")
	(built[1] as ShipModelBuilder.Model).root.free()
	_use("res://data/custom/")


func test_your_files_take_over() -> void:
	_use(CUSTOM_FIXTURES)
	var a := _audio()
	assert_true(a.custom.has("gun") and not a.custom.has("hit") and a._variants["gun"][0] == CustomAssets.audio("gun")[0],
		"your gun sound plays; the rest are the game's (custom: %s)" % a.custom)
	a.free()
	assert_true(ShipModelBuilder._plates() == CustomAssets.texture("hull_plates") and ShipModelBuilder._plates() != null, "your hull plating")
	var built := _model()
	var model: ShipModelBuilder.Model = built[1]
	var leg: Node3D = model.parts[_first(built[0], &"landing_leg")]
	assert_true(leg.get_node_or_null("CustomModel") != null, "your landing leg")
	assert_true(not leg.get_children().any(func(n: Node) -> bool: return n is MeshInstance3D and n.name != "CustomModel"),
		"in place of the built one's pieces")
	var gun: Node3D = model.parts[_first(built[0], &"autocannon")]
	var pivot := gun.get_node_or_null("TurretPivot")
	assert_true(pivot != null and pivot.get_node_or_null("CustomTurret") != null and model.turrets.any(func(t: Dictionary) -> bool: return t.pivot == pivot),
		"your turret head, on the pivot the view still aims")
	model.root.free()
	_use("res://data/custom/")


func test_every_sound_slot_is_one_the_game_plays() -> void:
	_use("res://tests/fixtures/custom_none/")
	var a := _audio()
	for row: Array in CustomAssets.AUDIO_SLOTS:
		var slot: String = row[0]
		var known := a.has_sound(slot) or (slot.begins_with("alarm_") and ShipAudio.ALARMS.has(StringName(slot.trim_prefix("alarm_")))) \
			or slot in ["engine_loop", "rcs_loop", "ambience_loop", "jump_spool"]
		assert_true(known, "%s is played" % slot)
	assert_true(CustomAssets.AUDIO_SLOTS.size() == 19 and ShipAudio.ALARMS.size() == 5, "19 slots: 10 one-shots, 5 alarms, 3 loops and the jump")
	a.free()
	_use("res://data/custom/")
