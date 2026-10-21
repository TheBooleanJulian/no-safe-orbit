extends SceneTree
## Milestone 10 end to end through the real flight scene: a three-ship
## encounter (mission 7). Every contact is listed (target card, radar,
## markers, drawer); U and the drawer select one; the encounter fights by
## role and fires missile salvos; the selected contact — not the lead — is
## salvaged and stays as a wreck while the others fight on; the player's
## policy is switched in the drawer and saved; manual fire wins over HOLD.
##   godot --headless --path . -s res://tests/smoke/smoke_encounter.gd
##
## Scaffolding, stated plainly: the profile starts at mission 7; the
## wingmen, who arrive from range since play-test batch 6 (checked first),
## are brought alongside at once; and the salvaged contact's guns are
## destroyed and it is placed alongside directly.

const WATCHDOG_S := 240.0
const TIME_SCALE := 20.0

var _failures := PackedStringArray()


func _initialize() -> void:
	create_timer(WATCHDOG_S, true, false, true).timeout.connect(func() -> void:
		print("smoke_encounter: TIMEOUT after %d s (script error or stuck await)" % WATCHDOG_S)
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


func _run() -> void:
	print("== smoke_encounter")
	PlayerProfile.path = "user://smoke_encounter_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	Main.profile = null
	var profile := Main.get_profile()
	profile.missions_completed = 6
	profile.encounter_size = 3
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var world := main.world
	var player := world.get_ship(Main.PLAYER_ID)

	var ids := main.encounter.contacts.map(func(c: Contact) -> StringName: return c.id)
	_check(ids == [&"target_01", &"target_02", &"target_03"] and main.encounter.selected == &"target_01",
		"three picked on the map: contacts in slots target_01..03, the lead selected (%s)" % [ids])
	var far := true
	for i in range(1, main.encounter.contacts.size()):
		var w := world.get_ship(main.encounter.contacts[i].id)
		far = far and main.encounter.contacts[i].arriving and w.position.distance_to(player.position) > 20000.0
	_check(far, "only the lead starts close: the wingmen arrive from range")
	# Bring them alongside, as they used to start, to test the rest (fixed
	# here: the opening range moved out in play-test batch 9; this is about
	# the fight once they are close).
	var alongside := [Vector3.ZERO, Vector3(-1500, -250, -3800), Vector3(2300, 450, -4400)]
	for i in range(1, main.encounter.contacts.size()):
		var c: Contact = main.encounter.contacts[i]
		var w := world.get_ship(c.id)
		c.arriving = false
		w.position = player.position + (alongside[i % alongside.size()] as Vector3)
		w.velocity = player.velocity + Vector3(-25, 1.5, 6.0)
	var roles := main.encounter.contacts.map(func(c: Contact) -> String: return ShipPolicy.ROLE_NAMES[c.policy.role])
	_check(roles == ["closer", "standoff", "flanker"], "roles by place: %s" % [roles])
	await process_frame
	await process_frame
	var card := main.hud.target_label.text
	_check(card.contains("OTHERS") and card.contains("TGT-07B") and card.contains("TGT-07C"),
		"the target card lists the other two compactly")
	_check(main.hud.radar.contacts.size() == 3, "the radar shows all three (%d)" % main.hud.radar.contacts.size())

	# U cycles the selection through all three.
	var picked: Array[StringName] = []
	for i in 3:
		await _press("cycle_target")
		picked.append(main.encounter.selected)
	_check(picked == [&"target_02", &"target_03", &"target_01"], "U cycles the contacts: %s" % [picked])
	# The drawer lists them; its button selects one.
	await _press("tactical_overview")
	main.hud.overview.show_tab("TARGET")
	await process_frame
	await process_frame
	_check(main.hud.overview._contacts_box.get_child_count() == 3, "Tab › TARGET lists the three contacts")
	main._on_overview_command(&"select_contact", "target_02")
	await process_frame
	_check(main.encounter.selected == &"target_02" and main.hud._target_heading.text.contains("TGT-07B")
		and not main.hud.target_label.text.contains("TGT-07B"),
		"the drawer selects TGT-07B; the card follows (heading: %s)" % main.hud._target_heading.text)

	# The policy tab: Standard, saved with the vessel.
	main.hud.overview.show_tab("POLICY")
	main._on_overview_command(&"policy_preset", "Standard")
	await process_frame
	await process_frame
	_check(player.policy.preset_name == "Standard" and player.policy.autofire_enabled and profile.vessel.policy.preset_name == "Standard"
		and main.hud.overview._policy_label.get_parsed_text().contains("Standard"),
		"Tab › POLICY switches to Standard; it is the vessel's (auto-fire on)")
	await _press("tactical_overview")

	# Hostile: all three fight, by role, and fire salvos.
	main.set_target_hostile(true, "smoke")
	var fired := func() -> bool:
		return main.encounter.contacts.all(func(c: Contact) -> bool: return world.get_ship(c.id).rounds_fired > 0)
	await _wait(main, 90.0, fired)
	_check(fired.call(), "every contact opens fire on its own (after %.0f s)" % world.sim_time)
	await _wait(main, 60.0, func() -> bool: return main.combat_log.missiles_inbound >= 2)
	_check(main.combat_log.missiles_inbound >= 2, "the encounter fires missile salvos at us (%d inbound so far)" % main.combat_log.missiles_inbound)
	var closer := world.get_ship(&"target_01").position.distance_to(player.position)
	var standoff := world.get_ship(&"target_02").position.distance_to(player.position)
	_check(standoff > closer, "the standoff ship holds further out than the closer (%.1f vs %.1f km)" % [standoff / 1000.0, closer / 1000.0])

	# Manual fire wins over a HOLD policy.
	main._on_overview_command(&"policy_preset", "Hold")
	var before := player.rounds_fired
	Input.action_press("fire")
	await _wait(main, 3.0, func() -> bool: return false)
	Input.action_release("fire")
	_check(player.policy.preset_name == "Hold" and player.rounds_fired > before, "manual fire under HOLD still fires (%d rounds)" % (player.rounds_fired - before))

	# Salvage the selected one (TGT-07B), not the lead.
	main.select_contact(&"target_02")
	var b := world.get_ship(&"target_02")
	for e in b.systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.CANNON:
			b.systems.damage_equipment(e, 1000.0)
	b.position = player.position + player.orientation * Vector3(0, 0, -300)
	b.velocity = player.velocity
	b.angular_velocity = Vector3.ZERO
	b.snapshot_previous()
	await process_frame
	await process_frame
	await _press("salvage")
	var wreck_ids := main._wrecks.duplicate()
	_check(wreck_ids.size() == 1 and world.get_ship(wreck_ids[0]).derelict and world.get_ship(wreck_ids[0]).display_name.contains("07B"),
		"G salvages the selected TGT-07B; it stays as a silent wreck (%s)" % [wreck_ids])
	_check(main.encounter.live(world).size() == 2 and main.encounter.selected != &"target_02" and not world.has_ship(&"target_02"),
		"two contacts fight on; the selection moved to %s" % main.encounter.selected)
	_check(world.has_ship(&"target_01") and world.get_ship(&"target_01").display_name.begins_with("TGT-07 "),
		"the lead was not touched")

	Engine.time_scale = 1.0
	for s in ["", PlayerProfile.BACKUP_SUFFIX]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	print("smoke_encounter: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
