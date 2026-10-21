extends TestCase
## Measures: play-test batch 9, part 5 — the economy. The tech tree
## branches from one root left to right: each node's first level needs its
## parent, each later level the one before; upgrades bought before the tree
## branched are kept; the newer nodes do what they say. The bank: deposits
## compound a little each sortie; loans are paid off in instalments on
## docking (a shortfall costs extra), or repaid early; both are saved (v13).


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _profile() -> PlayerProfile:
	var p := PlayerProfile.new(5)
	p.ensure_vessel(BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray()))
	return p


func test_the_tree_branches_from_one_root() -> void:
	var columns := {}
	var total := 0
	for n in TechTree.NODES:
		for k in range(1, TechTree.levels(n.id) + 1):
			var t := TechTree.tier(n.id, k)
			columns[t] = int(columns.get(t, 0)) + 1
			total += 1
			if k == 1 and n.id != "charter":
				var req := TechTree.requirement(n.id, 1)
				assert_true(TechTree.tier(str(req[0]), int(req[1])) < t, "%s comes after %s %d" % [n.id, req[0], req[1]])
	var keys := columns.keys()
	keys.sort()
	var widths := keys.map(func(t: int) -> int: return columns[t])
	print("    measured: %d nodes in %d levels; nodes per column, left to right: %s" % [TechTree.NODES.size(), total, widths])
	assert_true(columns[0] == 1 and widths.max() >= 4 and TechTree.NODES.size() >= 14, "one root, widening to the right")
	var p := _profile()
	p.credits = 100_000
	assert_true(p.buy_tech("reactor").contains("Tuned thrusters"), "a node needs its parent: %s" % p.buy_tech("reactor"))
	assert_true(p.buy_tech("thrusters").contains("charter"), "everything starts from the charter")
	var credits := p.credits
	assert_true(p.buy_tech("charter") == "" and p.credits == credits - TechTree.CHARTER_COST and p.buy_tech("charter").contains("top"), "the charter, once")
	assert_true(p.buy_tech("thrusters") == "" and p.buy_tech("reactor") == "", "then down a branch")
	assert_true(p.buy_tech("jump").contains("Tuned thrusters II"), "jump calibration after Tuned thrusters II")
	# Upgrades from before the tree branched are kept, and go on from there.
	var old := _profile()
	old.tech = {"reactor": 2}
	old.credits = 10_000
	assert_true(old.tech_level("reactor") == 2 and old.buy_tech("reactor") == "" and old.tech_level("reactor") == 3, "an old level is kept and built on")
	# The page draws a node per level.
	var g := TechGraph.new()
	g.profile = p
	g.rebuild()
	print("    measured: the graph %.0f × %.0f px, %d nodes" % [g.custom_minimum_size.x, g.custom_minimum_size.y, g.get_child_count()])
	assert_true(g.get_child_count() == total and g.custom_minimum_size.x >= keys.size() * TechGraph.COLUMN_W - 1.0, "a node per level, a column per tier")
	g.free()


