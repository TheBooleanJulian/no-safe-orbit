extends SceneTree
## End-to-end smoke test of the real main scene, driven through InputMap
## actions exactly as a player would.
##   godot --headless --path . -s res://tests/smoke/smoke_main.gd
## Measures: scene boots; forward thrust key moves the player ship forward;
## assist toggle reaches the simulation and HUD; HUD shows target range.

var _failures := PackedStringArray()


## A script error aborts the coroutine before quit(); never hang the checks.
const WATCHDOG_S := 120.0


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("smoke: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
		quit(2))
	_run.call_deferred()


func _check(condition: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if condition else "FAIL", what])
	if not condition:
		_failures.append(what)


func _run_until_sim_time(main: Main, seconds: float) -> void:
	var stop := main.world.sim_time + seconds
	var guard := 0
	while main.world.sim_time < stop and guard < 100_000:
		await process_frame
		guard += 1


func _run() -> void:
	print("== smoke_main")
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	_check(main.world != null and main.world.has_ship(&"player") and main.world.has_ship(&"target_01"),
		"world spawned player and target")
	_check(main.world.get_ship(&"player").config.display_name == "Frigate Mk I",
		"player flies the Frigate Mk I template compiled from its blueprint")
	var player := main.world.get_ship(&"player")
	var alt_km := main.world.altitude_of(player) / 1000.0
	_check(absf(alt_km - 400.0) < 1.0, "player starts in Earth orbit at 400 km (actual %.2f km)" % alt_km)
	_check(main.hud.orbit_label.text.contains("PERIAPSIS") and main.hud.orbit_label.text.contains("ENTRY IF   100 km"),
		"HUD orbit panel shows apsides and the 100 km entry interface")

	# Hold W for 1 s of simulation time.
	Input.action_press("thrust_forward")
	await _run_until_sim_time(main, 1.0)
	Input.action_release("thrust_forward")
	var fwd := -player.body_velocity().z
	var expected := player.config.thrust_forward_n / player.mass_kg() * 1.0
	_check(fwd > expected * 0.8 and fwd < expected * 1.3,
		"forward speed after ~1 s of W: expected ≈%.1f m/s, actual %.2f m/s" % [expected, fwd])

	# Assist on + HOLD ORBIT: releasing the keys coasts, spending no Δv.
	var dv_before := player.delta_v_expended
	await _run_until_sim_time(main, 0.5)
	_check(absf(player.delta_v_expended - dv_before) < 1e-6,
		"hold-orbit assist spends no Δv while coasting (spent %.4f m/s)" % (player.delta_v_expended - dv_before))

	# Fire for ~0.6 s through the fire action: at 240 rpm that is 3 rounds.
	Input.action_press("fire")
	await _run_until_sim_time(main, 0.6)
	Input.action_release("fire")
	_check(player.rounds_fired >= 2 and not main.world.projectiles().is_empty(),
		"fire action launches rounds (fired %d, in flight %d)" % [player.rounds_fired, main.world.projectiles().size()])
	_check(main.hud.target_label.text.contains("ROUND TOF"), "HUD target panel shows round time of flight")

	# X switches the hold to target velocity matching.
	var target := main.world.get_ship(&"target_01")
	var rel_before := (player.velocity - target.velocity).length()
	_press_action("toggle_velocity_hold")
	await process_frame
	await process_frame
	_check(main.player_input.velocity_hold == PlayerInput.VelocityHold.TARGET and main.hud.flight_label.text.contains("MATCH TARGET"),
		"X switches velocity hold to MATCH TARGET")
	# Each axis nulls at the RCS limit, so 3 s removes at least ~0.8 × a·t.
	await _run_until_sim_time(main, 3.0)
	var rel_after := (player.velocity - target.velocity).length()
	var a_rcs := player.config.thrust_lateral_n / player.mass_kg()
	_check(rel_before - rel_after > 0.8 * a_rcs * 3.0,
		"match-target assist reduces relative speed at the RCS limit (%.1f → %.1f m/s in 3 s, a_rcs %.2f m/s²)" % [rel_before, rel_after, a_rcs])

	# Toggle assist off through the real input path.
	_press_action("toggle_flight_assist")
	await process_frame
	await process_frame
	_check(not main.player_input.flight_assist, "Z toggles flight assist off")
	var hud_text: String = main.hud.flight_label.text
	_check(hud_text.contains("MANUAL"), "HUD shows manual mode")

	# Manual mode: coasting keeps forward speed (no hidden damping).
	var before := -player.body_velocity().z
	await _run_until_sim_time(main, 0.5)
	var after := -player.body_velocity().z
	_check(absf(after - before) < 0.05, "manual coast keeps speed: before %.3f, after %.3f" % [before, after])

	var target_text: String = main.hud.target_label.text
	_check(target_text.contains("RANGE") and target_text.contains("km"), "HUD target panel shows range in km")
	_check(main.camera.current, "chase camera is the active camera")

	print("smoke: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)


func _press_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

