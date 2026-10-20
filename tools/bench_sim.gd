extends SceneTree
## Simulation frame-time profile under load: two frigates trading fire with
## every gun and point defence, plus a salvo of missiles, and the cost of a
## tick measured as the rounds pile up.
##   godot --headless --path . -s res://tools/bench_sim.gd
## Prints ms per tick (mean and worst) by rounds in flight; exits non-zero
## if a tick averages over BUDGET_MS (the 8 ms simulation share of a 60 Hz
## frame). A second scenario: a three-hostile encounter (Milestone 10).

const DT := 1.0 / 60.0
const BUDGET_MS := 8.0


func _initialize() -> void:
	var result := run(12, 1800)
	for row in result.rows:
		print("  rounds %4d · missiles %2d · %.2f ms mean · %.2f ms worst" % [row.rounds, row.missiles, row.mean_ms, row.worst_ms])
	print("bench_sim: duel %.2f ms mean per tick (budget %.0f ms)" % [result.mean_ms, BUDGET_MS])
	var enc := run_encounter(3, 3600)
	for row in enc.rows:
		print("  ships %d · craft %2d · missiles %2d · rounds %4d · %.2f ms mean · %.2f ms worst" % [row.ships, row.craft, row.missiles, row.rounds,
			row.mean_ms, row.worst_ms])
	print("bench_sim: 3-hostile encounter %.2f ms mean, %.2f ms worst per tick (budget %.0f ms); peak %d missiles, %d craft" % [
		enc.mean_ms, enc.worst_ms, BUDGET_MS, enc.peak_missiles, enc.peak_craft])
	quit(0 if result.mean_ms <= BUDGET_MS and enc.mean_ms <= BUDGET_MS else 1)


## A Milestone 10 encounter: the player's frigate against `hostiles` armed
## frigates (missile rack each, fighters launched), every gun firing, each
## hostile fighting its role and firing salvos by its policy; both sides'
## point defence on. {rows, mean_ms, worst_ms, peak_missiles, peak_craft}.
static func run_encounter(hostiles: int, ticks: int) -> Dictionary:
	var catalog := ConstructionCatalog.default_catalog()
	var world := WorldSimulation.new(DT)
	var player := _armed_ship(&"player", Vector3.ZERO, Quaternion.IDENTITY, catalog)
	player.side = &"player"
	world.add_ship(player)
	var enemies: Array[ShipState] = []
	var policies: Array[ShipPolicy] = []
	var salvos: Array = []
	for i in hostiles:
		var pos := Vector3(-1800.0 + 1800.0 * i, 300.0 * i, -3000.0 - 600.0 * i)
		var e := _armed_ship(StringName("target_%02d" % (i + 1)), pos, Quaternion(Vector3.UP, PI), catalog)
		e.side = &"hostile"
		e.policy = EnemyFactory.policy(9, i)
		e.policy.salvo_interval_s = 10.0
		world.add_ship(e)
		var wing := AirWing.for_ship(e)
		wing.target_id = &"player"
		world.wings.append(wing)
		for c in wing.crafts:
			if not c.is_drone():
				wing.launch(world, c)
		enemies.append(e)
		policies.append(e.policy)
		salvos.append(null)
	var rows: Array[Dictionary] = []
	var total := 0.0
	var worst := 0.0
	var window := 0.0
	var window_worst := 0.0
	var peak_missiles := 0
	var peak_craft := 0
	var next_salvo := []
	for i in hostiles:
		next_salvo.append(1.0 + 2.0 * i)
	for tick in ticks:
		var t := world.sim_time
		if player.is_active():
			var aim := GunneryAI.command(player, enemies[0])
			aim.fire = true
			world.set_input(&"player", aim)
		for i in hostiles:
			var e := enemies[i]
			if not e.is_active():
				continue
			world.set_input(e.id, GunneryAI.combat(e, player, t, policies[i]))
			if salvos[i] == null and t >= next_salvo[i]:
				salvos[i] = MissileSalvo.start(e.id, &"player", policies[i].salvo_mode, [], policies[i].salvo_count)
				next_salvo[i] = t + policies[i].salvo_interval_s
			if salvos[i] != null:
				(salvos[i] as MissileSalvo).step(world)
				if (salvos[i] as MissileSalvo).done():
					salvos[i] = null
		var t0 := Time.get_ticks_usec()
		world.step()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		window += ms
		worst = maxf(worst, ms)
		window_worst = maxf(window_worst, ms)
		world.take_hit_events()
		world.take_link_events()
		world.take_bursts()
		var craft := 0
		for w in world.wings:
			craft += w.flying().size()
		peak_missiles = maxi(peak_missiles, world.missiles.size())
		peak_craft = maxi(peak_craft, craft)
		if (tick + 1) % 600 == 0:
			var ships := 0
			for id in world.ship_ids():
				var s := world.get_ship(id)
				if s.is_active() and s.systems != null:
					ships += 1
			rows.append({"ships": ships, "craft": craft, "missiles": world.missiles.size(), "rounds": world.projectiles().size(),
				"mean_ms": window / 600.0, "worst_ms": window_worst})
			window = 0.0
			window_worst = 0.0
	return {"rows": rows, "mean_ms": total / ticks, "worst_ms": worst, "peak_missiles": peak_missiles, "peak_craft": peak_craft}


