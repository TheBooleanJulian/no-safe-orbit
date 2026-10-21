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


## Hold B until the jump drive takes us to the shipyard (sped up).
func _jump() -> void:
	Engine.time_scale = 8.0
	Input.action_press("open_shipyard")
	for i in 900:
		if current_scene is Shipyard:
			break
		await process_frame
	Input.action_release("open_shipyard")
	Engine.time_scale = 1.0
	await _frames(3)


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
	var credits_at_start := profile.credits
	var player := main.world.get_ship(Main.PLAYER_ID)
	var target := main.world.get_ship(Main.TARGET_ID)

	# 1. Fight: we hit them (scripted aim, real fire action) ... From the old
	# 2.5 km start: the opening range moved out in play-test batch 9, and from
	# there the first round disables this mission-1 ship before it can fire
	# back — this is about hits and damage, not the opening range.
	target.position = player.position + Vector3(400, 120, -2500)
	Input.action_press("fire")
	var t0 := main.world.sim_time
	while target.hits_taken == 0 and main.world.sim_time - t0 < 8.0:
		var aim := target.position + target.orientation * target.config.hit_box_center - (player.position + player.orientation * player.config.primary_muzzle())
		var tof := FireControl.intercept_time(aim, target.velocity - player.velocity, player.config.cannon.muzzle_velocity_mps)
		if tof > 0.0:
			player.orientation = Quaternion(Vector3.FORWARD, FireControl.lead_point(aim, target.velocity - player.velocity, tof).normalized())
			player.angular_velocity = Vector3.ZERO
		main.aim_cursor_at_lead()
		await process_frame
	Input.action_release("fire")
	_check(target.hits_taken > 0, "we hit the target (%d hits)" % target.hits_taken)
	# ... and they hit us.
	await _press("toggle_target_ai")
	t0 = main.world.sim_time
	while player.hits_taken == 0 and main.world.sim_time - t0 < 40.0:
		await process_frame
	await _press("toggle_target_ai")
	_check(player.hits_taken > 0 and (not player.systems.condition().modules.is_empty() or player.systems.condition().has("plates")),
		"the target hits us and leaves damage (%d hits)" % player.hits_taken)

	# 2. Mission kill, then come alongside.
	target.systems.damage_equipment(target.systems.equipment_by_id("e41"), 1000.0)
	target.position = player.position + Vector3(0, 0, -300)
	target.velocity = player.velocity
	await _frames(2)
	_check(main.hud.target_label.text.contains("DISABLED") and main.hud.target_label.text.contains("READY — press [G]"),
		"HUD reports the target disabled and ready to salvage")

	# 3. Salvage beacon with G: half the scrap value and the bounty in
	# credits; the crates are opened on the carousel, into the hold.
	var old_target := target
	var scrap := Salvage.scrap_value(target.systems)
	var bounty := Salvage.bounty_for(target.systems)
	await _press("salvage")
	_check(main.hud.loot.visible and profile.missions_completed == 1 and profile.total_pulls >= 1,
		"G drops a beacon: carousel open, %d crates opened, mission 1 complete" % profile.total_pulls)
	_check(profile.loot_log.is_empty() or profile.loot_log[profile.loot_log.size() - 1].ends_with("(in cargo)"),
		"beacon loot goes into the hold, banked once home (%s)" % profile.vessel.cargo_summary())
	# Disabling it also met the first goal ("First blood").
	var goal := int(MissionChain.CHAIN[0].credits)
	_check(profile.credits == credits_at_start + roundi(scrap * Salvage.BEACON_SCRAP_RATE) + bounty + goal and int(profile.campaign.step) == 1,
		"50%% of %d cr scrap, %d cr bounty and the %d cr mission reward paid (%d → %d)" % [scrap, bounty, goal, credits_at_start, profile.credits])
	var next := main.world.get_ship(Main.TARGET_ID)
	_check(next != old_target and next.display_name.begins_with("TGT-02"), "the next contact arrives (%s)" % next.display_name)
	_check(main.world.has_ship(old_target.id) and old_target.derelict and old_target.id != Main.TARGET_ID and old_target.display_name.begins_with("WRECK"),
		"the salvaged ship stays as a silent wreck (%s, %s)" % [old_target.id, old_target.display_name])
	_check(next.position.distance_to(player.position) > 25000.0 and not main.track.detected,
		"it arrives %.0f km out, beyond the sensors: no contact yet" % (next.position.distance_to(player.position) / 1000.0))
	main.target_hostile = true
	var fired_before := next.rounds_fired
	await _frames(30)
	_check(next.rounds_fired == fired_before, "undetected, it does not open fire even when hostile")
	main.target_hostile = false
	_check(FileAccess.file_exists(PlayerProfile.path), "salvage saved the profile")
	await create_timer((LootCarousel.SPIN_S + LootCarousel.HOLD_S) * (profile.total_pulls + 2)).timeout
	_check(main.hud.loot.revealed_all() and main.hud.loot.text().contains("Rates"), "every crate opened on the carousel, with the drop rates")
	await _press("salvage")
	_check(not main.hud.loot.visible, "G again closes the carousel")
	# Stores carried home (a takeover would have filled the hold).
	profile.vessel.cargo["spare_parts"] = 12

	# 4. Return damaged: B docks.
	var flown_condition := player.systems.condition()
	# Docking keeps every scrap of damage; only the wounded recover ashore.
	if flown_condition.has("crew"):
		flown_condition.crew.erase("wounded")
		if flown_condition.crew.is_empty():
			flown_condition.erase("crew")
	# The jump home burns propellant (main tank first, then the reserve).
	var aboard_kg := player.propellant_kg + main.jump_reserve_kg
	var jump_cost := main.jump_home_cost_kg(player)
	await _jump()
	var yard := current_scene as Shipyard
	_check(yard != null, "holding B jumps to Earth Shipyard")
	if yard == null:
		return _finish()
	var vessel := yard.profile.vessel
	var docked_condition := vessel.condition.duplicate(true)
	_check(docked_condition.has("stores"), "the stores it came back with are recorded (%s)" % str(docked_condition.get("stores")))
	var home: Dictionary = docked_condition.get("stores", {})
	var burned := aboard_kg - float(home.get("propellant_kg", 0.0)) - float(home.get("jump_reserve_kg", 0.0))
	_check(home.has("jump_reserve_kg") and absf(burned - jump_cost) < 1500.0,
		"the jump burned %.1f t (%.1f t quoted)" % [burned / 1000.0, jump_cost / 1000.0])
	docked_condition.erase("stores")
	_check(vessel.sorties == 1 and vessel.is_damaged() and JSON.stringify(docked_condition) == JSON.stringify(flown_condition),
		"the docked vessel keeps exactly the damage it flew back with (the wounded recover)")
	_check(yard._hangar_label.get_parsed_text().contains("DAMAGE"), "the hangar panel lists the damage")
	_check(yard.debrief.visible and yard.debrief.text().contains("LESSONS FOR THE SHIPYARD") and yard.debrief.text().contains("Hit from the"),
		"the station opens on the debrief, with where the hits came from")
	yard.debrief.hide_debrief()
	var hold_parts := int(vessel.cargo.get("spare_parts", 0))
	var banked_from := profile.spare_parts
	_check(not yard.bank_cargo().is_empty() and vessel.cargo_is_empty() and profile.spare_parts >= banked_from + hold_parts,
		"Bank cargo moves the hold into the station bank")
	_check(yard.loot_tables_label.get_parsed_text().contains("LEGENDARY") and yard.loot_tables_label.get_parsed_text().contains("takeover"),
		"the shipyard lists the loot tables")
	var credits_dev := profile.credits
	yard.dev_add_credits()
	_check(profile.credits == credits_dev + 100, "DEV +100 cr adds 100 credits")

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
	_check(profile.spare_parts == parts_before_launch - 5, "the refit was paid for: 5 parts for the 2-cell radiator")

	# 6b. The wreck left behind on the first sortie is still out there
	# (Milestone 14 derelict field): salvage it again, for half.
	var field_ids: Array = main.hud.derelict_ids
	_check(field_ids.size() == 1 and profile.derelicts.size() == 1 and int(profile.derelicts[0].salvaged) == 1,
		"the first sortie's wreck is in the derelict field (%d found)" % field_ids.size())
	if field_ids.size() == 1:
		var old := main.world.get_ship(field_ids[0])
		var dist := old.position.distance_to(player.position)
		_check(old.derelict and old.systems.disabled_reason() == "no power" and dist > 3500.0,
			"%s lies %.1f km out, dead in space" % [old.display_name, dist / 1000.0])
		player.position = old.position + Vector3(0, 0, 600)
		player.velocity = old.velocity
		var credits_before := profile.credits
		main._on_salvage_pressed()
		await _frames(2)
		_check(profile.credits > credits_before and int(profile.derelicts[0].salvaged) == 2 and main.hud.loot.visible,
			"G by it salvages it again: +%d cr, salvaged twice" % (profile.credits - credits_before))
		main.hud.loot.close()
		var again := profile.credits
		main._on_salvage_pressed()
		await _frames(2)
		_check(profile.credits == again, "but only once per sortie")
		if main.hud.loot.visible:
			main.hud.loot.close()

	# 7. What is on disk agrees.
	var errors := PackedStringArray()
	var saved := PlayerProfile.load_file(PlayerProfile.path, errors)
	_check(saved != null and saved.spare_parts == profile.spare_parts and saved.missions_completed == 1
		and saved.vessel.blueprint.equipment.size() == player.systems.blueprint.equipment.size() and not saved.vessel.is_damaged(),
		"the saved profile matches: parts, mission count, refitted and repaired vessel")

	# 8. Death: only the hold is lost; the same design comes back for a fee.
	profile.vessel.cargo = {"spare_parts": 25}
	var credits_before_loss := profile.credits
	var fee := profile.respawn_fee(ConstructionCatalog.default_catalog())
	main.world.get_ship(Main.PLAYER_ID).status = ShipState.Status.ENTERED_ATMOSPHERE
	# Earth: the re-entry cutscene first (play-test batch 10), then the debrief.
	Engine.time_scale = 8.0
	var waited := 0
	while not main.hud.debrief.visible and waited < 5000:
		await process_frame
		waited += 1
	Engine.time_scale = 1.0
	_check(main._reentry_s >= Main.REENTRY_CUTSCENE_S, "the re-entry cutscene played first (%.1f s)" % main._reentry_s)
	_check(main.hud.debrief.visible and main.hud.debrief.text().contains("VESSEL LOST") and main.hud.debrief.text().contains("Respawn fee"),
		"losing the ship shows the debrief with the fee")
	_check(profile.credits == credits_before_loss - fee and profile.vessel.cargo_is_empty(), "fee %d credits paid; the hold's 25 parts lost" % fee)
	await _press("restart_scenario")
	await _frames(3)
	var reborn := main.world.get_ship(Main.PLAYER_ID)
	_check(reborn.is_active() and reborn.systems.blueprint.equipment.size() == player.systems.blueprint.equipment.size() and not main.hud.debrief.visible,
		"Backspace respawns the same design")
	# Dry tanks: going home (Backspace docks first, a jump) calls the tow.
	reborn.propellant_kg = 0.0
	main.jump_reserve_kg = 0.0
	profile.credits = 1000
	var tow := JumpDrive.standard().tow_credits(reborn.mass_kg())
	await _press("restart_scenario")
	await _frames(3)
	_check(profile.credits == 1000 - tow - _wages_paid(profile), "dry tanks: the rescue tow brings the ship home for %d credits (left %d, after wages)" % [tow, profile.credits])
	# Stranded under fire (play-test batch 8): the jump is blocked, but held
	# on, B calls a rescue tow at hazard pay.
	var me := main.world.get_ship(Main.PLAYER_ID)
	me.propellant_kg = me.config.propellant_capacity_kg
	profile.credits = 5000
	main.set_target_hostile(true, "smoke test")
	var hazard_fee := 0
	var saw_blocked := false
	Engine.time_scale = 8.0
	Input.action_press("open_shipyard")
	for i in 900:
		if current_scene is Shipyard:
			break
		main._last_enemy_fire = main.world.sim_time  # someone keeps shooting
		if main.in_combat() and main.world.has_ship(Main.PLAYER_ID):
			hazard_fee = main.rescue_tow_fee(main.world.get_ship(Main.PLAYER_ID))
			saw_blocked = saw_blocked or main.hud.jump_state.has("blocked")
		await process_frame
	Input.action_release("open_shipyard")
	Engine.time_scale = 1.0
	await _frames(3)
	var base_fee := JumpDrive.standard().tow_credits(me.mass_kg() + main.jump_reserve_kg) if is_instance_valid(main) else 0
	_check(saw_blocked and current_scene is Shipyard and hazard_fee > 0 and profile.credits == 5000 - hazard_fee - _wages_paid(profile),
		"under fire: the jump is blocked, holding on calls the tow — home for %d cr hazard pay (left %d)" % [hazard_fee, profile.credits])
	# Tab › Call rescue tow: twice to confirm; out of a fight, the plain fee.
	var yard2 := current_scene as Shipyard
	if yard2 != null:
		yard2.debrief.hide_debrief()
		_check(yard2.launch(), "launched again")
		await _frames(4)
		var main2 := current_scene as Main
		profile.credits = 5000
		var fee2 := main2.rescue_tow_fee(main2.world.get_ship(Main.PLAYER_ID))
		main2.request_rescue_tow()
		await _frames(2)
		_check(current_scene == main2 and profile.credits == 5000, "the first press only quotes the fee (%d cr)" % fee2)
		main2.request_rescue_tow()
		await _frames(3)
		_check(current_scene is Shipyard and profile.credits == 5000 - fee2 - _wages_paid(profile) and fee2 < hazard_fee,
			"the second calls it: home for %d cr, no hazard pay out of a fight (left %d)" % [fee2, profile.credits])
	# Milestone 13: a retrieve contract — the pod in flight, G stows it, paid at the dock.
	var yard3 := current_scene as Shipyard
	if yard3 != null:
		yard3.debrief.hide_debrief()
		profile.active_contract = {}
		var offer := ContractBoard._retrieve_offer(profile, RandomNumberGenerator.new(), [profile.location], 9)
		profile.board = [offer]
		_check(ContractBoard.accept(profile, str(offer.id)) == "", "a retrieve contract accepted")
		_check(yard3.launch(), "launched for the pod")
		await _frames(4)
		var main3 := current_scene as Main
		var pod := main3.world.get_ship(Main.POD_ID) if main3 != null and main3.world.has_ship(Main.POD_ID) else null
		_check(pod != null and main3.hud.derelict_ids.has(Main.POD_ID), "the pod is out there, marked")
		if pod != null:
			var me3 := main3.world.get_ship(Main.PLAYER_ID)
			var far := main3.recover_pod(me3)
			_check(far.contains("close to"), "from %.1f km, G says to close (%s)" % [pod.position.distance_to(me3.position) / 1000.0, far])
			pod.position = me3.position + Vector3(0, 0, -300)
			pod.velocity = me3.velocity
			main3._on_salvage_pressed()
			_check(not main3.world.has_ship(Main.POD_ID) and profile.vessel.cargo.has("freight"), "G alongside: stowed in the hold")
			var credits3 := profile.credits
			main3.open_shipyard()
			await _frames(4)
			_check(profile.active_contract.is_empty() and not profile.vessel.cargo.has("freight")
				and profile.credits == credits3 + int(offer.credits) - _wages_paid(profile),
				"docked at the station that wanted it: paid %d cr" % int(offer.credits))
	_finish()


## The crew's wages paid on the last docking (play-test batch 9), from the
## vessel's record.
func _wages_paid(p: PlayerProfile) -> int:
	for k in range(p.vessel.history.size() - 1, -1, -1):
		var line := p.vessel.history[k]
		if line.begins_with("Wages: "):
			return line.trim_prefix("Wages: ").get_slice(" ", 0).to_int()
	return 0


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + PlayerProfile.BACKUP_SUFFIX))
	print("smoke_campaign: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