func test_the_newer_nodes_do_what_they_say() -> void:
	var p := _profile()
	p.vessel.ensure_crew(_catalog())
	var dv := p.jump_dv("moon")
	var wages := p.wages()
	var train := p.training_cost(0)
	p.tech = {"charter": 1, "thrusters": 2, "jump": 3, "damage_control": 1, "medicine": 1, "academy": 2, "welfare": 1}
	print("    measured: jump %.0f → %.0f m/s; wages %d → %d cr; training %d → %d cr" % [dv, p.jump_dv("moon"), wages, p.wages(), train, p.training_cost(0)])
	assert_near(p.jump_dv("moon"), dv * 0.85, 0.01, "jump calibration III: −15 % Δv (m/s)")
	assert_true(p.wages() == roundi(wages * 0.8) and p.training_cost(0) == roundi(train * 0.6), "welfare −20 %, academy II −40 %")
	# Ship systems: sensors and point defence.
	var bp := BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, PackedStringArray())
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var sys := ShipSystems.create(bp, grid, stats, stats.to_ship_config("s"))
	var range0 := sys.sensor_range_m()
	var pd0 := sys.effective_config().pd_gun.rate_of_fire_rpm
	sys.tech = {"sensors": 2, "pd_control": 3}
	sys.invalidate()
	print("    measured: sensors %.0f → %.0f km; PD %.0f → %.0f rpm" % [range0 / 1000.0, sys.sensor_range_m() / 1000.0, pd0, sys.effective_config().pd_gun.rate_of_fire_rpm])
	assert_near(sys.sensor_range_m(), range0 * 1.2, 1.0, "sensor suites II: +20 % (m)")
	assert_near(sys.effective_config().pd_gun.rate_of_fire_rpm, pd0 * 1.3, 0.01, "PD fire control III: +30 % (rpm)")
	assert_true(stats.pd_gun.rate_of_fire_rpm == pd0, "the shared gun data is not changed")
	assert_near(TechTree.factor("bounty", 2), 1.2, 1e-6, "bounty licences II: +20 %")
	assert_near(TechTree.factor("hangar_crews", 1), 1.15, 1e-6, "hangar crews I: +15 % turnaround")


func test_the_bank() -> void:
	var p := _profile()
	p.credits = 2000
	assert_true(p.deposit(1000) == "" and p.credits == 1000 and p.bank_deposit == 1000, "deposited")
	assert_true(p.deposit(5000) != "" and p.withdraw(5000) != "", "not more than there is")
	p.bank_sortie()
	p.bank_sortie()
	print("    measured: 1,000 cr deposited, after two sorties %d" % p.bank_deposit)
	assert_true(p.bank_deposit == 1020, "1 % a sortie, compounding")
	assert_true(p.withdraw(20) == "" and p.credits == 1020, "withdrawn")
	# A loan paid off in instalments.
	var q := _profile()
	q.credits = 10_000
	assert_true(q.take_loan("dock_credit") == "" and q.credits == 11_000 and q.debt() == 1000, "1,000 cr borrowed")
	assert_true(q.take_loan("dock_credit").contains("already"), "one of each at a time")
	var paid := 0
	for k in 5:
		var before := q.credits
		q.bank_sortie()
		paid += before - q.credits
	print("    measured: Dockyard credit 1,000 cr at 5 %% over 5 sorties — %d cr paid in all; owed %d" % [paid, q.debt()])
	assert_true(q.debt() == 0 and q.loans.is_empty() and paid > 1000 and paid < 1200, "paid off on time, with interest")
	# A shortfall costs extra; early repayment.
	var r := _profile()
	r.credits = 0
	r.take_loan("guild_loan")
	r.credits = 0
	r.bank_sortie()
	var owed := r.debt()
	print("    measured: a missed instalment — owed %d (was 5,000; 4 %% interest and the penalty)" % owed)
	assert_true(owed > 5200, "interest and a penalty")
	r.credits = owed
	assert_true(r.repay("guild_loan") == "" and r.debt() == 0 and r.credits == 0, "repaid early in full")


func test_the_bank_is_saved_and_v12_saves_load() -> void:
	var path := "user://test_b9_bank_profile.json"
	for s in ["", ".bak", ".tmp", ".v12"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
	var p := _profile()
	var d := p.to_dict()
	d.schema_version = 12
	d.erase("bank_deposit")
	d.erase("loans")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = path
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	assert_true(q.loaded_schema == 12 and q.bank_deposit == 0 and q.loans.is_empty() and FileAccess.file_exists(path + ".v12"), "a v12 save: no deposit, no loans, the original kept")
	q.credits = 500
	q.deposit(300)
	q.take_loan("mortgage")
	var r := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(q.to_dict())), PackedStringArray())
	assert_true(r.bank_deposit == 300 and r.loans.size() == 1 and int(r.loan("mortgage").balance) == 25_000, "deposit and loan saved at v%d" % PlayerProfile.SCHEMA_VERSION)
	for s in ["", ".bak", ".tmp", ".v12"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + s))
