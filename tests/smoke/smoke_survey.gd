extends SceneTree
## Milestone 14, end to end through the real scenes:
##   godot --headless --path . -s res://tests/smoke/smoke_survey.gd
## A survey of the ISS from Earth orbit: it is there, 3 km ahead, in its real
## orbit; close in and match speed → surveyed, paid, in the codex; B home
## clears the survey. Then Voyager 1: the Sun is the central body, its light
## comes from the right way, nothing breaks over time far out, the HUD says
## how far; Backspace goes back to an ordinary sortie at Earth.
##
## Scaffolding, stated plainly: the ship is placed alongside the ISS rather
## than flown there (rendezvous and the match-velocity assist have their own
## tests), and the Voyager survey skips the shipyard's tankage check.

const WATCHDOG_S := 180.0

var _failures := PackedStringArray()


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("smoke_survey: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
		quit(2))
	_run.call_deferred()


func _check(condition: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if condition else "FAIL", what])
	if not condition:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _launch() -> Main:
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(3)
	return main


func _run() -> void:
	print("== smoke_survey")
	PlayerProfile.path = "user://smoke_survey_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	Main.launch_blueprint = null
	root.size = Vector2i(1600, 900)
	var profile := Main.get_profile()
	profile.survey_target = "iss"

	# 1. The ISS from Earth orbit.
	var main := await _launch()
	var player := main.world.get_ship(Main.PLAYER_ID)
	var iss := main.world.get_ship(Main.ARTIFACT_ID)
	_check(main.artifact != null and iss != null and main.encounter.contacts.is_empty(),
		"a survey sortie: the ISS is there and no hostile traffic")
	_check(iss != null and absf(iss.position.distance_to(player.position) - Artifact.START_BEHIND_M) < 50.0,
		"it is %.2f km ahead" % (iss.position.distance_to(player.position) / 1000.0 if iss != null else -1.0))
	var r := main.world.pci_position(player.position).length()
	_check(absf(r - 6_371_000.0 - 427_000.0) < 10_000.0, "in its real orbit, %.0f km up" % ((r - 6_371_000.0) / 1000.0))
	await _frames(2)
	_check(main.hud._target_heading.text.contains("SURVEY") and main.hud.target_label.text.contains("RANGE"),
		"the target card is the survey card (%s)" % main.hud._target_heading.text)
	var credits := profile.credits
	Engine.time_scale = 8.0
	var t_far := main.world.sim_time
	while main.world.sim_time - t_far < 6.0:
		await process_frame
	Engine.time_scale = 1.0
	_check(main.survey_progress == 0.0, "from 3 km out the survey does not start")
	player.position = iss.position + Vector3(0, 0, 300)
	player.velocity = iss.velocity
	Engine.time_scale = 8.0
	var t0 := main.world.sim_time
	while not main.survey_done and main.world.sim_time - t0 < 60.0:
		await process_frame
	Engine.time_scale = 1.0
	_check(main.survey_done and profile.codex.has("iss") and profile.credits == credits + Artifact.by_id("iss").survey_credits,
		"close and slow for %.0f s: surveyed, %d credits, in the codex" % [Artifact.SURVEY_S, Artifact.by_id("iss").survey_credits])
	Engine.time_scale = 8.0
	Input.action_press("open_shipyard")
	for i in 900:
		if current_scene is Shipyard:
			break
		await process_frame
	Input.action_release("open_shipyard")
	Engine.time_scale = 1.0
	await _frames(3)
	_check(current_scene is Shipyard and profile.survey_target == "", "B jumps home; the next sortie is an ordinary one")
	if current_scene is Shipyard:
		var yard := current_scene as Shipyard
		yard.show_section("MAP")
		await _frames(2)
		_check(yard._artifact_box.get_child_count() == Artifact.all().size() + 1, "the MAP lists every artifact")
		current_scene.queue_free()
		await _frames(2)

	# 2. Voyager 1, about the Sun.
	profile.survey_target = "voyager1"
	main = await _launch()
	player = main.world.get_ship(Main.PLAYER_ID)
	var v1 := main.world.get_ship(Main.ARTIFACT_ID)
	_check(main.world.body.is_star and v1 != null and main.location.station_name == "Earth Shipyard",
		"deep space: the Sun at the centre, Voyager 1 alongside, home is still Earth Shipyard")
	var pos := main.world.pci_position(player.position)
	var sun_dir := main.celestial.sun_direction_pci(main.world.sim_time)
	_check(sun_dir.dot(pos.times(-1.0).normalized().to_vector3()) > 0.99999, "sunlight comes from the Sun, at the centre")
	_check(main.sun.light_energy > 0.5 * Main.SUN_ENERGY, "and nothing shades it (light %.2f)" % main.sun.light_energy)
	Engine.time_scale = 8.0
	t0 = main.world.sim_time
	while main.world.sim_time - t0 < 20.0:
		await process_frame
	Engine.time_scale = 1.0
	var p2 := main.world.pci_position(player.position)
	_check(player.is_active() and is_finite(p2.x) and is_finite(p2.y) and is_finite(p2.z) and not main.hud.debrief.visible,
		"20 s out at %.1f AU: still flying, finite" % (p2.length() / CelestialFrame.AU_M))
	_check(main.hud.target_label.text.contains("AU from the Sun"), "the survey card says how far from the Sun")
	var ev := InputEventAction.new()
	ev.action = "restart_scenario"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(8)
	var back := current_scene as Main
	_check(back != null and back.artifact == null and not back.world.body.is_star and not back.encounter.contacts.is_empty(),
		"Backspace: an ordinary sortie at Earth again")
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + PlayerProfile.BACKUP_SUFFIX))
	print("smoke_survey: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