static func _armed_ship(id: StringName, pos: Vector3, attitude: Quaternion, catalog: ConstructionCatalog) -> ShipState:
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	EnemyFactory._fit_launcher(bp, catalog, &"missile_rack", rng)
	var grid := ShipGrid.build(bp, catalog)
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos, Vector3.ZERO, attitude)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	return ship


## Fly `ticks` ticks with `missiles` launched in the first seconds; a row of
## timings every 300 ticks. {rows, mean_ms}.
static func run(missiles: int, ticks: int) -> Dictionary:
	var catalog := ConstructionCatalog.default_catalog()
	var world := WorldSimulation.new(DT)
	for spec in [[&"a", Vector3.ZERO, Quaternion.IDENTITY], [&"b", Vector3(0, 0, -2500), Quaternion(Vector3.UP, PI)]]:
		var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		EnemyFactory._fit_launcher(bp, catalog, &"missile_rack", rng)
		EnemyFactory._fit_launcher(bp, catalog, &"missile_rack", rng)
		EnemyFactory._fit_launcher(bp, catalog, &"missile_rack", rng)
		var grid := ShipGrid.build(bp, catalog)
		var stats := ShipStats.compute(bp, grid)
		var cfg := stats.to_ship_config(bp.name)
		var ship := ShipState.create(spec[0], String(spec[0]), cfg, spec[1], Vector3.ZERO, spec[2])
		ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
		world.add_ship(ship)
	var launched := 0
	var rows: Array[Dictionary] = []
	var total := 0.0
	var window := 0.0
	var worst := 0.0
	for i in ticks:
		for pair in [[&"a", &"b"], [&"b", &"a"]]:
			var me := world.get_ship(pair[0])
			var other := world.get_ship(pair[1])
			if me != null and other != null and me.is_active() and other.is_active():
				var input := GunneryAI.command(me, other)
				input.fire = true
				world.set_input(pair[0], input)
				if launched < missiles and world.launch_missile(pair[0], pair[1]) == "":
					launched += 1
		var t0 := Time.get_ticks_usec()
		world.step()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		window += ms
		worst = maxf(worst, ms)
		world.take_hit_events()
		world.take_link_events()
		world.take_bursts()
		if (i + 1) % 300 == 0:
			rows.append({"rounds": world.projectiles().size(), "missiles": world.missiles.size(), "mean_ms": window / 300.0, "worst_ms": worst})
			window = 0.0
			worst = 0.0
	return {"rows": rows, "mean_ms": total / ticks}
