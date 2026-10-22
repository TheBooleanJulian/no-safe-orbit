extends SceneTree
## Milestone 16, end to end through the real flight scene:
##   godot --headless --path . -s res://tests/smoke/smoke_solar_system.gd
## A sortie at each new location: the right central body, the start orbit
## at its altitude (inclined 20° at Saturn), the ship and the local traffic
## still flying after 12 s (no one starts inside Phobos or under Jupiter's
## entry interface), ground to land on at Mercury, Phobos and Deimos, Mars
## in Phobos's sky and Phobos in Mars's, rings drawn at Saturn.
##
## Scaffolding, stated plainly: the profile is placed at each station rather
## than flown there (jumps and charts have their own tests).

const WATCHDOG_S := 600.0
const NEW := ["mercury", "venus", "phobos", "deimos", "jupiter", "saturn", "uranus", "neptune"]

var _failures := PackedStringArray()


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("smoke_solar_system: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
		quit(2))
	_run.call_deferred()


func _check(condition: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if condition else "FAIL", what])
	if not condition:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	print("== smoke_solar_system")
	PlayerProfile.path = "user://smoke_solar_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	Main.launch_blueprint = null
	root.size = Vector2i(1600, 900)
	var profile := Main.get_profile()
	for id in NEW:
		profile.known_locations.append(id)
	profile.known_locations.append("mars")
	for id: String in NEW + ["mars"]:
		profile.location = id
		var loc := Location.by_id(id)
		var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		current_scene = main
		await _frames(3)
		var player := main.world.get_ship(Main.PLAYER_ID)
		var alt := main.world.altitude_of(player)
		var r := main.world.pci_position(player.position)
		var v := main.world.pci_velocity(player.velocity)
		var h := r.cross(v).normalized().to_vector3()
		var incl := rad_to_deg(h.angle_to(Vector3(-1, 0, 0)))
		Engine.time_scale = 12.0
		var t0 := main.world.sim_time
		while main.world.sim_time - t0 < 12.0:
			await process_frame
		Engine.time_scale = 1.0
		var flying := main.encounter.live(main.world).size()
		var all := main.encounter.contacts.size()
		var mat: ShaderMaterial = main.sky._material
		var line := "%s: %s, %.1f km up, inclined %.1f°; after 12 s the ship %s, %d of %d contacts flying" % [id, main.world.body.display_name,
			alt / 1000.0, incl, "flies" if player.is_active() else "is LOST", flying, all]
		_check(main.world.body == loc.body and absf(alt - loc.start_altitude_m) < maxf(loc.start_altitude_m * 0.02, 200.0)
			and absf(incl - loc.start_inclination_deg) < 0.5 and player.is_active() and flying == all and all > 0, line)
		match id:
			"mercury", "phobos", "deimos":
				_check(main.world.terrain != null, "%s: ground to land on" % id)
			"saturn":
				_check(float(mat.get_shader_parameter("ring_outer")) > 1.0e8, "Saturn: rings in the sky")
		if id in ["phobos", "deimos"]:
			_check(main.sky.sky_body != null and main.sky.sky_body.display_name == "Mars", "%s: Mars in the sky" % id)
		if id == "mars":
			_check(main.sky.sky_body != null and main.sky.sky_body.display_name == "Phobos", "Mars: Phobos in the sky")
		main.close_sortie()
		main.queue_free()
		await _frames(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + PlayerProfile.BACKUP_SUFFIX))
	print("smoke_solar_system: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
