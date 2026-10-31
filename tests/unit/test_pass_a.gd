extends TestCase
## Measures: Pass A — the alert grammar (short, one value, a key chip), the
## queue (priority, deduplication, at most three shown, hysteresis, level
## changes, acknowledging), every HUD alert appearing with its condition and
## clearing when it is resolved, a sound for every alert class, recorded
## CC0 samples in every slot with synthesis as the fallback, and alarms
## ducking the other buses.

const DT := 1.0 / 60.0
const DANGER := AlertQueue.Level.DANGER
const CAUTION := AlertQueue.Level.CAUTION
const ADVISORY := AlertQueue.Level.ADVISORY


func _keys(alerts: Array) -> Array:
	return alerts.map(func(a: AlertQueue.Alert) -> StringName: return a.key)


func test_grammar_is_short() -> void:
	var a := AlertQueue.make(&"missile", &"threat", DANGER, "MSL", "2.1s", "040↑", "[SPC]")
	assert_true(a.text() == "MSL 2.1s 040↑ [SPC]", "noun, value, direction, key (%s)" % a.text())
	var long := AlertQueue.make(&"x", &"info", CAUTION, "VERYLONGNOUN", "1234567890", "359↓", "[Tab]")
	assert_true(long.text().length() <= AlertQueue.MAX_TEXT, "never over %d characters (%d)" % [AlertQueue.MAX_TEXT, long.text().length()])


func test_priority_dedupe_and_three_at_most() -> void:
	var q := AlertQueue.new()
	var raw: Array[AlertQueue.Alert] = [
		AlertQueue.make(&"hold", &"info", CAUTION, "HOLD", "+3m³"),
		AlertQueue.make(&"fire", &"damage", DANGER, "FIRE", "r12"),
		AlertQueue.make(&"round", &"threat", DANGER, "RND", "0.4s"),
		AlertQueue.make(&"power", &"systems", CAUTION, "PWR", "−300kW"),
		AlertQueue.make(&"round", &"threat", CAUTION, "RND", "0.5s"),
		AlertQueue.make(&"hit", &"damage", ADVISORY, "HIT", "ricochet"),
	]
	q.update(raw, 0.0)
	var shown := q.visible()
	assert_true(_keys(shown) == [&"round", &"fire", &"power"],
		"danger first (threat before damage), then caution (systems before info); three at most: %s" % [_keys(shown)])
	assert_true(q.all_active().size() == 5, "the duplicate round is one alert (%d active)" % q.all_active().size())
	assert_true(shown[0].level == DANGER, "a duplicate keeps the higher level")


func test_hysteresis_and_levels() -> void:
	var q := AlertQueue.new()
	var fire: Array[AlertQueue.Alert] = [AlertQueue.make(&"fire", &"damage", DANGER, "FIRE", "r12")]
	q.update(fire, 0.0)
	assert_true(q.raised.size() == 1, "a new alert is raised (for its sound)")
	q.update(fire, 0.1)
	assert_true(q.raised.is_empty(), "and not raised again while it lasts")
	var none: Array[AlertQueue.Alert] = []
	q.update(none, 0.5)
	assert_true(q.has(&"fire"), "gone for 0.4 s: still shown (no flicker)")
	q.update(none, 0.95)
	assert_true(not q.has(&"fire"), "gone for %.1f s: cleared" % AlertQueue.CLEAR_DELAY_S)
	# Escalates at once, de-escalates only after a second.
	q.update([AlertQueue.make(&"reactor", &"systems", CAUTION, "HOT", "1220K")] as Array[AlertQueue.Alert], 2.0)
	q.update([AlertQueue.make(&"reactor", &"systems", DANGER, "SCRAM", "1450K")] as Array[AlertQueue.Alert], 2.1)
	assert_true(q.visible()[0].level == DANGER and q.raised.size() == 1, "caution → danger at once, and sounded")
	q.update([AlertQueue.make(&"reactor", &"systems", CAUTION, "HOT", "1300K")] as Array[AlertQueue.Alert], 2.2)
	assert_true(q.visible()[0].level == DANGER, "not lowered on one frame")
	q.update([AlertQueue.make(&"reactor", &"systems", CAUTION, "HOT", "1290K")] as Array[AlertQueue.Alert], 3.3)
	assert_true(q.visible()[0].level == CAUTION, "lowered after a steady second")


func test_acknowledge() -> void:
	var q := AlertQueue.new()
	var raw: Array[AlertQueue.Alert] = [AlertQueue.make(&"hold", &"info", CAUTION, "HOLD", "+3m³"), AlertQueue.make(&"round", &"threat", DANGER, "RND", "1s")]
	q.update(raw, 0.0)
	assert_true(q.acknowledge() and _keys(q.visible()) == [&"round"], "[.] hides the caution, not the danger: %s" % [_keys(q.visible())])
	assert_true(not q.acknowledge(), "a danger can't be acknowledged")
	q.update([AlertQueue.make(&"hold", &"info", DANGER, "HOLD", "+9m³")] as Array[AlertQueue.Alert], 0.1)
	assert_true(q.has(&"hold") and _keys(q.visible()).has(&"hold"), "an escalation brings it back")


