extends SceneTree
## Milestone 5 exit test through the real flight scene and input actions:
## boarding is physical (tolerances, a gangway that must seal), counterable
## (a target that can still manoeuvre tears free) and plays out in the
## target's own rooms.
##   godot --headless --path . -s res://tests/smoke/smoke_boarding.gd
##
## Scaffolding, stated plainly: the target is placed alongside (flying the
## approach is tested elsewhere), its security team is killed and, for the
## capture, its reactor destroyed directly.

const WATCHDOG_S := 180.0
## Simulated time runs this much faster than real time while waiting.
const TIME_SCALE := 30.0

var _failures := PackedStringArray()


func _initialize() -> void:
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		print("smoke_boarding: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
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


## Target turned 180° with its collar facing ours, `gap` m away, matched.
func _alongside(player: ShipState, target: ShipState, gap: float) -> void:
	target.orientation = player.orientation * Quaternion(Vector3.UP, PI)
	var pa: Docking.Port = Docking.collars(player.systems)[0]
	var pb: Docking.Port = Docking.collars(target.systems, false)[0]
	target.position = pa.world_position(player) + pa.world_normal(player) * gap - target.orientation * pb.position_body
	target.velocity = player.velocity
	target.angular_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	target.snapshot_previous()


func _run() -> void:
	print("== smoke_boarding")
	PlayerProfile.path = "user://smoke_boarding_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	Main.launch_blueprint = null
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 3:
		await process_frame
	var player := main.world.get_ship(Main.PLAYER_ID)
	var target := main.world.get_ship(Main.TARGET_ID)

	# Out of tolerance: refused, with the reason.
	_alongside(player, target, 60.0)
	await _press("dock")
	_check(main.world.link_for(Main.PLAYER_ID) == null and main.hud.ticker_text().contains("range"),
		"V at 60 m is refused and the HUD says why")

	# In tolerance, but the target still has power and a crew in command: it tears free.
	_alongside(player, target, 15.0)
	await process_frame
	_check(main.hud.target_label.text.contains("DOCKING    READY"), "HUD: docking ready at 15 m")
	await _press("dock")
	var link := main.world.link_for(Main.PLAYER_ID)
	_check(link != null, "V extends a gangway")
	await _wait(main, 30.0, func() -> bool: return not link.active())
	_check(link.state == DockingLink.State.SEVERED, "an intact target thrusts away and tears the gangway (%s)" % link.reason)

	# Power out and its security dead: it can neither run nor hold the bridge.
	target.systems.damage_equipment(target.systems.equipment_by_id("e28"), 1000.0)
	for m in target.systems.crew.members:
		if m.role == CrewRoster.Role.SECURITY:
			m.state = CrewRoster.State.DEAD
	target.systems.invalidate()
	_alongside(player, target, 15.0)
	await _press("dock")
	link = main.world.link_for(Main.PLAYER_ID)
	await _wait(main, 30.0, func() -> bool: return link == null or link.sealed())
	_check(link != null and link.sealed() and main.hud.target_label.text.contains("SEALED"), "the gangway seals against a dead ship")
	await _press("board")
	var boarding := main.world.boarding_for(link)
	_check(boarding != null, "N sends the boarding party")
	if boarding == null:
		return _finish()
	var profile := Main.get_profile()
	var credits_before := profile.credits
	var scrap := Salvage.scrap_value(target.systems)
	await _wait(main, 400.0, func() -> bool: return target.systems.captured)
	await process_frame
	_check(target.systems.captured and boarding.prize, "the boarders take the bridge (after %.0f s)" % boarding.elapsed)
	_check(main.hud.target_label.text.contains("CAPTURED"), "HUD reports the capture")

	# The prize pays out at once: 80 % scrap and double bounty, its stores
	# and crates into our hold, on the carousel; the team withdraws itself.
	_check(main.hud.loot.visible and profile.missions_completed == 1, "the takeover opens the loot carousel and completes the mission")
	_check(profile.credits >= credits_before + roundi(scrap * Salvage.TAKEOVER_SCRAP_RATE) * 0.9,
		"80%% of the scrap value credited (%d → %d, scrap %d)" % [credits_before, profile.credits, scrap])
	_check(int(profile.vessel.cargo.get("spare_parts", 0)) > 0, "its stores are in our hold (%s)" % profile.vessel.cargo_summary())
	await _wait(main, 300.0, func() -> bool: return boarding.finished())
	_check(boarding.phase == BoardingAction.Phase.RETURNED
		and boarding.team.all(func(m: CrewRoster.Member) -> bool: return m.state == CrewRoster.State.DEAD or (m.location >= 0 and not m.busy)),
		"the boarding party withdraws on its own and is back aboard (%s)" % BoardingAction.PHASE_NAMES[boarding.phase])
	await process_frame
	await process_frame
	_check(main.world.get_ship(Main.TARGET_ID) != target and main.world.link_for(Main.PLAYER_ID) == null,
		"the prize leaves and the next contact is on its way")

	# Turned round: the next enemy boards us once our guns are out.
	var hunter := main.world.get_ship(Main.TARGET_ID)
	_alongside(player, hunter, 120.0)
	hunter.angular_velocity = Vector3.ZERO
	main._target_arriving = false
	main.set_target_hostile(true)
	player.systems.damage_equipment(player.systems.equipment_by_id("e41"), 1000.0)
	main._on_overview_command(&"defence", BoardingAction.Defence.COUNTERATTACK)
	await _wait(main, 300.0, func() -> bool: return main.enemy_boarding() != null)
	var theirs := main.enemy_boarding()
	_check(theirs != null and theirs.link.attacker_id == Main.TARGET_ID, "a beaten player is boarded: the enemy docks and sends a party")
	_check(theirs != null and theirs.defence == BoardingAction.Defence.COUNTERATTACK, "our chosen defence applies to their boarding")
	_check(main.hud.warning_label.text.contains("BOARD") and main.hud.alert_queue.has(&"boarders"), "the HUD warns of enemy boarders (%s)" % main.hud.warning_label.text)
	await _press("dock")
	_check(main.world.link_for(Main.PLAYER_ID) == null, "V cuts their gangway loose")
	_finish()


func _finish() -> void:
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + PlayerProfile.BACKUP_SUFFIX))
	print("smoke_boarding: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
