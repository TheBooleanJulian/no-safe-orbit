extends SceneTree
## Balance check (play-test batch 6: "enemies still feel slightly too strong
## when it's not a 1v1"): the real flight scene, headless and fast-forwarded,
## the player's Frigate Mk I played competently — guns on the lead, trigger
## held, fighters out, auto-fire and auto-salvo by the Standard policy, the
## next contact taken when one is beaten — against 1, 2 and 3 ships at a few
## mission levels. Prints who won and how long it took.
##   godot --headless --path . -s res://tools/balance_sim.gd [-- --quick]
## Scratch profile; never the player's save.

const MISSIONS := [3, 5, 7]
const SIZES := [1, 2, 3]
const LIMIT_S := 480.0
const TIME_SCALE := 8.0
const FIRE_RANGE_M := 6000.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var quick := OS.get_cmdline_user_args().has("--quick")
	var rows := PackedStringArray()
	for m in ([5] if quick else MISSIONS):
		for n in SIZES:
			rows.append(await _fight(m, n))
	print("balance_sim: mission · ships · outcome · time · player intact · enemies beaten · when the player's guns went out")
	for r in rows:
		print("  " + r)
	quit()


func _fight(mission: int, ships: int) -> String:
	PlayerProfile.path = "user://balance_sim_profile.json"
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	Main.profile = null
	Main.launch_blueprint = null
	var p := Main.get_profile()
	p.missions_completed = mission - 1
	p.encounter_size = ships
	p.tutorial = {"declined": true}
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 5:
		await process_frame
	var player := main.world.get_ship(Main.PLAYER_ID)
	player.policy = ShipPolicy.preset("Standard")
	player.policy.salvo_enabled = true
	main.set_target_hostile(true, "balance")
	main.player_wing.launch_all(main.world)
	Engine.time_scale = TIME_SCALE
	var start := main.world.sim_time
	var beaten := 0
	var outcome := "time"
	var guns_out := -1.0
	var firing := false
	while main.world.sim_time - start < LIMIT_S:
		main.aim_cursor_at_lead()
		# A sensible player: the trigger only on a contact in sight and range.
		var tgt := main.target_ship()
		var c0 := main.encounter.selected_contact()
		var want := tgt != null and c0 != null and c0.track.detected and tgt.position.distance_to(player.position) < FIRE_RANGE_M
		if want != firing:
			firing = want
			if firing:
				Input.action_press("fire")
			else:
				Input.action_release("fire")
		await process_frame
		# Losing the guns is a setback (repairs, missiles, fighters), not a
		# loss: lost is the ship gone, captured, or without power or bridge.
		var why := player.systems.disabled_reason() if player.is_active() else "gone"
		if why == "all guns out" and guns_out < 0.0:
			guns_out = main.world.sim_time - start
		if not player.is_active() or why in ["no power", "command room lost", "captured", "gone"]:
			outcome = "LOST (%s)" % why
			var sys := player.systems
			var breached := PackedStringArray()
			for i in sys.rooms.size():
				if sys.rooms[i].breached:
					breached.append("%s(%s)" % [sys.blueprint.rooms[i].id, sys.blueprint.rooms[i].def_id])
			var gone := PackedStringArray()
			for e in sys.equipment:
				if e.destroyed():
					gone.append(String(e.def.id))
			print("    LOSS: hits %d · breached %s · destroyed %s · missiles in flight %d" % [player.hits_taken, breached, gone, main.world.missiles.size()])
			break
		beaten = 0
		var live := 0
		for c in main.encounter.contacts:
			if Main.is_fightable(main.world.get_ship(c.id)):
				live += 1
			else:
				beaten += 1
		if live == 0 and main.encounter.contacts.size() > 0:
			outcome = "won"
			break
		var sel := main.target_ship()
		if not Main.is_fightable(sel):
			for c in main.encounter.contacts:
				if Main.is_fightable(main.world.get_ship(c.id)):
					main.select_contact(c.id)
					break
	Engine.time_scale = 1.0
	Input.action_release("fire")
	var row := "m%d · %d ship%s · %s · %5.0f s · %3d %% · %d/%d · guns out %s" % [mission, ships, "" if ships == 1 else "s", outcome,
		main.world.sim_time - start, roundi(player.systems.intact_fraction() * 100.0), beaten, ships,
		"at %.0f s" % guns_out if guns_out >= 0.0 else "never"]
	var detail := PackedStringArray()
	for c in main.encounter.contacts:
		var s := main.world.get_ship(c.id)
		detail.append("%s hit %d, detected %s, locked %s, hostile %s" % [c.id, s.hits_taken if s != null else -1, c.track.detected, c.track.locked, c.hostile])
	row += "  [player fired %d; %s]" % [player.rounds_fired, "; ".join(detail)]
	print(row)
	main.queue_free()
	await process_frame
	await process_frame
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	return row
