extends TestCase
## Measures: Milestone 4 — salvage loot (cascading weighted rarity, cascade
## down past empty tiers, hard pity, determinism across save/load,
## duplicates), ownership gating in the validator, persistence of the profile
## and of a damaged vessel, service costs / priorities / anti-exploit rules,
## write-offs and vessel loss, salvage rules and yield, workshop field repair.

const TEST_PROFILE := "user://test_profile_unit.json"


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	var errors := PackedStringArray()
	return BlueprintIO.load_file(BlueprintIO.DEFAULT_TEMPLATE, errors)


func _ship(bp: ShipBlueprint, id: StringName = &"s", condition: Dictionary = {}) -> ShipState:
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var systems := ShipSystems.create(bp, grid, stats, cfg)
	if not condition.is_empty():
		systems.apply_condition(condition)
	var ship := ShipState.create(id, String(id), cfg)
	ship.attach_systems(systems)
	return ship


func _report(bp: ShipBlueprint, profile: PlayerProfile) -> ShipValidator.Report:
	var report := ShipValidator.validate(bp, _catalog())
	profile.check_design(bp, _catalog(), report)
	return report


## Template with the dorsal kinetic cannon e41 swapped for `def_id`.
func _with_gun(def_id: StringName) -> ShipBlueprint:
	var bp := _template()
	(bp.find("e41") as ShipBlueprint.PlacedEquipment).def_id = def_id
	return bp


## Template with crew quarters r9 refitted as a workshop.
func _with_workshop() -> ShipBlueprint:
	var bp := _template()
	(bp.find("r9") as ShipBlueprint.PlacedRoom).def_id = &"workshop"
	return bp


func _spares_pool() -> Array[LootRoller.Drop]:
	var pool: Array[LootRoller.Drop] = []
	var d := LootRoller.Drop.new()
	d.kind = &"spares"
	d.rarity = Rarity.Tier.COMMON
	d.amount = 5
	pool.append(d)
	return pool


func _entry(id: StringName, rarity: int, weight: float) -> LootRoller.Drop:
	var d := LootRoller.Drop.new()
	d.kind = &"equipment"
	d.def_id = id
	d.rarity = rarity
	d.weight = weight
	return d


# --- Loot ------------------------------------------------------------------------

func test_tier_probabilities_follow_the_cascade() -> void:
	var p := Rarity.tier_probabilities()
	var expected := [0.70, 0.21, 0.0675, 0.018, 0.0045]
	var total := 0.0
	for t in p.size():
		assert_near(p[t], expected[t], 1e-12, "P(%s)" % Rarity.name_of(t))
		total += p[t]
	assert_near(total, 1.0, 1e-12, "tier probabilities sum")


func test_cascade_roll_matches_the_stated_odds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 200_000
	var counts := [0, 0, 0, 0, 0]
	for i in n:
		counts[LootRoller.roll_tier(rng)] += 1
	var p := Rarity.tier_probabilities()
	for t in p.size():
		var sigma := sqrt(n * p[t] * (1.0 - p[t]))
		assert_near(counts[t], n * p[t], 4.0 * sigma, "%s count in %d rolls (4σ)" % [Rarity.name_of(t), n])