func _ship(id: StringName) -> ShipState:
	var bp := BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())
	var grid := ShipGrid.build(bp, ConstructionCatalog.default_catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(String(id))
	var s := ShipState.create(id, String(id), cfg)
	s.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return s


func _hud_alerts(hud: Hud, world: WorldSimulation, player: ShipState) -> Array:
	return _keys(hud._alerts(world, player, null))


func test_every_alert_follows_its_condition() -> void:
	var hud := Hud.new()
	var world := WorldSimulation.new(DT)
	var player := _ship(&"player")
	world.add_ship(player)
	var other := _ship(&"target_01")
	other.position = Vector3(0, 0, -3000)
	world.add_ship(other)
	var sys := player.systems
	assert_true(_hud_alerts(hud, world, player).is_empty(), "a quiet ship: no alerts (%s)" % [_hud_alerts(hud, world, player)])
	var checks := []
	# Propellant.
	var prop := player.propellant_kg
	player.propellant_kg = 0.0
	checks.append(["prop", _hud_alerts(hud, world, player).has(&"prop")])
	player.propellant_kg = prop
	checks.append(["prop cleared", not _hud_alerts(hud, world, player).has(&"prop")])
	# A round on a collision course: no alert since play-test batch 9 ("remove
	# RND from critical screen alerts").
	var shot := ProjectileState.new()
	shot.shooter_id = &"target_01"
	shot.position = Vector3(0, 0, -1500)
	shot.prev_position = shot.position
	shot.velocity = Vector3(0, 0, 1500)
	shot.weapon = KineticCannonConfig.new()
	world._rounds.append(shot)
	checks.append(["no round alert", not _hud_alerts(hud, world, player).has(&"round")])
	world._rounds.clear()
	# Reactor scram.
	sys.reactor_state = ShipSystems.Reactor.SCRAM
	checks.append(["scram", _hud_alerts(hud, world, player).has(&"reactor")])
	sys.reactor_state = ShipSystems.Reactor.NORMAL
	checks.append(["scram cleared", not _hud_alerts(hud, world, player).has(&"reactor")])
	# Fire.
	sys.fires[0] = {"burn_s": 0.0, "smoulder_s": 0.0}
	checks.append(["fire", _hud_alerts(hud, world, player).has(&"fire")])
	sys.fires.clear()
	checks.append(["fire cleared", not _hud_alerts(hud, world, player).has(&"fire")])
	# Jump drive.
	hud.jump_state = {"progress": 0.4, "left_s": 3.0, "waiting": PackedStringArray()}
	checks.append(["jump", _hud_alerts(hud, world, player).has(&"jump")])
	hud.jump_state = {}
	checks.append(["jump cleared", not _hud_alerts(hud, world, player).has(&"jump")])
	var bad := checks.filter(func(c: Array) -> bool: return not c[1]).map(func(c: Array) -> String: return str(c[0]))
	assert_true(bad.is_empty(), "every alert appears with its condition and clears with it; failed: %s" % [bad])
	# Several at once, each in its few words.
	player.propellant_kg = 0.0
	sys.fires[0] = {"burn_s": 0.0, "smoulder_s": 0.0}
	sys.reactor_state = ShipSystems.Reactor.SCRAM
	for a in hud._alerts(world, player, null):
		assert_true(a.text().length() <= AlertQueue.MAX_TEXT, "%s fits (%s)" % [a.key, a.text()])
	hud.free()


func test_every_class_has_a_sound_and_samples_fill_the_slots() -> void:
	for cls in AlertQueue.CLASSES:
		assert_true(ShipAudio.ALARMS.has(cls), "alert class %s has an alarm" % cls)
	var audio := ShipAudio.new()
	audio._ready()
	var missing := PackedStringArray()
	for slot: String in ShipAudio.SAMPLES:
		if not audio.sampled.has(slot):
			missing.append(slot)
	for cls in AlertQueue.CLASSES:
		if not audio.sampled.has("alarm_%s" % cls):
			missing.append("alarm_%s" % cls)
	for loop in [ShipAudio.ENGINE_SAMPLE, ShipAudio.RCS_SAMPLE, ShipAudio.AMBIENCE_SAMPLE]:
		if not audio.sampled.has(loop):
			missing.append(loop)
	print("    measured: %d slots from recorded samples; missing %s" % [audio.sampled.size(), missing])
	assert_true(missing.is_empty(), "every slot plays a recorded sample (missing: %s)" % ", ".join(missing))
	assert_true((audio._engine.stream as AudioStreamOggVorbis).loop and (audio._ambience.stream as AudioStreamOggVorbis).loop,
		"the engine and the machinery hum loop")
	# Ducking: an alarm lowers the effects and ambience, then they come back.
	for bus in [ShipAudio.BUS_EFFECTS, ShipAudio.BUS_ALARMS, ShipAudio.BUS_AMBIENCE]:
		assert_true(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	audio.alarm(&"threat", DANGER)
	var effects := AudioServer.get_bus_index(ShipAudio.BUS_EFFECTS)
	assert_true(audio.ducking() and AudioServer.get_bus_volume_db(effects) <= GameSettings.volume_db(ShipAudio.BUS_EFFECTS) + ShipAudio.DUCK_DB + 0.01,
		"an alarm ducks the effects (%.1f dB)" % AudioServer.get_bus_volume_db(effects))
	assert_true(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(ShipAudio.BUS_ALARMS)) == 0.0, "the alarm itself is not ducked")
	assert_true(audio._pending.size() == 3, "a danger sounds three blips (%d)" % audio._pending.size())
	for i in 200:
		audio._process(0.02)
	assert_true(not audio.ducking() and is_equal_approx(AudioServer.get_bus_volume_db(effects), GameSettings.volume_db(ShipAudio.BUS_EFFECTS)), "and the effects come back")
	var total := 0
	for f in DirAccess.get_files_at("res://data/audio"):
		if f.ends_with(".ogg"):
			total += FileAccess.get_file_as_bytes("res://data/audio/" + f).size()
	print("    measured: audio samples %.0f kB" % (total / 1024.0))
	assert_true(total < 1_000_000, "the sample budget stays under 1 MB (%.0f kB)" % (total / 1024.0))
	audio.free()
