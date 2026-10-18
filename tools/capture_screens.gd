extends SceneTree
## Renders scripted flight moments to PNG for visual review (needs a real
## renderer, e.g. under Xvfb):
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

	# Burn forward, then strafe right: velocity (prograde) now differs from heading.
	Input.action_press("thrust_forward")
	await _hold(main, [], 2.0)
	await _shot("02a_main_engine_burn")
	Input.action_release("thrust_forward")
	await _hold(main, ["strafe_right", "thrust_up"], 2.0)
	await _shot("02_prograde_vs_heading")

	# Yaw hard right until the target falls off-screen → edge arrow.
	await _hold(main, ["yaw_right"], 3.5)
	await _hold(main, [], 1.0)
	await _shot("03_target_offscreen")
	quit(0)
