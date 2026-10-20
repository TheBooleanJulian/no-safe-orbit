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
	# A throwaway profile: never touch the player's real save.
	PlayerProfile.path = "user://smoke_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	# The template with a missile rack, so M can be tried too.
	var errors := PackedStringArray()
	var armed := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)
	EnemyFactory._fit_launcher(armed, ConstructionCatalog.default_catalog(), &"missile_rack", RandomNumberGenerator.new())
	Main.launch_blueprint = armed
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

	# The mission goal and the tutorial offer at the top; F2 starts it.
	_check(main.hud.guide_label.visible and main.hud.guide_label.get_parsed_text().contains("MISSION 1/4")
		and main.hud.guide_label.get_parsed_text().contains("[F2]"), "HUD shows the first goal and offers the tutorial")
	_press_action("tutorial")
	await process_frame
	await process_frame
	_check(main.tutorial.running() and main.hud.guide_label.get_parsed_text().contains("TUTORIAL 1/7"), "F2 starts the guided first sortie")

	# Hold W for 1 s of simulation time.
	Input.action_press("thrust_forward")
	await _run_until_sim_time(main, 1.0)
	Input.action_release("thrust_forward")
	await process_frame
	_check(main.tutorial.step >= 1, "burning the engine completes the tutorial's FLY step (now %s)" % main.tutorial.current_id())
	var fwd := -player.body_velocity().z
	var expected := player.config.thrust_forward_n / player.mass_kg() * 1.0
	_check(fwd > expected * 0.8 and fwd < expected * 1.3,
		"forward speed after ~1 s of W: expected ≈%.1f m/s, actual %.2f m/s" % [expected, fwd])

	# Assist on + HOLD ORBIT: releasing the keys coasts, spending no Δv.
	var dv_before := player.delta_v_expended
	await _run_until_sim_time(main, 0.5)
	_check(absf(player.delta_v_expended - dv_before) < 1e-6,
		"hold-orbit assist spends no Δv while coasting (spent %.4f m/s)" % (player.delta_v_expended - dv_before))

	# Fire for 3 s through the fire action, the cursor on the target: the
	# turret trains on, then fires at 50 rpm.
	Input.action_press("fire")
	var t_fire := main.world.sim_time
	while main.world.sim_time - t_fire < 3.0:
		main.aim_cursor_at_lead()
		await process_frame
	Input.action_release("fire")
	_check(player.rounds_fired >= 2 and not main.world.projectiles().is_empty(),
		"fire action launches rounds (fired %d, in flight %d)" % [player.rounds_fired, main.world.projectiles().size()])
	_check(main.hud.target_label.text.contains("ETA ~"), "HUD target card shows the round ETA, marked as an estimate")

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
	_check(main.hud.flight_label.text.contains("POWER") and main.hud.flight_label.text.contains("HEAT")
		and main.hud.target_label.text.contains("STATUS") and main.hud.target_label.text.contains("TRACK   ● MEAS"),
		"HUD shows own power/heat, the target's status and a measured track")

	# Aim at the lead (scripted) and fire through the real action: our hit
	# opens the hit cam replay.
	var tgt := main.world.get_ship(&"target_01")
	var hits_before := tgt.hits_taken
	var t_aim := main.world.sim_time
	Input.action_press("fire")
	while tgt.hits_taken == hits_before and main.world.sim_time - t_aim < 8.0:
		var aim := tgt.position + tgt.orientation * tgt.config.hit_box_center - (player.position + player.orientation * player.config.primary_muzzle())
		var tof := FireControl.intercept_time(aim, tgt.velocity - player.velocity, player.config.cannon.muzzle_velocity_mps)
		if tof > 0.0:
			player.orientation = Quaternion(Vector3.FORWARD, FireControl.lead_point(aim, tgt.velocity - player.velocity, tof).normalized())
			player.angular_velocity = Vector3.ZERO
		main.aim_cursor_at_lead()
		await process_frame
	Input.action_release("fire")
	await process_frame
	_check(tgt.hits_taken > hits_before and main.hud.hit_cam.visible and main.hud.hit_cam._title.text.begins_with("HIT CAM"),
		"our hit on the target opens the hit cam replay (%d hits)" % (tgt.hits_taken - hits_before))

	# T: the target shoots back. Within 40 s the player takes a hit, and the
	# HUD reports what it did. (Our hit above may already have turned it
	# hostile — "fired upon" — and T would then toggle it back to passive.)
	# Scaffolding: our hits above can knock out its only gun or cut the
	# conduit feeding it (where they land depends on frame timing), and a
	# gunless target can't shoot back. Restore both.
	for e in tgt.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.CANNON and e.destroyed():
			e.hp = e.max_hp
	tgt.systems.bus_cut.clear()
	tgt.systems.solve_power()
	tgt.systems.invalidate()
	tgt.config = tgt.systems.effective_config()
	if not main.target_hostile:
		_press_action("toggle_target_ai")
	await process_frame
	_check(main.target_hostile, "the target is hostile (fired upon, or T)")
	var t0 := main.world.sim_time
	while player.hits_taken == 0 and main.world.sim_time - t0 < 40.0:
		await process_frame
	await process_frame
	_check(player.hits_taken > 0 and main.hud.flight_label.text.contains("HIT TAKEN"),
		"hostile target hits the player and the HUD reports it (after %.1f s)" % (main.world.sim_time - t0))

	# Panels and the damage-control drawer, through the real actions.
	_press_action("toggle_details")
	_press_action("toggle_orbit_panel")
	await process_frame
	await process_frame
	_check(main.hud.details_label.is_visible_in_tree() and main.hud.orbit_label.is_visible_in_tree(), "J and O open the details and orbit panels")
	player.systems.damage_equipment(player.systems.equipment_by_id("e28"), 50.0)
	await process_frame
	await process_frame
	_check(main.hud.alert_subject == "e28" or main.hud.warning_label.text.contains("e28") or main.hud.flight_label.text.contains("e28"),
		"a critical reactor raises an alert naming it")
	_press_action("tactical_overview")
	await process_frame
	await process_frame
	var drawer := main.hud.overview
	drawer.select_subject("e41")
	await process_frame
	await process_frame
	var off_button: Button
	for b in drawer._actions.get_children():
		if (b as Button).text.begins_with("Switch off"):
			off_button = b
	_check(drawer.visible and off_button != null, "Tab opens the drawer; the selected gun offers 'Switch off'")
	if off_button != null:
		off_button.pressed.emit()
		await process_frame
		_check(player.systems.switched_off.has("e41") and not player.systems.equipment_by_id("e41").powered, "the button switches the gun off (power rerouted)")
	# A click beside the open drawer must not grab the mouse back.
	main.player_input.suppress_fire = false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(20, 20)
	Input.parse_input_event(click)
	await process_frame
	await process_frame
	_check(main.menu_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not main.player_input.suppress_fire,
		"with Tab open a click keeps the cursor visible (no capture)")
	var unclick := click.duplicate() as InputEventMouseButton
	unclick.pressed = false
	Input.parse_input_event(unclick)

	# The CREW and WEAPONS tabs fill in (the drawer is still open).
	drawer.show_tab("CREW")
	await process_frame
	await process_frame
	_check(drawer._crew_tree.get_root() != null and drawer._crew_tree.get_root().get_child_count() >= 3,
		"Tab › CREW lists the crew by post (%d posts)" % (drawer._crew_tree.get_root().get_child_count() if drawer._crew_tree.get_root() != null else 0))
	drawer.show_tab("WEAPONS")
	await process_frame
	await process_frame
	_check(drawer._missile_label.get_parsed_text().contains("Missile rack") and drawer._missile_label.get_parsed_text().contains("Mode: ALL"),
		"Tab › WEAPONS shows the launchers and the missile mode")

	# [,] cycles the missile mode; back to "all" after a full turn.
	for i in MissileSalvo.Mode.size():
		_press_action("missile_mode")
		await process_frame
	_check(main.get_profile().missile_mode == MissileSalvo.Mode.ALL, "[,] cycles the missile modes round to 'all'")

	# M: a volley — one missile from each pod (here the one rack) — at the
	# locked target; a second press fires the next.
	_press_action("tactical_overview")
	main.hud.selected_id = &""
	var t_lock := main.world.sim_time
	while not main.track.locked and main.world.sim_time - t_lock < 10.0:
		await process_frame
	_press_action("fire_missile")
	await process_frame
	await process_frame
	_check(main.track.locked and (main.salvo != null or main.combat_log.missiles_launched > 0) and main.hud.weapon_label.text.contains("MSL"),
		"M fires a volley at the locked target (strip: %s)" % main.hud.weapon_label.text.get_slice("\n", 0))
	await _run_until_sim_time(main, 1.0)
	_check(main.salvo == null and player.systems.missiles_of() == 11 and main.combat_log.missiles_launched == 1,
		"one press, one missile from the rack (%d launched, %d left)" % [main.combat_log.missiles_launched, player.systems.missiles_of()])
	_press_action("fire_missile")
	await _run_until_sim_time(main, 1.0)
	_check(main.combat_log.missiles_launched == 2 and player.systems.missiles_of() == 10, "a second press fires the next")
	Main.launch_blueprint = null

	print("smoke: %d failure(s)" % _failures.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + PlayerProfile.BACKUP_SUFFIX))
	quit(1 if not _failures.is_empty() else 0)


func _press_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

