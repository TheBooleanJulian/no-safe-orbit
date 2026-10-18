extends SceneTree
## Renders scripted flight moments to PNG for visual review. Needs a real
## renderer (a desktop session, or Xvfb on Linux):
##   godot --path . -s res://tools/capture_screens.gd
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
##       -s res://tools/capture_screens.gd
## Output: build/screens/*.png

const OUT_DIR := "res://build/screens"


func _initialize() -> void:
	_run.call_deferred()


func _hold(main: Main, actions: Array[String], sim_seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	var stop := main.world.sim_time + sim_seconds
	while main.world.sim_time < stop:
		await process_frame
	for a in actions:
		Input.action_release(a)


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _hold(main, [], 0.3)
	await _shot("01_start")

	# Burn forward, then strafe: local velocity differs from heading.
	await _hold(main, ["thrust_forward"], 2.0)
	await _shot("02a_main_engine_burn")
	await _hold(main, ["strafe_right", "thrust_up"], 2.0)
	await _shot("02_prograde_vs_heading")

	# Fire a burst at the target: tracers in flight, lead pip, TOF.
	await _hold(main, ["fire"], 1.2)
	await _shot("03_firing")

	# Pitch down towards Earth: surface, terminator side, limb glow.
	await _hold(main, ["pitch_down"], 2.2)
	await _hold(main, [], 1.0)
	await _shot("04_looking_down")

	# Yaw hard right until the target falls off-screen → edge arrow.
	await _hold(main, ["pitch_up"], 2.2)
	await _hold(main, ["yaw_right"], 3.5)
	await _hold(main, [], 1.0)
	await _shot("05_target_offscreen")

	# Kill 130 m/s of orbital speed (scripted, not flown): periapsis drops
	# below the 100 km entry interface → warning and path entry marker.
	var player := main.world.get_ship(Main.PLAYER_ID)
	player.velocity += Vector3(0, 0, 130.0)
	await _hold(main, ["yaw_left"], 3.5)
	await _hold(main, [], 1.0)
	await _shot("06_deorbit_warning")
	quit(0)
