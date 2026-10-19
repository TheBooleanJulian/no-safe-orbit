extends SceneTree
## Simulation frame-time profile under load: two frigates trading fire with
## every gun and point defence, plus a salvo of missiles, and the cost of a
## tick measured as the rounds pile up.
##   godot --headless --path . -s res://tools/bench_sim.gd
## Prints ms per tick (mean and worst) by rounds in flight; exits non-zero
## if a tick averages over BUDGET_MS (a 60 Hz frame).

const DT := 1.0 / 60.0
const BUDGET_MS := 16.0


func _initialize() -> void:
	var result := run(12, 1800)
	for row in result.rows:
		print("  rounds %4d · missiles %2d · %.2f ms mean · %.2f ms worst" % [row.rounds, row.missiles, row.mean_ms, row.worst_ms])
	print("bench_sim: overall %.2f ms mean per tick (budget %.0f ms)" % [result.mean_ms, BUDGET_MS])
	quit(0 if result.mean_ms <= BUDGET_MS else 1)


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
