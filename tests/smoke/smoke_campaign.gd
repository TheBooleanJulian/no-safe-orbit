extends SceneTree
## Milestone 4 exit test, end to end through the real scenes (spec §17:
## "complete a combat mission, return damaged, repair/reconfigure and
## relaunch").
##   godot --headless --path . -s res://tests/smoke/smoke_campaign.gd
## Fight (our hit, their hits on us) → target disabled → salvage with G →
## loot granted and saved → B docks damaged → shipyard repairs and refits →
## relaunch flies the repaired, refitted vessel; the profile on disk agrees.
##
## Scaffolding, stated plainly: after a real exchange of fire the target's
## gun is destroyed directly and it is placed alongside, rather than shot to
## a mission kill and flown to (hits, penetration and the match-velocity
## assist have their own tests).

const WATCHDOG_S := 180.0

var _failures := PackedStringArray()


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("smoke_campaign: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
		quit(2))
	_run.call_deferred()


func _check(condition: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if condition else "FAIL", what])
	if not condition:
		_failures.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)


func _run() -> void:
	print("== smoke_campaign")
	PlayerProfile.path = "user://smoke_campaign_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	Main.launch_blueprint = null
	root.size = Vector2i(1600, 900)
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(2)
	var profile := Main.get_profile()
	var parts_at_start := profile.spare_parts
	var player := main.world.get_ship(Main.PLAYER_ID)
	var target := main.world.get_ship(Main.TARGET_ID)

	# 1. Fight: we hit them (scripted aim, real fire action) ...
	Input.action_press("fire")
	var t0 := main.world.sim_time
	while target.hits_taken == 0 and main.world.sim_time - t0 < 8.0:
		var aim := target.position + target.orientation * target.config.hit_box_center - (player.position + player.orientation * player.config.primary_muzzle())
		var tof := FireControl.intercept_time(aim, target.velocity - player.velocity, player.config.cannon.muzzle_velocity_mps)
		if tof > 0.0:
			player.orientation = Quaternion(Vector3.FORWARD, FireControl.lead_point(aim, target.velocity - player.velocity, tof).normalized())
			player.angular_velocity = Vector3.ZERO
		await process_frame
	Input.action_release("fire")
	_check(target.hits_taken > 0, "we hit the target (%d hits)" % target.hits_taken)
	# ... and they hit us.
	await _press("toggle_target_ai")
	t0 = main.world.sim_time
	while player.hits_taken == 0 and main.world.sim_time - t0 < 40.0:
		await process_frame
	await _press("toggle_target_ai")
	_check(player.hits_taken > 0 and not player.systems.condition().modules.is_empty(),
		"the target hits us and leaves damage (%d hits)" % player.hits_taken)

	# 2. Mission kill, then come alongside.
	target.systems.damage_equipment(target.systems.equipment_by_id("e41"), 1000.0)
	target.position = player.position + Vector3(0, 0, -300)
	target.velocity = player.velocity
	await _frames(2)
	_check(main.hud.target_label.text.contains("DISABLED") and main.hud.target_label.text.contains("READY — press [G]"),
		"HUD reports the target disabled and ready to salvage")

	# 3. Salvage with G.
	var old_target := target
	await _press("salvage")
	_check(main.hud.loot.visible and profile.missions_completed == 1 and profile.total_pulls >= 1,
		"G salvages: loot panel open, %d crates opened, mission 1 complete" % profile.total_pulls)
	_check(profile.spare_parts > parts_at_start, "spare parts recovered (%d → %d)" % [parts_at_start, profile.spare_parts])
	var next := main.world.get_ship(Main.TARGET_ID)
	_check(next != old_target and next.display_name.begins_with("TGT-02"), "the next contact arrives (%s)" % next.display_name)
	_check(FileAccess.file_exists(PlayerProfile.path), "salvage saved the profile")
	await create_timer(LootPanel.REVEAL_INTERVAL_S * (profile.total_pulls + 2)).timeout
	_check(main.hud.loot.revealed_all() and main.hud.loot.text().contains("Rates"), "every drop revealed, with the drop rates")
	await _press("salvage")
	_check(not main.hud.loot.visible, "G again closes the loot panel")

	# 4. Return damaged: B docks.
	var flown_condition := player.systems.condition()
	await _press("open_shipyard")
	await _frames(3)
	var yard := current_scene as Shipyard
	_check(yard != null, "B docks at the shipyard")
	if yard == null:
		return _finish()
	var vessel := yard.profile.vessel
	_check(vessel.sorties == 1 and vessel.is_damaged() and JSON.stringify(vessel.condition) == JSON.stringify(flown_condition),
		"the docked vessel keeps exactly the damage it flew back with")
	_check(yard._hangar_label.get_parsed_text().contains("DAMAGE"), "the hangar panel lists the damage")

	# 5. Repair and reconfigure.
	var before_repair := profile.spare_parts
	var spent := yard.repair(ServiceYard.Priority.FULL)
	_check(spent > 0 and not vessel.is_damaged() and profile.spare_parts == before_repair - spent,
		"full repair: %d spare parts, vessel like new" % spent)
	var radiators := yard.editor.blueprint.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == &"radiator").size()
	yard.editor.place_equipment(&"radiator", Vector3i(3, 2, 6), &"dorsal")
	var parts_before_launch := profile.spare_parts
	_check(not yard.editor.report.has_errors(), "refitted design (extra radiator) validates")

	# 6. Relaunch.
	_check(yard.launch(), "launch accepted")
	await _frames(4)
	main = current_scene as Main
	_check(main != null, "flight scene running again")
	if main == null:
		return _finish()
	player = main.world.get_ship(Main.PLAYER_ID)
	var whole := player.systems.equipment.all(func(e: ShipSystems.EquipmentState) -> bool: return e.hp == e.max_hp)
	var flown_radiators := player.systems.blueprint.equipment.filter(func(e: ShipBlueprint.PlacedEquipment) -> bool: return e.def_id == &"radiator").size()
	_check(whole and player.systems.condition().modules.is_empty(), "relaunched ship is repaired")
	_check(flown_radiators == radiators + 1, "relaunched ship carries the refit (%d radiators)" % flown_radiators)
	_check(profile.spare_parts == parts_before_launch - 3, "the refit was paid for: 3 parts for the radiator")

	# 7. What is on disk agrees.
	var errors := PackedStringArray()
	var saved := PlayerProfile.load_file(PlayerProfile.path, errors)
	_check(saved != null and saved.spare_parts == profile.spare_parts and saved.missions_completed == 1
		and saved.vessel.blueprint.equipment.size() == player.systems.blueprint.equipment.size() and not saved.vessel.is_damaged(),
		"the saved profile matches: parts, mission count, refitted and repaired vessel")
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	print("smoke_campaign: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
