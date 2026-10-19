extends SceneTree
## Milestone 6 exit test through the real scenes and input actions: the
## player commands an NPC fighter and recovers or loses it persistently.
##   godot --headless --path . -s res://tests/smoke/smoke_wing.gd
## L launches, the fighter strikes the target, K recalls it and it is
## recovered; next sortie it is shot down, the station lists the
## replacement, it stays lost until replaced, then flies again.
##
## Scaffolding, stated plainly: the fighter is "shot down" by setting its
## status (rounds destroying craft are tested in test_air_wing.gd).

const WATCHDOG_S := 180.0
const TIME_SCALE := 30.0

var _failures := PackedStringArray()


func _initialize() -> void:
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		print("smoke_wing: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
		quit(2))
	_run.call_deferred()


func _check(condition: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if condition else "FAIL", what])
	if not condition:
		_failures.append(what)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame


func _wait(main: Main, sim_seconds: float, until: Callable) -> void:
	Engine.time_scale = TIME_SCALE
	var stop := main.world.sim_time + sim_seconds
	while main.world.sim_time < stop and not until.call():
		await process_frame
	Engine.time_scale = 1.0


func _main() -> Main:
	return current_scene as Main


func _run() -> void:
	print("== smoke_wing")
	PlayerProfile.path = "user://smoke_wing_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	Main.launch_blueprint = null
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 3:
		await process_frame
	var wing := main.player_wing
	var fighter: AirWing.Craft
	for c in wing.crafts:
		if not c.is_drone():
			fighter = c
	_check(fighter != null and wing.crafts.size() == 2, "the Frigate carries a fighter and a drone")

	# Launch, strike, recall, recover.
	await _press("launch_craft")
	_check(fighter.status == AirWing.Status.FLYING and main.world.has_ship(fighter.id), "L launches the wing")
	_check(main.hud.weapon_label.text.contains("WING"), "the weapon strip shows the wing")
	var target := main.world.get_ship(Main.TARGET_ID)
	var hits_before := target.hits_taken
	await _wait(main, 150.0, func() -> bool: return target.hits_taken >= hits_before + 3)
	_check(target.hits_taken >= hits_before + 3, "the fighter strikes the target (%d hits)" % (target.hits_taken - hits_before))
	await _press("recall_craft")
	await _wait(main, 240.0, func() -> bool: return fighter.status == AirWing.Status.DOCKED)
	_check(fighter.status == AirWing.Status.DOCKED and not main.world.has_ship(fighter.id), "K recalls it and it is recovered")

	# Dock: the recovered fighter's state persists.
	await _press("open_shipyard")
	for i in 4:
		await process_frame
	var yard := current_scene as Shipyard
	_check(yard != null, "docked at the station")
	if yard == null:
		return _finish()
	var profile := Main.get_profile()
	_check(not (profile.vessel.wing.get(fighter.rack_id, {}) as Dictionary).get("lost", false), "the recovered fighter is not lost")
	_check(yard.launch(), "relaunch")
	for i in 4:
		await process_frame
	main = _main()
	wing = main.player_wing
	for c in wing.crafts:
		if not c.is_drone():
			fighter = c
	await _press("launch_craft")
	_check(fighter.status == AirWing.Status.FLYING, "the fighter flies again")

	# Shot down: lost, and it stays lost.
	main.world.get_ship(fighter.id).status = ShipState.Status.DESTROYED
	await _wait(main, 1.0, func() -> bool: return fighter.status == AirWing.Status.LOST)
	_check(fighter.status == AirWing.Status.LOST and main.hud.weapon_label.text.contains("LOST"), "shot down: LOST, and the HUD says so")
	await _press("open_shipyard")
	for i in 4:
		await process_frame
	yard = current_scene as Shipyard
	_check(yard != null and (profile.vessel.wing.get(fighter.rack_id, {}) as Dictionary).get("lost", false), "the loss is saved with the vessel")
	_check(yard._hangar_label.get_parsed_text().contains("Replace lost Wasp fighter"), "the station lists the replacement")
	_check(yard.launch(), "relaunch without replacing it")
	for i in 4:
		await process_frame
	main = _main()
	for c in main.player_wing.crafts:
		if not c.is_drone():
			fighter = c
	_check(fighter.status == AirWing.Status.LOST and main.player_wing.launch(main.world, fighter).contains("lost"),
		"still lost next sortie: it cannot launch")
	await _press("open_shipyard")
	for i in 4:
		await process_frame
	yard = current_scene as Shipyard
	profile.spare_parts = 200
	yard.repair(ServiceYard.Priority.FULL)
	_check(not profile.vessel.wing.has(fighter.rack_id), "replaced at the station")
	yard.launch()
	for i in 4:
		await process_frame
	main = _main()
	for c in main.player_wing.crafts:
		if not c.is_drone():
			fighter = c
	_check(fighter.status == AirWing.Status.DOCKED and main.player_wing.launch(main.world, fighter) == "", "the replacement launches")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	print("smoke_wing: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
