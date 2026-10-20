extends SceneTree
## Renders the README's screenshots into docs/screenshots/*.jpg, on a
## scratch profile (never the player's save). Needs a display (it briefly
## opens a window):
##   godot --path . -s res://tools/capture_readme.gd

const OUT := "res://docs/screenshots"
var main: Main


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	img.save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [OUT, name]), 0.86)
	print("shot ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _sim(seconds: float) -> void:
	var stop := main.world.sim_time + seconds
	while main.world.sim_time < stop:
		await process_frame


func _run() -> void:
	PlayerProfile.path = "user://readme_capture_profile.json"
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	Main.profile = null
	var cat := ConstructionCatalog.default_catalog()
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	EnemyFactory._fit_launcher(bp, cat, &"saturation_pod", rng)
	EnemyFactory._fit_launcher(bp, cat, &"missile_rack", rng)
	Main.launch_blueprint = bp
	root.size = Vector2i(1600, 900)
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(30)
	await _shot("flight")

	# Gunnery: the cursor on the lead, firing, until a hit opens the hit cam.
	var player := main.world.get_ship(Main.PLAYER_ID)
	var target := main.world.get_ship(Main.TARGET_ID)
	Input.action_press("fire")
	var t0 := main.world.sim_time
	while target.hits_taken < 3 and main.world.sim_time - t0 < 15.0:
		main.aim_cursor_at_lead()
		await process_frame
	Input.action_release("fire")
	await _frames(20)
	await _shot("gunnery")

	# The crew tab.
	main.hud.overview.toggle()
	main.hud.overview.show_tab("CREW")
	await _frames(10)
	await _shot("crew")
	main.hud.overview.show_tab("DAMAGE")
	await _frames(10)
	await _shot("damage_control")
	main.hud.overview.toggle()

	# A missile salvo, then the warheads arriving.
	while not main.track.locked:
		await process_frame
	main.fire_missile()
	await _sim(4.0)
	await _shot("missile_salvo")
	await _sim(6.0)

	# The debrief.
	main.close_sortie()
	main.hud.debrief.show_debrief(main.get_profile().last_debrief, "[B] back to Earth Shipyard")
	await _frames(10)
	await _shot("debrief")

	# The shipyard.
	main.hud.debrief.visible = false
	Main.launch_blueprint = null
	main.queue_free()
	await _frames(2)
	var p := Main.get_profile()
	p.inventory["saturation_pod"] = 1
	p.inventory["missile_rack"] = 1
	change_scene_to_file("res://scenes/shipyard/shipyard.tscn")
	await _frames(30)
	var yard := current_scene as Shipyard
	yard.debrief.hide_debrief()
	yard.editor.revalidate()
	await _frames(30)
	await _shot("shipyard")
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	quit()