func test_weighted_pick_within_a_tier() -> void:
	var pool := _spares_pool()
	pool.append(_entry(&"light", Rarity.Tier.RARE, 1.0))
	pool.append(_entry(&"heavy", Rarity.Tier.RARE, 3.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var heavy := 0
	var n := 40_000
	for i in n:
		if LootRoller.pick(rng, pool, Rarity.Tier.RARE).def_id == &"heavy":
			heavy += 1
	assert_near(float(heavy) / n, 0.75, 0.01, "weight 3 vs 1 → share of the heavier entry")


func test_empty_tier_cascades_down() -> void:
	var pool := _spares_pool()
	pool.append(_entry(&"only_uncommon", Rarity.Tier.UNCOMMON, 1.0))
	var rng := RandomNumberGenerator.new()
	assert_true(LootRoller.pick(rng, pool, Rarity.Tier.LEGENDARY).def_id == &"only_uncommon",
		"a LEGENDARY roll with no legendary, epic or rare entries falls to the uncommon one")
	assert_true(LootRoller.pick(rng, _spares_pool(), Rarity.Tier.EPIC).kind == &"spares",
		"with only spares in the pool every tier falls to COMMON spares")
	var empty: Array[LootRoller.Drop] = []
	assert_true(LootRoller.pick(rng, empty, Rarity.Tier.RARE) == null, "an empty pool yields nothing")


func test_catalog_pool_covers_every_tier_and_never_drops_common_parts() -> void:
	var pool := LootRoller.build_pool(_catalog())
	for t in Rarity.Tier.size():
		assert_true(pool.any(func(d: LootRoller.Drop) -> bool: return d.rarity == t), "pool has a %s entry" % Rarity.name_of(t))
	for d in pool:
		if d.rarity == Rarity.Tier.COMMON:
			assert_true(d.kind == &"spares", "COMMON tier pays spare parts, not common parts (%s)" % d.def_id)


func test_hard_pity_caps_the_dry_streaks() -> void:
	var pool := LootRoller.build_pool(_catalog())
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pity := {}
	var since_rare := 0
	var since_legendary := 0
	var worst_rare := 0
	var worst_legendary := 0
	var legendaries := 0
	for i in 8000:
		var d := LootRoller.pull(rng, pool, pity)
		since_rare = 0 if d.rarity >= Rarity.Tier.RARE else since_rare + 1
		since_legendary = 0 if d.rarity == Rarity.Tier.LEGENDARY else since_legendary + 1
		legendaries += 1 if d.rarity == Rarity.Tier.LEGENDARY else 0
		worst_rare = maxi(worst_rare, since_rare)
		worst_legendary = maxi(worst_legendary, since_legendary)
	assert_true(worst_rare <= LootRoller.RARE_PITY - 1, "never %d pulls in a row below Rare (worst streak %d)" % [LootRoller.RARE_PITY, worst_rare])
	assert_true(worst_legendary <= LootRoller.LEGENDARY_PITY - 1, "never %d pulls without a Legendary (worst streak %d)" % [LootRoller.LEGENDARY_PITY, worst_legendary])
	assert_true(legendaries >= 8000 / LootRoller.LEGENDARY_PITY, "pity guarantees ≥ %d legendaries in 8000 pulls (got %d)" % [8000 / LootRoller.LEGENDARY_PITY, legendaries])
	assert_true(int(pity.since_rare) == since_rare and int(pity.since_legendary) == since_legendary, "pity counters track the streaks")


func test_pulls_are_deterministic_and_survive_save_and_load() -> void:
	var a := PlayerProfile.new(777)
	a.pull(5, _catalog())
	var json := JSON.stringify(a.to_dict())
	var errors := PackedStringArray()
	var b := PlayerProfile.from_dict(JSON.parse_string(json), errors)
	assert_true(errors.is_empty(), "profile reloads without errors: %s" % ", ".join(errors))
	var seq_a := a.pull(20, _catalog()).map(func(d: LootRoller.Drop) -> String: return "%s/%s" % [d.kind, d.def_id])
	var seq_b := b.pull(20, _catalog()).map(func(d: LootRoller.Drop) -> String: return "%s/%s" % [d.kind, d.def_id])
	assert_true(seq_a == seq_b, "the reloaded profile continues the same loot sequence (no re-rolls by reloading)")
	var c := PlayerProfile.new(777)
	var seq_c := c.pull(25, _catalog()).map(func(d: LootRoller.Drop) -> String: return "%s/%s" % [d.kind, d.def_id])
	assert_true(seq_c.slice(5) == seq_a, "a save/load in between does not change the sequence")


func test_duplicate_blueprints_scrap_for_spare_parts() -> void:
	var p := PlayerProfile.new(1)
	var room := _entry(&"workshop", Rarity.Tier.UNCOMMON, 1.0)
	room.kind = &"room"
	p.grant(room)
	var spares := p.spare_parts
	var again := _entry(&"workshop", Rarity.Tier.UNCOMMON, 1.0)
	again.kind = &"room"
	p.grant(again)
	assert_true(p.unlocks.has("workshop") and again.duplicate, "second workshop blueprint is a duplicate")
	assert_near(p.spare_parts - spares, PlayerProfile.DUPLICATE_SPARES[Rarity.Tier.UNCOMMON], 0.0, "duplicate scrapped for spare parts")
	p.grant(_entry(&"railgun", Rarity.Tier.EPIC, 1.0))
	p.grant(_entry(&"railgun", Rarity.Tier.EPIC, 1.0))
	assert_true(p.owned(&"railgun") == 2, "equipment drops stack as units (own %d)" % p.owned(&"railgun"))


# --- Ownership gating ------------------------------------------------------------

func test_locked_blueprints_and_unowned_parts_are_errors() -> void:
	var p := PlayerProfile.new(1)
	assert_true(not _report(_template(), p).has_errors(), "the all-common template needs nothing found")
	var bp := _template()
	(bp.find("r12") as ShipBlueprint.PlacedRoom).def_id = &"dense_magazine"
	for id in ["e29", "e30", "e31", "e32"]:
		(bp.find(id) as ShipBlueprint.PlacedEquipment).def_id = &"main_engine_high_isp"
	var r := _report(bp, p)
	assert_true(r.has_code(&"blueprint_locked") and r.has_code(&"part_not_owned"), "locked module and unowned engines are errors:\n%s" % r.summary())
	p.unlocks["dense_magazine"] = true
	p.inventory["main_engine_high_isp"] = 2
	r = _report(bp, p)
	assert_true(not r.has_code(&"blueprint_locked"), "unlocking the blueprint clears its error")
	var msg := r.errors().filter(func(i: ShipValidator.Issue) -> bool: return i.code == &"part_not_owned")
	assert_true(msg.size() == 1 and msg[0].message.contains("uses 4 but you own 2"), "message counts units: %s" % r.summary())
	p.inventory["main_engine_high_isp"] = 4
	assert_true(not _report(bp, p).has_errors(), "owning four clears it")


func test_mixed_gun_batteries_compile_per_mount() -> void:
	var bp := _template()
	bp.add_equipment(&"kinetic_cannon", Vector3i(4, 2, 4), &"dorsal")
	var r := ShipValidator.validate(bp, _catalog())
	assert_true(not r.has_errors(), "an autocannon and a heavy kinetic cannon can share a ship:\n%s" % r.summary())
	var cfg := ShipStats.compute(bp, ShipGrid.build(bp, _catalog())).to_ship_config("mixed")
	assert_true(cfg.mount_cannon(0).display_name != cfg.mount_cannon(1).display_name and cfg.mount_cannon(1).magazine_rounds == cfg.cannon.magazine_rounds,
		"each mount keeps its own gun, fed from one magazine")


func test_rare_parts_change_the_numbers() -> void:
	var base := ShipStats.compute(_template(), ShipGrid.build(_template(), _catalog()))
	var bp := _template()
	(bp.find("r12") as ShipBlueprint.PlacedRoom).def_id = &"dense_magazine"
	var rail := _with_gun(&"railgun")
	var dense := ShipStats.compute(bp, ShipGrid.build(bp, _catalog()))
	var rail_cfg := ShipStats.compute(rail, ShipGrid.build(rail, _catalog())).to_ship_config("r")
	assert_near(dense.rounds_capacity, base.rounds_capacity * 1.8, 0.5, "dense magazine holds 1.8× the rounds")
	assert_near(rail_cfg.cannon.muzzle_velocity_mps, 4000.0, 1e-6, "railgun design fires 4 km/s rounds")


# --- Persistence ------------------------------------------------------------------

## A template ship with a spread of damage of every kind.
func _damaged_ship() -> ShipState:
	var ship := _ship(_template())
	var s := ship.systems
	s.damage_equipment(s.equipment_by_id("e29"), 25.0)  # engine to 37.5 %
	s.damage_equipment(s.equipment_by_id("e33"), 100.0)  # RCS destroyed
	s.damage_equipment(s.equipment_by_id("e28"), 15.0)  # reactor to 75 %
	s.modules[1].armor_mm -= 7.0
	s.damage_module(1, 3.0)
	s.breach_room(1)
	s.destroy_hatch("h21")
	ship.attach_systems(s)
	return ship


func test_damage_round_trips_through_the_condition() -> void:
	var a := _damaged_ship()
	var c := a.systems.condition()
	var b := _ship(_template(), &"b", JSON.parse_string(JSON.stringify(c)))
	for i in a.systems.equipment.size():
		assert_near(b.systems.equipment[i].hp, a.systems.equipment[i].hp, 1e-4, "hp of %s" % a.systems.equipment[i].id)
	for i in a.systems.modules.size():
		assert_near(b.systems.modules[i].armor_mm, a.systems.modules[i].armor_mm, 1e-4, "armour of module %d" % i)
		assert_near(b.systems.modules[i].structure, a.systems.modules[i].structure, 1e-4, "structure of module %d" % i)
	for i in a.systems.rooms.size():
		assert_true(b.systems.rooms[i].pressurized == a.systems.rooms[i].pressurized, "room %d pressure" % i)
	assert_true(b.systems.destroyed_hatches.has("h21"), "destroyed hatch persists")
	assert_near(b.config.thrust_forward_n, a.config.thrust_forward_n, 1e-3, "flies with the same damaged thrust (N)")
	assert_near(b.systems.power_supply_kw, a.systems.power_supply_kw, 1e-3, "same power (kW)")
	assert_true(_ship(_template(), &"c", {}).systems.condition() == {"equipment": {}, "modules": {}, "breached": [], "hatches": []},
		"a new ship has an empty condition")


func test_profile_and_damaged_vessel_survive_save_and_load() -> void:
	var p := PlayerProfile.new(5)
	p.spare_parts = 123
	p.inventory["railgun"] = 2
	p.unlocks["workshop"] = true
	p.pity = {"since_rare": 4, "since_legendary": 33}
	p.missions_completed = 3
	p.ensure_vessel(_template())
	p.dock(_damaged_ship().systems.condition(), _catalog())
	assert_true(p.save(TEST_PROFILE) == OK, "profile saved")
	var errors := PackedStringArray()
	var q := PlayerProfile.load_file(TEST_PROFILE, errors)
	assert_true(q != null and errors.is_empty(), "profile loads: %s" % ", ".join(errors))
	if q == null:
		return
	assert_true(JSON.stringify(q.to_dict()) == JSON.stringify(p.to_dict()), "reloaded profile is identical")
	var flown := _ship(q.vessel.blueprint, &"q", q.vessel.condition)
	assert_near(flown.systems.equipment_by_id("e29").hp, 15.0, 1e-3, "reloaded vessel's engine e29 keeps its damage (hp)")
	assert_true(flown.systems.equipment_by_id("e33").destroyed(), "destroyed RCS e33 is still destroyed")
	assert_true(q.vessel.sorties == 1 and q.vessel.history.size() >= 2, "service history persists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func test_unsupported_or_corrupt_profiles_are_rejected_safely() -> void:
	var errors := PackedStringArray()
	assert_true(PlayerProfile.from_dict({"schema_version": PlayerProfile.SCHEMA_VERSION + 1}, errors) == null and not errors.is_empty(),
		"a newer schema is refused")
	errors.clear()
	assert_true(PlayerProfile.from_dict({"spare_parts": 5}, errors) == null, "a profile without a version is refused")
	var f := FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	errors.clear()
	assert_true(PlayerProfile.load_file(TEST_PROFILE, errors) == null and not errors.is_empty(), "corrupt JSON is refused")
	var saved_path := PlayerProfile.path
	PlayerProfile.path = TEST_PROFILE
	var fresh := PlayerProfile.load_or_new()
	PlayerProfile.path = saved_path
	assert_true(fresh != null and fresh.spare_parts == PlayerProfile.STARTING_SPARE_PARTS, "load_or_new starts a new profile")
	assert_true(FileAccess.file_exists(TEST_PROFILE + ".unreadable") and not FileAccess.file_exists(TEST_PROFILE),
		"the unreadable file is kept aside, not overwritten")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE + ".unreadable"))


# --- Service -------------------------------------------------------------------------

func _vessel(condition: Dictionary) -> ShipInstance:
	var v := ShipInstance.fresh(_template())
	v.condition = condition
	return v


func _job(jobs: Array[ServiceYard.Job], subject: String) -> ServiceYard.Job:
	for j in jobs:
		if j.subject == subject:
			return j
	return null


func test_repair_costs_scale_with_damage_and_never_beat_a_rebuild() -> void:
	var v := _vessel({"equipment": {"e29": 0.4, "e30": 0.0}})
	var jobs := ServiceYard.repair_jobs(v, _catalog())
	var engine_new := ServiceYard.equipment_cost(_catalog().equipment[&"main_engine"])
	assert_near(engine_new, 9, 0, "main engine (9 t) costs 9 parts new")
	assert_near(_job(jobs, "e29").cost, 6, 0, "engine at 40 % costs ⌈9 × 0.6⌉ to repair")
	assert_true(_job(jobs, "e30").kind == &"replace" and _job(jobs, "e30").cost == engine_new, "destroyed engine is rebuilt at full cost")
	# Removing the damaged engine and fitting a new one is a refit build.
	var bp := v.blueprint.duplicate_blueprint()
	bp.remove("e29")
	bp.add_equipment(&"main_engine", Vector3i(3, 0, 14), &"aft")
	var refit := ServiceYard.refit_jobs(v, bp, _catalog())
	assert_true(refit.size() == 1 and refit[0].cost >= _job(jobs, "e29").cost, "swapping the part costs %d ≥ repairing it (%d)" % [refit[0].cost, _job(jobs, "e29").cost])
	for d in [0.0, 0.01, 0.3, 0.5, 0.99, 1.0]:
		assert_true(ServiceYard.damaged_cost(engine_new, d) <= engine_new, "repair at %.0f %% damage ≤ new cost" % (d * 100.0))


func test_priorities_choose_what_gets_fixed_with_few_parts() -> void:
	var v := _vessel({"equipment": {"e28": 0.5, "e29": 0.2}, "modules": {"m3": {"armor": 1.0, "structure": 0.5}}})
	var jobs := ServiceYard.repair_jobs(v, _catalog())
	var reactor := _job(jobs, "e28").cost
	var engine := _job(jobs, "e29").cost
	var budget := maxi(reactor, engine)
	var mobility := ServiceYard.plan(jobs, ServiceYard.Priority.MOBILITY, budget)
	var combat := ServiceYard.plan(jobs, ServiceYard.Priority.COMBAT, budget)
	assert_true(mobility[0].subject == "e29", "mobility fixes the engine first (got %s)" % mobility[0].subject)
	assert_true(combat[0].subject == "e28", "combat readiness fixes the reactor first (got %s)" % combat[0].subject)
	assert_true(ServiceYard.total_cost(mobility) <= budget and ServiceYard.total_cost(combat) <= budget, "plans stay within budget")
	assert_true(ServiceYard.plan(jobs, ServiceYard.Priority.FULL, 0).is_empty(), "no parts, no repairs")


func test_repairs_restore_the_vessel_and_charge_parts() -> void:
	var p := PlayerProfile.new(1)
	p.spare_parts = 500
	p.ensure_vessel(_template())
	var flown := _damaged_ship()
	flown.systems.crew.by_id("c1").state = CrewRoster.State.DEAD  # a commander lost in the action
	p.dock(flown.systems.condition(), _catalog())
	assert_true(not p.vessel.condition.get("crew", {}).has("wounded"), "the wounded recover on docking")
	var jobs := ServiceYard.repair_jobs(p.vessel, _catalog())
	assert_true(jobs.any(func(j: ServiceYard.Job) -> bool: return j.kind == &"recruit"), "crew killed in action must be replaced")
	var cost := ServiceYard.total_cost(jobs)
	var spent := ServiceYard.perform(ServiceYard.plan(jobs, ServiceYard.Priority.FULL, p.spare_parts, p.vessel, p), p.vessel, p)
	assert_true(spent == cost and p.spare_parts == 500 - cost, "full repair charged %d parts (spent %d)" % [cost, spent])
	assert_true(not p.vessel.is_damaged(), "vessel like new after a full repair: %s" % p.vessel.condition)
	var relaunched := _ship(p.vessel.blueprint, &"r", p.vessel.condition)
	assert_true(relaunched.systems.crew.count() == relaunched.systems.crew.members.size(), "full complement after recruiting")
	assert_near(relaunched.config.thrust_forward_n, _ship(_template()).config.thrust_forward_n, 1e-3, "repaired ship has full thrust (N)")


func test_refit_is_paid_up_front_and_keeps_wear_on_kept_parts() -> void:
	var p := PlayerProfile.new(1)
	p.ensure_vessel(_template())
	p.vessel.condition = {"equipment": {"e28": 0.5, "e29": 0.3}}
	var bp := p.vessel.blueprint.duplicate_blueprint()
	bp.remove("e29")
	p.spare_parts = 0
	assert_true(ServiceYard.refit(p.vessel, bp, p, _catalog()) == "", "removing a part is free")
	assert_true(not p.vessel.condition.equipment.has("e29") and is_equal_approx(p.vessel.equipment_fraction("e28"), 0.5),
		"removed part leaves the record; the reactor keeps its wear")
	var bp2 := p.vessel.blueprint.duplicate_blueprint()
	bp2.add_equipment(&"radiator", Vector3i(3, 2, 6), &"dorsal")
	var why := ServiceYard.refit(p.vessel, bp2, p, _catalog())
	assert_true(why.contains("needs 5 spare parts"), "unaffordable refit refused: '%s'" % why)
	assert_true(p.vessel.blueprint.equipment.size() == bp.equipment.size(), "refused refit leaves the vessel unchanged")
	p.spare_parts = 10
	assert_true(ServiceYard.refit(p.vessel, bp2, p, _catalog()) == "" and p.spare_parts == 5, "paid refit: 10 → %d parts" % p.spare_parts)


func test_a_destroyed_rare_part_is_rebuilt_not_written_off() -> void:
	var p := PlayerProfile.new(1)
	p.spare_parts = 100
	p.inventory["railgun"] = 1
	p.ensure_vessel(_with_gun(&"railgun"))
	p.dock({"equipment": {"e41": 0.0}}, _catalog())
	assert_true(p.owned(&"railgun") == 1 and not _report(p.vessel.blueprint, p).has_errors(), "the railgun is still yours")
	var job := _job(ServiceYard.repair_jobs(p.vessel, _catalog()), "e41")
	assert_true(job.kind == &"replace" and job.cost == ServiceYard.equipment_cost(_catalog().equipment[&"railgun"]),
		"rebuilt at its fitting cost (%d parts)" % job.cost)
	var one: Array[ServiceYard.Job] = [job]
	ServiceYard.perform(one, p.vessel, p)
	assert_true(not p.vessel.is_damaged(), "and whole again")


func test_losing_the_vessel_loses_only_the_cargo_and_a_fee() -> void:
	var p := PlayerProfile.new(1)
	p.inventory["railgun"] = 1
	p.ensure_vessel(_with_gun(&"railgun"))
	p.vessel.condition = {"equipment": {"e29": 0.5}}
	p.vessel.cargo = {"spare_parts": 40, "equipment": {"torch_drive": 1}}
	var design := JSON.stringify(p.vessel.blueprint.to_dict())
	var credits := p.credits
	var fee := p.respawn_fee(_catalog())
	var lost := p.lose_vessel(_catalog())
	assert_true(p.owned(&"railgun") == 1, "parts installed in the design are kept")
	assert_true(p.vessel.cargo_is_empty() and p.owned(&"torch_drive") == 0, "the cargo is gone")
	assert_true(credits - p.credits == fee and fee == PlayerProfile.RESPAWN_BASE_FEE + PlayerProfile.RESPAWN_FEE_PER_BERTH * 24,
		"respawn fee %d credits (24 berths)" % fee)
	assert_true(JSON.stringify(p.vessel.blueprint.to_dict()) == design and not p.vessel.is_damaged(), "the same design, rebuilt and rearmed")
	assert_true(lost.size() == 3 and p.vessels_lost == 1, "loss report: %s" % ", ".join(lost))
	p.credits = 10
	p.lose_vessel(_catalog())
	assert_true(p.credits == 0, "a short purse pays what it has")


func test_salvage_goes_into_the_hold_until_banked() -> void:
	var p := PlayerProfile.new(3)
	p.ensure_vessel(_template())
	var parts_before := p.spare_parts
	for d in p.pull(10, _catalog()):
		p.stow(d)
	assert_true(not p.vessel.cargo_is_empty() and p.spare_parts == parts_before and p.inventory.is_empty() and p.unlocks.is_empty(),
		"loot waits in the hold: %s" % p.vessel.cargo_summary())
	var banked := p.bank_cargo(_catalog())
	assert_true(p.vessel.cargo_is_empty() and not banked.is_empty(), "banking empties the hold: %s" % ", ".join(banked))
	assert_true(p.spare_parts > parts_before or not p.inventory.is_empty() or not p.unlocks.is_empty(), "and it is yours")


func test_cargo_and_credits_survive_save_and_load_and_old_saves_migrate() -> void:
	var p := PlayerProfile.new(1)
	p.ensure_vessel(_template())
	p.vessel.cargo = {"spare_parts": 12, "equipment": {"railgun": 1}, "blueprints": {"workshop": ["room", 1, 1]}}
	p.credits = 777
	var errors := PackedStringArray()
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), errors)
	assert_true(q.credits == 777 and q.vessel.cargo_summary() == p.vessel.cargo_summary(), "credits and cargo reload")
	var v1 := p.to_dict()
	v1.schema_version = 1
	v1.erase("credits")
	# v1/v2 kept a single "vessel".
	v1["vessel"] = (v1.vessels as Array)[0]
	v1.erase("vessels")
	(v1.vessel as Dictionary).erase("cargo")
	var old := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(v1)), errors)
	assert_true(old != null and old.credits == PlayerProfile.STARTING_CREDITS and old.vessel.cargo_is_empty(), "a v1 profile migrates with defaults")


