extends SceneTree
## Renders the README's sky screenshots into docs/screenshots/sky_*.jpg, on
## a scratch profile (never the player's save), HUD hidden. Needs a display
## (it briefly opens a window):
##   godot --path . -s res://tools/capture_sky.gd
## The far body is framed by a separate camera placed 20 km towards it
## (clear of every ship); night scenes rebuild the celestial frame at local
## midnight on chosen dates (the scenario date's Moon, a full Moon, a full
## Earth).

const OUT := "res://docs/screenshots"

var _main: Main
var _cam: Camera3D
var _aim := Vector3.ZERO
var _fov := 60.0


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_viewport().get_texture().get_image().save_jpg(ProjectSettings.globalize_path("%s/%s.jpg" % [OUT, name]), 0.86)
	print("shot ", name)


func _sim(seconds: float, actions: Array[String] = []) -> void:
	for a in actions:
		Input.action_press(a)
	var stop := _main.world.sim_time + seconds
	while _main.world.sim_time < stop:
		await process_frame
	for a in actions:
		Input.action_release(a)


## Aim the separate camera after Main has placed its own (frame_pre_draw).
func _pre_draw() -> void:
	if _main == null or _cam == null or _aim == Vector3.ZERO:
		return
	var dir := _aim.normalized()
	_cam.fov = _fov
	_cam.global_position = dir * 20_000.0
	_cam.look_at(_cam.global_position + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	_cam.make_current()
	# What Main does for its own camera: the sky's pixel size follows the fov.
	(_main.sky.environment.sky.sky_material as ShaderMaterial).set_shader_parameter("pixel_angle", deg_to_rad(_fov) / root.size.y)


## Boot the flight scene at `location`; with an `epoch`, rebuild the sky at
## local midnight on that date (the ship in the planet's shadow).
func _boot(location: String, epoch: String = "") -> void:
	if _main != null:
		_main.queue_free()
		await process_frame
	_aim = Vector3.ZERO
	Main.profile = null
	Main.get_profile().location = location
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await process_frame
	if epoch != "":
		_main.celestial = CelestialFrame.for_scenario(CelestialFrame.julian_date_from_iso(epoch), 180.0, _main.location.body)
		_main.hud.celestial = _main.celestial
		_main.stars.build(_main.celestial)
	await _sim(0.5)
	_main.hud.visible = false
	_cam = Camera3D.new()
	_cam.far = 1.0e6
	_main.add_child(_cam)


## Frame the other body in the sky at `fov` degrees.
func _frame_far_body(fov: float) -> void:
	_fov = fov
	_aim = _main.sky.sky_body_center


func _chase_view() -> void:
	_aim = Vector3.ZERO
	_main.camera.make_current()


func _run() -> void:
	PlayerProfile.path = "user://sky_capture_profile.json"
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	root.size = Vector2i(1600, 900)
	# The scenario date (2026-10-19 12:00 UTC): a waxing gibbous Moon seen
	# from Earth orbit, at the deepest in-game zoom (3°).
	await _boot("earth")
	_frame_far_body(3.0)
	await _shot("sky_moon_from_earth_orbit")
	# The same moment from lunar orbit: Earth over the limb, then zoomed.
	await _boot("moon")
	_frame_far_body(50.0)
	await _shot("sky_earthrise")
	_frame_far_body(3.0)
	await _shot("sky_earth_from_lunar_orbit")
	# Full Moon (2026-10-26) at midnight: moonlight on Earth's night side and
	# the hull.
	await _boot("earth", "2026-10-26T04:12:00")
	_chase_view()
	await _sim(2.4, ["pitch_down"])
	await _sim(1.0)
	await _shot("sky_full_moon_night")
	# New Moon (2026-10-10) is full Earth from the Moon: earthlight on the
	# lunar night side.
	await _boot("moon", "2026-10-10T15:50:00")
	_chase_view()
	await _sim(2.4, ["pitch_down"])
	await _sim(1.0)
	await _shot("sky_full_earth_night")
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	quit()
