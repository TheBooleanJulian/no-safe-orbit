extends SceneTree
## Frame-time profile of the real flight scene under load, with rendering:
## the player's frigate (missile rack and saturation pod, fighters out)
## against a three-ship encounter, everyone's guns, fighters and missile
## salvos going. Needs a display (it opens a window); runs on a scratch
## profile, never the player's save.
##   godot --path . -s res://tools/profile_frames.gd
## Prints frame time (mean, 95th percentile, worst) and where it went
## (Main.frame_ms sections), with what was in flight.
##   -- --carriers : the player's Carrier (four hangars) against three enemy
##                   carriers: the many-fighters fight (play-test batch 6).
##   -- --carrier  : the player's Carrier against the usual three frigates.

const SECONDS := 40.0
const SALVO_EVERY_S := 8.0
## Frames longer than this are listed with their sections.
const SPIKE_MS := 50.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerProfile.path = "user://profile_frames_profile.json"
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	Main.profile = null
	var p := Main.get_profile()
	p.missions_completed = 6
	p.encounter_size = 3
	var carriers := OS.get_cmdline_user_args().has("--carriers")
	var own_carrier := carriers or OS.get_cmdline_user_args().has("--carrier")
	var bp := BlueprintIO.load_file("res://data/blueprints/carrier_mk1.json" if own_carrier else BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	if carriers:
		# In memory only: Earth's traffic becomes carriers for this run.
		Location.by_id("earth").enemy_templates = PackedStringArray(["carrier_mk1.json"])
		Location.by_id("earth").enemy_weights = PackedFloat32Array([1.0])
	var rng := RandomNumberGenerator.new()
	EnemyFactory._fit_launcher(bp, ConstructionCatalog.default_catalog(), &"missile_rack", rng)
	EnemyFactory._fit_launcher(bp, ConstructionCatalog.default_catalog(), &"saturation_pod", rng)
	Main.launch_blueprint = bp
	root.size = Vector2i(1600, 900)
	# Uncapped, so the numbers are the frame's real cost, not the refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	main.set_target_hostile(true, "profile")
	main.player_wing.launch_all(main.world)
	Input.action_press("fire")
	var frames: Array[float] = []
	var spikes: PackedStringArray = []
	var sections := {}
	var worst_sections := {}
	var peak := {"missiles": 0, "craft": 0, "rounds": 0}
	var draw_calls := 0.0
	var render := {"cpu": 0.0, "gpu": 0.0, "process": 0.0, "physics": 0.0}
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	main.world.take_phase_ms()
	var next_salvo := 2.0
	var t_end := Time.get_ticks_msec() + SECONDS * 1000.0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		main.aim_cursor_at_lead()
		if main.world.sim_time >= next_salvo and main.salvo == null:
			main.salvo = MissileSalvo.start(Main.PLAYER_ID, main.encounter.selected, MissileSalvo.Mode.ALL, [], 12)
			next_salvo = main.world.sim_time + SALVO_EVERY_S
		for c in main.encounter.contacts:
			if c.salvo == null:
				c.salvo_at = 0.0
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		if frames[-1] > SPIKE_MS:
			spikes.append("T+%.1f s %.0f ms %s" % [main.world.sim_time, frames[-1], main.frame_ms])
		last = now
		for k in main.frame_ms:
			sections[k] = float(sections.get(k, 0.0)) + float(main.frame_ms[k])
			worst_sections[k] = maxf(float(worst_sections.get(k, 0.0)), float(main.frame_ms[k]))
		var craft := 0
		for w in main.world.wings:
			craft += w.flying().size()
		peak.missiles = maxi(peak.missiles, main.world.missiles.size())
		peak.craft = maxi(peak.craft, craft)
		peak.rounds = maxi(peak.rounds, main.world.projectiles().size())
		peak["asleep"] = int(peak.get("asleep", 0)) + main.world.rounds_asleep
		peak["awake"] = int(peak.get("awake", 0)) + main.world.rounds_awake
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		render.cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		render.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		render.process += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		render.physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	Input.action_release("fire")
	frames.sort()
	var n := frames.size()
	var mean := 0.0
	for f in frames:
		mean += f
	mean /= maxf(n, 1)
	print("profile_frames: %d frames in %.0f s · mean %.1f ms (%.0f fps) · p95 %.1f ms · worst %.1f ms" % [
		n, SECONDS, mean, 1000.0 / maxf(mean, 0.001), frames[int(n * 0.95)], frames[n - 1]])
	print("  peak in flight: %d missiles · %d craft · %d rounds near · rounds asleep %d %% of round-ticks" % [peak.missiles, peak.craft, peak.rounds,
		roundi(100.0 * int(peak.get("asleep", 0)) / maxf(int(peak.get("asleep", 0)) + int(peak.get("awake", 0)), 1))])
	for k in sections:
		print("  %-6s %6.2f ms mean · %6.1f ms worst" % [k, float(sections.get(k, 0.0)) / maxf(n, 1), float(worst_sections.get(k, 0.0))])
	var phases: Dictionary = main.world.take_phase_ms()
	var ticks := maxf(main.world.tick, 1)
	for k in phases:
		print("  tick:%-14s %6.3f ms per tick" % [k, float(phases[k]) / ticks])
	print("  engine: render cpu %.2f ms · gpu %.2f ms · all _process %.2f ms · physics %.2f ms (means)" % [
		render.cpu / maxf(n, 1), render.gpu / maxf(n, 1), render.process / maxf(n, 1), render.physics / maxf(n, 1)])
	print("  draw calls %.0f mean · objects %d" % [draw_calls / maxf(n, 1), Performance.get_monitor(Performance.OBJECT_COUNT)])
	print("  spikes over %.0f ms: %d" % [SPIKE_MS, spikes.size()])
	for line in spikes.slice(0, 12):
		print("    " + line)
	var by_gun := {}
	for shot in main.world.projectiles():
		var k := shot.weapon.display_name if shot.weapon != null else "?"
		by_gun[k] = int(by_gun.get(k, 0)) + 1
	print("  rounds by gun at the end: %s" % by_gun)
	var census := {}
	_census(main, census)
	print("  scene: %s" % census)
	Main.launch_blueprint = null
	for s in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerProfile.path + s))
	quit()


## Visual node counts (meshes, lights) in the scene, by class.
func _census(node: Node, out: Dictionary) -> void:
	if node is GeometryInstance3D or node is Light3D:
		var key := node.get_class()
		out[key] = int(out.get(key, 0)) + 1
	for child in node.get_children():
		_census(child, out)