func test_station_sells_spare_parts_for_credits() -> void:
	var p := PlayerProfile.new(1)
	p.credits = PlayerProfile.PARTS_LOT_PRICE
	var parts := p.spare_parts
	assert_true(p.buy_spare_parts() and p.spare_parts == parts + PlayerProfile.PARTS_LOT and p.credits == 0, "one lot bought")
	assert_true(not p.buy_spare_parts(), "not without credits")


func test_debrief_says_where_the_hits_came_from() -> void:
	var log := CombatLog.new()
	for side in ["port", "port", "fore"]:
		var r := DamageReport.new()
		var travel: Vector3 = {"port": Vector3(1, 0, 0), "fore": Vector3(0, 0, 1)}[side]
		r.path_body = PackedVector3Array([Vector3.ZERO, travel])
		assert_true(CombatLog.side_of(r) == side, "a round travelling %s came in through the %s" % [travel, side])
		log.hits_taken += 1
		log.hits_by_side[side] = int(log.hits_by_side.get(side, 0)) + 1
	log.systems_lost.append({"id": "e28", "name": "Fusion reactor", "side": "port", "t": 1.0})
	var lessons := "\n".join(CombatLog.insights(log.to_dict()))
	assert_true(lessons.contains("through the port (2 of 3)") and lessons.contains("second reactor") and lessons.contains("workshop"),
		"lessons name the side, the reactor and the missing workshop:
%s" % lessons)
	assert_true(CombatLog.render(log.to_dict()).contains("LESSONS FOR THE SHIPYARD"), "debrief renders")


# --- Salvage -------------------------------------------------------------------------

func test_disabled_means_it_cannot_fight() -> void:
	var ship := _ship(_template())
	assert_true(not ship.systems.is_disabled(), "an intact ship is not disabled")
	ship.systems.damage_equipment(ship.systems.equipment_by_id("e41"), 1000.0)
	assert_true(ship.systems.disabled_reason() == "all guns out", "losing every gun disables it")
	var dark := _ship(_template())
	dark.systems.damage_equipment(dark.systems.equipment_by_id("e28"), 1000.0)
	assert_true(dark.systems.disabled_reason() == "no power", "losing the only reactor disables it")


func test_salvage_beacon_needs_a_disabled_wreck_in_range() -> void:
	var me := _ship(_template(), &"me")
	var wreck := _ship(_template(), &"wreck")
	wreck.position = Vector3(0, 0, -300)
	wreck.velocity = Vector3(10, 0, 0)
	assert_true(Salvage.block_reason(me, wreck).contains("disable"), "a fighting ship cannot be salvaged")
	wreck.systems.damage_equipment(wreck.systems.equipment_by_id("e41"), 1000.0)
	assert_true(Salvage.block_reason(me, wreck) == "", "disabled, 300 m, 10 m/s: a beacon can be dropped (no velocity match needed)")
	wreck.position = Vector3(0, 0, -2500)
	assert_true(Salvage.block_reason(me, wreck).contains("close to"), "2.5 km is too far for a beacon")
	wreck.position = Vector3(0, 0, -300)
	wreck.systems.captured = true
	assert_true(Salvage.block_reason(me, wreck).contains("already taken"), "a captured ship is a prize, not a beacon job")


func test_takeover_pays_more_than_a_beacon() -> void:
	var wreck := _ship(_template())
	wreck.systems.damage_equipment(wreck.systems.equipment_by_id("e41"), 1000.0)
	var scrap := Salvage.scrap_value(wreck.systems)
	assert_true(scrap > 100, "an intact frigate is worth scrap (%d cr)" % scrap)
	assert_true(Salvage.TAKEOVER_SCRAP_RATE > Salvage.BEACON_SCRAP_RATE and Salvage.TAKEOVER_LOOT_CHANCE > Salvage.BEACON_LOOT_CHANCE,
		"takeover: higher scrap credit and crate odds than a beacon")
	var p := PlayerProfile.new(7)
	var beacon := p.open_crates(400, Salvage.BEACON_LOOT_CHANCE, _catalog())
	var prize := p.open_crates(400, Salvage.TAKEOVER_LOOT_CHANCE, _catalog())
	var full := func(a: Array) -> int: return a.filter(func(d: Variant) -> bool: return d != null).size()
	assert_near(full.call(beacon) / 400.0, Salvage.BEACON_LOOT_CHANCE, 0.07, "beacon crates holding loot")
	assert_near(full.call(prize) / 400.0, Salvage.TAKEOVER_LOOT_CHANCE, 0.07, "prize crates holding loot")


func test_salvage_pays_more_for_a_cleaner_kill() -> void:
	var clean := _ship(_template())
	clean.systems.damage_equipment(clean.systems.equipment_by_id("e41"), 1000.0)
	var shredded := _ship(_template())
	for e in shredded.systems.equipment:
		shredded.systems.damage_equipment(e, e.max_hp * 0.8)
	shredded.systems.damage_equipment(shredded.systems.equipment_by_id("e41"), 1000.0)
	assert_true(Salvage.pulls_for(clean.systems) > Salvage.pulls_for(shredded.systems), "clean kill: %d pulls vs shredded %d" % [Salvage.pulls_for(clean.systems), Salvage.pulls_for(shredded.systems)])
	assert_true(Salvage.spare_parts_for(clean.systems) > Salvage.spare_parts_for(shredded.systems), "clean kill: %d parts vs shredded %d" % [Salvage.spare_parts_for(clean.systems), Salvage.spare_parts_for(shredded.systems)])
	assert_true(Salvage.pulls_for(shredded.systems) >= 1, "even a wreck yields one pull")


# --- Field repair ----------------------------------------------------------------------

func test_field_repair_needs_a_working_workshop_and_patches_over_time() -> void:
	var plain := _ship(_template())
	plain.systems.damage_equipment(plain.systems.equipment_by_id("e28"), 30.0)
	assert_true(plain.systems.field_repair_block_reason() == "no workshop aboard", "no workshop, no field repairs")
	var ship := _ship(_with_workshop())
	var s := ship.systems
	s.damage_equipment(s.equipment_by_id("e29"), 100.0)  # destroyed: needs the yard
	s.damage_equipment(s.equipment_by_id("e28"), 30.0)   # reactor at 50 %
	var e := s.start_field_repair()
	assert_true(e != null and e.id == "e28", "crew patch the damaged reactor, not the destroyed engine")
	# Damage control walk from the workshop r9 → corridor r8 → corridor r14 → reactor room r15.
	var walk := 3.0 * CrewRoster.ROOM_TRANSIT_S
	assert_near(s.repair_task.travel_s, walk, 1e-6, "walk from the workshop to the reactor room (s)")
	assert_near(s.repair_task.total_s, walk + ShipSystems.FIELD_REPAIR_SETUP_S + 15.0, 1e-6, "repair time = walk + setup + 1 s per hp (s)")
	var t := 0.0
	while s.repair_task != null and t < 60.0:
		s.tick(ship, 0.5)
		t += 0.5
	assert_near(t, 40.0, 0.5, "repair finished after (s)")
	assert_near(s.equipment_by_id("e28").hp, 45.0, 1e-4, "reactor patched to 75 % (hp)")
	assert_true(s.field_repair_target() == null, "nothing left to patch: the engine is destroyed")


func test_field_repair_is_interrupted_when_the_workshop_vents() -> void:
	var ship := _ship(_with_workshop())
	var s := ship.systems
	s.damage_equipment(s.equipment_by_id("e28"), 30.0)
	s.start_field_repair()
	s.tick(ship, 1.0)
	var workshop := -1
	for i in s.blueprint.rooms.size():
		if s.blueprint.rooms[i].id == "r9":
			workshop = i
	s.breach_room(workshop)
	s.tick(ship, 1.0)
	assert_true(s.repair_task == null and s.event_log[-1].contains("interrupted"), "breaching the workshop stops the repair: %s" % s.event_log[-1])
	assert_near(s.equipment_by_id("e28").hp, 30.0, 1e-6, "no hit points restored (hp)")
	assert_true(s.field_repair_block_reason().contains("workshop"), "and no new repair can start: %s" % s.field_repair_block_reason())


# --- Enemies ------------------------------------------------------------------------

func test_enemies_get_tougher_and_stay_valid() -> void:
	var rare_counts := []
	for mission in range(1, 13):
		var bp := EnemyFactory.design(mission, _template(), _catalog())
		var again := EnemyFactory.design(mission, _template(), _catalog())
		assert_true(JSON.stringify(bp.to_dict()) == JSON.stringify(again.to_dict()), "mission %d enemy is deterministic" % mission)
		assert_true(not ShipValidator.validate(bp, _catalog()).has_errors(), "mission %d enemy is a valid design" % mission)
		var rares := 0
		for e in bp.equipment:
			rares += 1 if (_catalog().equipment[e.def_id] as EquipmentDefinition).rarity != Rarity.Tier.COMMON else 0
		for m in bp.modules:
			rares += 1 if (_catalog().hull[m.def_id] as HullModuleDefinition).rarity != Rarity.Tier.COMMON else 0
		rare_counts.append(rares)
	assert_true(rare_counts[0] == 0, "the first enemy is the plain template")
	var early := 0
	var late := 0
	for k in 4:
		early += rare_counts[k]
		late += rare_counts[8 + k]
	assert_true(late > early, "later enemies carry more rare parts (%s)" % [rare_counts])


func test_salvage_strips_the_best_intact_rare_part() -> void:
	var bp := _template()
	(bp.find("e41") as ShipBlueprint.PlacedEquipment).def_id = &"railgun"
	(bp.find("e33") as ShipBlueprint.PlacedEquipment).def_id = &"rcs_block_heavy"
	var wreck := _ship(bp)
	assert_true(EnemyFactory.recoverable_part(wreck.systems).def.id == &"railgun", "the epic railgun beats the uncommon RCS")
	wreck.systems.damage_equipment(wreck.systems.equipment_by_id("e41"), 30.0)
	assert_true(EnemyFactory.recoverable_part(wreck.systems).def.id == &"rcs_block_heavy", "a wrecked railgun is not worth stripping")
	assert_true(EnemyFactory.recoverable_part(_ship(_template()).systems) == null, "an all-common wreck has nothing rare")


func test_cargo_hold_capacity_and_venting_the_excess() -> void:
	var bp := _template()
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	assert_true(stats.cargo_m3 > 0.0 and stats.cargo_m3 < 24 * 27.0,
		"hold space is what the tanks leave free (%.0f m³ of %.0f)" % [stats.cargo_m3, 24 * 27.0])
	var v := ShipInstance.fresh(bp)
	v.cargo = {"spare_parts": 100, "equipment": {"railgun": 1}}
	var rail_m3 := ShipInstance.equipment_m3(_catalog().equipment[&"railgun"])
	assert_near(v.cargo_volume_m3(_catalog()), 100 * ShipInstance.SPARE_PART_M3 + rail_m3, 1e-6, "volume of 100 parts and a railgun (m³)")
	var went := v.vent_excess(10.0, _catalog())
	assert_true(v.cargo_volume_m3(_catalog()) <= 10.0 + 1e-6 and int(v.cargo.equipment.railgun) == 1,
		"venting the excess drops cheap spare parts first and keeps the railgun (%s)" % ", ".join(went))
	assert_true(v.vent("equipment", "railgun") != "" and not v.cargo.has("equipment"), "a whole line can be vented")


func test_a_new_hull_is_commissioned_into_the_hangar() -> void:
	var p := PlayerProfile.new(9)
	p.ensure_vessel(_template())
	var first := p.vessel
	var small := ShipBlueprint.new()
	small.name = "Cutter"
	small.add_module(&"hull_block", Vector3i.ZERO)
	var cost := p.new_hull_cost(small, _catalog())
	assert_true(cost.x == ServiceYard.module_cost(_catalog().hull[&"hull_block"]) and cost.y == PlayerProfile.NEW_HULL_FEE,
		"a one-block hull costs its block and the fee (%s)" % cost)
	p.credits = 0
	assert_true(p.commission(small, _catalog()).contains("fee"), "no credits, no new hull")
	p.credits = 1000
	p.spare_parts = 100
	assert_true(p.commission(small, _catalog()) == "" and p.vessels.size() == 2 and p.vessel.name == "Cutter",
		"commissioned: the cutter is the active vessel")
	assert_true(p.credits == 1000 - PlayerProfile.NEW_HULL_FEE and p.spare_parts == 100 - cost.x, "paid in parts and credits")
	assert_true(p.select_vessel(0) and p.vessel == first, "the frigate is still in the hangar")
	# Saved and loaded with both vessels; old single-vessel profiles migrate.
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())), PackedStringArray())
	assert_true(q.vessels.size() == 2 and q.active_vessel == 0 and q.vessels[1].name == "Cutter", "the hangar round-trips")
	var old := p.to_dict()
	old.erase("vessels")
	old["vessel"] = first.to_dict()
	old.schema_version = 2
	var r := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(old)), PackedStringArray())
	assert_true(r.vessels.size() == 1 and r.vessel.name == first.name, "a v2 profile's vessel becomes the hangar's only vessel")
	# Rare parts owned can go on any vessel's design, not just the one they
	# were first fitted to.
	p.inventory["railgun"] = 1
	p.vessels[0].blueprint = _with_gun(&"railgun")
	p.select_vessel(1)
	var with_rail := ShipBlueprint.new()
	with_rail.add_module(&"hull_block", Vector3i.ZERO)
	with_rail.add_equipment(&"railgun", Vector3i(0, 0, 0), &"dorsal")
	var rep := ShipValidator.Report.new()
	p.check_design(with_rail, _catalog(), rep)
	assert_true(not rep.has_code(&"part_not_owned"), "the railgun on the frigate can be used on the cutter's design too")
	with_rail.add_equipment(&"railgun", Vector3i(0, 0, 0), &"port")
	rep = ShipValidator.Report.new()
	p.check_design(with_rail, _catalog(), rep)
	assert_true(rep.has_code(&"part_not_owned"), "but not more than are owned")
