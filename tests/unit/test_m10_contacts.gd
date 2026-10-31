extends TestCase
## Measures: Milestone 10 — the contact registry (selection, cycling, three
## hostiles with their own tracks and wings), enemy roles, focus fire and
## derelict avoidance, enemy salvos by count, point-defence priorities
## (order, range, ammunition reserve) against a missile, a craft and a round
## at once, the ShipPolicy engine (presets, discipline, auto-fire, manual
## override, auto-salvo), its persistence (schema 6) and the frame budget of
## a three-ship encounter.

const DT := 1.0 / 60.0
const TEST_PROFILE := "user://test_m10_profile.json"


func _catalog() -> ConstructionCatalog:
	return ConstructionCatalog.default_catalog()


func _template() -> ShipBlueprint:
	return BlueprintIO.load_file(TestCase.FRIGATE, PackedStringArray())


func _ship(id: StringName, pos: Vector3 = Vector3.ZERO, bp: ShipBlueprint = null, side: StringName = &"") -> ShipState:
	if bp == null:
		bp = _template()
	var grid := ShipGrid.build(bp, _catalog())
	var stats := ShipStats.compute(bp, grid)
	var cfg := stats.to_ship_config(bp.name)
	var ship := ShipState.create(id, String(id), cfg, pos)
	ship.attach_systems(ShipSystems.create(bp, grid, stats, cfg))
	ship.side = side
	return ship


## A hostile missile `d` m out along `dir`, flying at the origin at `speed`.
func _missile_at(world: WorldSimulation, dir: Vector3, d: float, speed: float = 200.0) -> ShipState:
	var cfg: MissileConfig = load("res://data/missiles/anti_ship_missile.tres")
	var m := ShipState.create(&"hostile_msl", "msl", cfg.to_ship_config(), dir * d, -dir * speed)
	m.missile = cfg
	m.missile_owner = &"nobody"
	m.side = &"hostile"
	world.add_ship(m)
	return m


func _craft_at(world: WorldSimulation, dir: Vector3, d: float) -> ShipState:
	var cfg: ShipConfig = load("res://data/craft/wasp_fighter.tres")
	var c := ShipState.create(&"hostile_wasp", "wasp", cfg, dir * d, -dir * 50.0)
	c.side = &"hostile"
	world.add_ship(c)
	return c


## A heavy-cannon slug (4 kg) `d` m out, coming straight at the origin.
func _round_at(world: WorldSimulation, dir: Vector3, d: float) -> ProjectileState:
	var r := ProjectileState.new()
	r.id = 9001
	r.shooter_id = &"nobody"
	r.weapon = load("res://data/weapons/medium_kinetic_cannon.tres")
	r.position = dir * d
	r.prev_position = r.position
	r.velocity = -dir * 1000.0
	world._rounds.append(r)
	return r


# --- Contact registry -------------------------------------------------------------

func test_the_encounter_registry_selects_cycles_and_reselects() -> void:
	var world := WorldSimulation.new(DT)
	var e := Encounter.new()
	for i in 3:
		var id := StringName("target_%02d" % (i + 1))
		world.add_ship(_ship(id, Vector3(i * 500.0, 0, -2000)))
		e.add(Contact.create(id, i, EnemyFactory.policy(7, i)))
	assert_true(e.selected == &"target_01", "the first added is selected (%s)" % e.selected)
	var seen: Array[StringName] = []
	for i in 3:
		seen.append(e.cycle(world))
	assert_true(seen == [&"target_02", &"target_03", &"target_01"], "U cycles through all three and wraps: %s" % [seen])
	assert_true(e.select(&"target_03") and not e.select(&"nope"), "select by id; unknown ids refused")
	world.get_ship(&"target_03").status = ShipState.Status.DESTROYED
	e.ensure_selection(world)
	assert_true(e.selected == &"target_01" and e.live(world).size() == 2, "a destroyed selection moves to a live contact (%s)" % e.selected)
	e.remove(&"target_01")
	assert_true(e.selected == &"target_02" and not e.has(&"target_01"), "removing the selected one selects another")
	assert_true(not e.any_hostile(world), "nobody hostile yet")
	e.get_contact(&"target_02").hostile = true
	assert_true(e.any_hostile(world), "one hostile")


func test_each_contact_keeps_its_own_track_and_policy() -> void:
	var world := WorldSimulation.new(DT)
	var player := _ship(&"player")
	world.add_ship(player)
	var contacts: Array[Contact] = []
	for i in 3:
		var id := StringName("target_%02d" % (i + 1))
		world.add_ship(_ship(id, Vector3(0, 0, -2000.0 - 14500.0 * i)))
		contacts.append(Contact.create(id, i, EnemyFactory.policy(7, i)))
	for c in contacts:
		c.track.update(player, world.get_ship(c.id), 0.0, DT)
	assert_true(contacts[0].track.detected and contacts[1].track.detected and not contacts[2].track.detected,
		"tracks are per contact: 2 km and 16.5 km seen, 31 km (beyond the 25 km mast) not (%s, %s, %s)" % [contacts[0].track.detected, contacts[1].track.detected, contacts[2].track.detected])
	assert_true(contacts[0].policy.role == ShipPolicy.Role.CLOSER and contacts[1].policy.role == ShipPolicy.Role.STANDOFF
		and contacts[2].policy.role == ShipPolicy.Role.FLANKER, "roles by place in the encounter")
	assert_true(EnemyFactory.encounter_size(0) == 1 and EnemyFactory.encounter_size(2) == 2 and EnemyFactory.encounter_size(9) == 3,
		"the encounter is the size picked on the map, 1–3")
	var a := EnemyFactory.design(7, _template(), _catalog(), 0)
	var b := EnemyFactory.design(7, _template(), _catalog(), 1)
	assert_true(a.name != b.name and not ShipValidator.validate(b, _catalog()).has_errors(), "each ship its own valid design (%s / %s)" % [a.name, b.name])
	assert_true(EnemyFactory.design(3, _template(), _catalog()).name == EnemyFactory.design(3, _template(), _catalog(), 0).name,
		"the lead ship of a mission is the same as before")


# --- Enemy behaviour --------------------------------------------------------------

## Thrust along the line of sight to the target (+ closes, − backs off).
func _radial_thrust(shooter: ShipState, target: ShipState, policy: ShipPolicy) -> float:
	var input := GunneryAI.combat(shooter, target, 0.0, policy)
	var los := shooter.orientation.inverse() * (target.position - shooter.position).normalized()
	return input.translation.dot(los)


func test_roles_fight_at_their_own_ranges() -> void:
	var target := _ship(&"player")
	var shooter := _ship(&"enemy", Vector3(0, 0, -3000))
	var closer := EnemyFactory.policy(7, 0)
	var standoff := EnemyFactory.policy(7, 1)
	# 3 km: inside the standoff's 5–9 km band, inside the closer's 1.2–3.5 km.
	var c := _radial_thrust(shooter, target, closer)
	var s := _radial_thrust(shooter, target, standoff)
	assert_true(absf(c) < 0.5 and s < -0.5, "at 3 km the closer holds (%.2f), the standoff ship backs off (%.2f)" % [c, s])
	shooter.position = Vector3(0, 0, -12000)
	assert_true(_radial_thrust(shooter, target, standoff) > 0.5, "at 12 km the standoff ship closes in")


func test_focus_fire_and_never_a_derelict() -> void:
	var shooter := _ship(&"enemy", Vector3(0, 0, -3000))
	var player := _ship(&"player")
	var fighter := _ship(&"player_f1", Vector3(0, 0, -2500))
	var wreck := _ship(&"wreck_01", Vector3(0, 0, -2900))
	wreck.derelict = true
	var focus := EnemyFactory.policy(7, 0)
	var candidates: Array[ShipState] = [player, fighter, wreck]
	assert_true(GunneryAI.choose_prey(shooter, candidates, player, focus) == player, "focus fire: the team's prey (the player), not the nearer fighter")
	var loose := EnemyFactory.policy(7, 0)
	loose.focus_fire = false
	assert_true(GunneryAI.choose_prey(shooter, candidates, player, loose) == fighter,
		"without focus fire: the nearest live candidate — the fighter at 500 m, not the wreck at 100 m")
	var only_wreck: Array[ShipState] = [wreck]
	assert_true(GunneryAI.choose_prey(shooter, only_wreck, null, loose) == null, "a derelict is never prey")


func test_enemy_salvos_launch_the_policy_count() -> void:
	var world := WorldSimulation.new(DT)
	var bp := _template()
	EnemyFactory._fit_launcher(bp, _catalog(), &"missile_rack", RandomNumberGenerator.new())
	world.add_ship(_ship(&"enemy", Vector3.ZERO, bp, &"hostile"))
	world.add_ship(_ship(&"player", Vector3(0, 0, -6000), null, &"player"))
	var policy := EnemyFactory.policy(4, 0)
	var s := MissileSalvo.start(&"enemy", &"player", policy.salvo_mode, [], policy.salvo_count)
	var t := 0.0
	while not s.done() and t < 20.0:
		s.step(world)
		world.step()
		t += DT
	assert_true(policy.salvo_count >= 2 and s.launched == policy.salvo_count and world.get_ship(&"enemy").systems.missiles_of() == 12 - policy.salvo_count,
		"a salvo of %d, not 1 and not the whole rack (launched %d, %d left)" % [policy.salvo_count, s.launched, world.get_ship(&"enemy").systems.missiles_of()])
	assert_true(world.missiles.all(func(m: ShipState) -> bool: return m.side == &"hostile"), "its missiles fly on its side")


# --- Point defence -----------------------------------------------------------------

func _pd_world(policy: ShipPolicy) -> Dictionary:
	var world := WorldSimulation.new(DT)
	var ship := _ship(&"player", Vector3.ZERO, null, &"player")
	ship.policy = policy
	world.add_ship(ship)
	var up := Vector3(0.2, 1.0, -0.3).normalized()
	var m := _missile_at(world, up, 1500.0)
	var c := _craft_at(world, up, 1200.0)
	var r := _round_at(world, up, 1000.0)
	return {"world": world, "ship": ship, "missile": m, "craft": c, "round": r}


## What the mounts that engaged anything are engaging, after one tick.
func _engaged(world: WorldSimulation, ship: ShipState) -> PackedStringArray:
	world.step()
	var out := PackedStringArray()
	for t in ship.pd_targets:
		if t != "" and not out.has(t):
			out.append(t)
	return out


func test_point_defence_engages_in_policy_order() -> void:
	var f := _pd_world(ShipPolicy.preset("Defensive"))
	var world: WorldSimulation = f.world
	var ship: ShipState = f.ship
	var cands := world.pd_candidates(ship)
	var kinds := cands.map(func(c: Dictionary) -> String: return String(c.kind))
	assert_true(kinds == ["missile", "craft", "round"], "candidates in the default order missiles › craft › rounds, though the round is nearest (%s)" % [kinds])
	var first := _engaged(world, ship)
	assert_true(first == PackedStringArray(["hostile_msl"]), "a missile, a craft and a round at once: the missile first (engaging %s)" % [first])
	world.remove_ship(&"hostile_msl")
	assert_true(_engaged(world, ship) == PackedStringArray(["hostile_wasp"]), "missile gone: the craft next")
	world.remove_ship(&"hostile_wasp")
	var last := _engaged(world, ship)
	assert_true(last.size() == 1 and last[0].begins_with("round:"), "then the round (%s)" % [last])
	# Reordered: rounds first.
	var rev := ShipPolicy.preset("Defensive")
	rev.pd_priorities = [&"round", &"craft", &"missile"]
	var g := _pd_world(rev)
	var r_first := _engaged(g.world, g.ship)
	assert_true(r_first.size() == 1 and r_first[0].begins_with("round:"), "order round › craft › missile: the round first (%s)" % [r_first])


func test_point_defence_respects_range_and_ammo_reserve() -> void:
	var short := ShipPolicy.preset("Defensive")
	short.pd_range_m = 600.0
	var f := _pd_world(short)
	assert_true(_engaged(f.world, f.ship).is_empty(), "everything is beyond a 600 m engagement range: nothing engaged")
	var g := _pd_world(ShipPolicy.preset("Defensive"))
	var ship: ShipState = g.ship
	ship.pd_rounds = 10  # under the 15 % reserve of a full magazine
	g.world.remove_ship(&"hostile_msl")
	assert_true(_engaged(g.world, ship).is_empty(), "below the reserve, a mount keeps its rounds for missiles only: the craft is left alone")
	var off := ShipPolicy.preset("Defensive")
	off.pd_enabled = false
	var h := _pd_world(off)
	assert_true(_engaged(h.world, h.ship).is_empty(), "auto point defence off: nothing engaged")


func test_flak_destroys_a_heavy_slug_but_not_small_or_fast_rounds() -> void:
	var world := WorldSimulation.new(DT)
	var ship := _ship(&"player", Vector3.ZERO, null, &"player")
	world.add_ship(ship)
	var r := _round_at(world, Vector3(0, 1, -0.2).normalized(), 1800.0)
	var t := 0.0
	while t < 2.5 and world._rounds.has(r):
		world.step()
		t += DT
	assert_true(world.rounds_intercepted >= 1 and not world._rounds.has(r) and ship.hits_taken == 0,
		"a 4 kg slug at 1 km/s is shot down before it arrives (intercepted %d, hits %d)" % [world.rounds_intercepted, ship.hits_taken])
	var small := ProjectileState.new()
	small.weapon = load("res://data/weapons/light_autocannon.tres")
	small.position = Vector3(0, 900, 0)
	small.velocity = Vector3(0, -1000, 0)
	assert_true(not world._round_threatens(ship, small), "a 1 kg autocannon round is too small to track")
	var rail := ProjectileState.new()
	rail.weapon = load("res://data/weapons/railgun.tres")
	rail.position = Vector3(0, 900, 0)
	rail.velocity = Vector3(0, -4000, 0)
	assert_true(not world._round_threatens(ship, rail), "a railgun slug is too fast")


func test_point_defence_never_engages_its_own_side() -> void:
	var world := WorldSimulation.new(DT)
	var a := _ship(&"target_01", Vector3.ZERO, null, &"hostile")
	world.add_ship(a)
	var cfg: ShipConfig = load("res://data/craft/wasp_fighter.tres")
	var friend := ShipState.create(&"target_02_f1", "f", cfg, Vector3(0, 800, 0))
	friend.side = &"hostile"
	world.add_ship(friend)
	assert_true(world.pd_candidates(a).is_empty(), "another hostile ship's fighter is not a target for a hostile ship's point defence")


# --- Policy engine ------------------------------------------------------------------

func test_policy_presets_and_discipline() -> void:
	var names := ShipPolicy.PRESETS.map(func(n: String) -> String: return ShipPolicy.preset(n).preset_name)
	assert_true(names == ["Hold", "Defensive", "Standard", "Aggressive"], "four presets load (%s)" % [names])
	var hold := ShipPolicy.preset("Hold")
	var tight := ShipPolicy.preset("Defensive")
	var free := ShipPolicy.preset("Aggressive")
	assert_true(not hold.allows_fire(true) and tight.allows_fire(true) and not tight.allows_fire(false) and free.allows_fire(false),
		"hold never, tight only at hostiles, free at anything")
	assert_true(not ShipPolicy.preset("Defensive").autofire_enabled and ShipPolicy.preset("Standard").autofire_enabled,
		"Defensive (the default) adds no automatic fire; Standard auto-fires")
	assert_true(ShipPolicy.preset("Defensive") != ShipPolicy.preset("Defensive"), "each preset() is a fresh copy")


func test_auto_fire_and_manual_override() -> void:
	var std := ShipPolicy.preset("Standard")
	assert_true(std.trigger(false, true, true, 0.3), "auto-fire: lock, hostile, aim 0.3° off the lead (≤ 0.5°): fires")
	assert_true(not std.trigger(false, true, true, 0.8), "aim 0.8° off: holds")
	assert_true(not std.trigger(false, false, true, 0.1), "no lock: holds")
	assert_true(not std.trigger(false, true, false, 0.1), "tight discipline, passive contact: holds")
	var hold := ShipPolicy.preset("Hold")
	hold.autofire_enabled = true
	assert_true(not hold.trigger(false, true, true, 0.0), "hold discipline: automation never fires")
	for p in [std, hold, ShipPolicy.preset("Defensive")]:
		assert_true(p.trigger(true, false, false, 180.0), "manual trigger always fires (%s, no lock, passive, no solution)" % p.preset_name)


func test_auto_salvo_conditions() -> void:
	var std := ShipPolicy.preset("Standard")
	assert_true(std.salvo_due(true, 0.9, 5000.0, true, 30.0, 0.0), "lock 90 %, 5 km, hostile, interval elapsed: salvo")
	assert_true(not std.salvo_due(true, 0.5, 5000.0, true, 30.0, 0.0), "lock quality 50 % < 80 %: no")
	assert_true(not std.salvo_due(true, 0.9, 1000.0, true, 30.0, 0.0) and not std.salvo_due(true, 0.9, 13000.0, true, 30.0, 0.0),
		"outside the 2–12 km band: no")
	assert_true(not std.salvo_due(true, 0.9, 5000.0, true, 10.0, 20.0), "before the interval: no")
	assert_true(not ShipPolicy.preset("Defensive").salvo_due(true, 1.0, 5000.0, true, 30.0, 0.0), "Defensive: no auto-salvo")


func test_policy_round_trips_and_is_clamped() -> void:
	var p := ShipPolicy.preset("Aggressive")
	p.pd_priorities = [&"round", &"missile"]
	p.salvo_count = 7
	var q := ShipPolicy.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(q.to_dict() == ShipPolicy.from_dict(p.to_dict()).to_dict() and q.salvo_count == 7, "saved and loaded the same")
	assert_true(q.pd_order() == [&"round", &"missile", &"craft"], "a partial order is completed (%s)" % [q.pd_order()])
	var bad := ShipPolicy.from_dict({"preset_name": "nonsense", "pd_range_m": 1e9, "discipline": 9, "pd_priorities": ["lasers", 4]})
	assert_true(bad.pd_range_m == 5000.0 and bad.discipline == ShipPolicy.Discipline.FREE and bad.pd_order() == ShipPolicy.PD_KINDS,
		"bad values clamped, unknown kinds dropped")


func test_schema_6_gives_old_vessels_the_defensive_policy() -> void:
	for s in ["", ".bak", ".tmp", ".v5"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE + s))
	var p := PlayerProfile.new(3)
	p.ensure_vessel(_template())
	var d := p.to_dict()
	d.schema_version = 5
	for v in d.vessels:
		(v as Dictionary).erase("policy")
	var f := FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var saved := PlayerProfile.path
	PlayerProfile.path = TEST_PROFILE
	var q := PlayerProfile.load_or_new()
	PlayerProfile.path = saved
	assert_true(q.loaded_schema == 5 and q.vessel.policy.preset_name == "Defensive", "a v5 vessel gets the Defensive policy (%s)" % q.vessel.policy.get("preset_name"))
	assert_true(FileAccess.file_exists(TEST_PROFILE + ".v5"), "the v5 original is kept before migrating")
	var std := ShipPolicy.preset("Standard")
	q.vessel.policy = std.to_dict()
	q.save(TEST_PROFILE)
	var r := PlayerProfile.load_file(TEST_PROFILE, PackedStringArray())
	assert_true(r.loaded_schema == PlayerProfile.SCHEMA_VERSION and ShipPolicy.from_dict(r.vessel.policy).autofire_enabled,
		"saved per vessel at the current schema (%d)" % r.loaded_schema)
	for s in ["", ".bak", ".tmp", ".v5"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE + s))


# --- Performance -------------------------------------------------------------------------

func test_a_three_ship_encounter_stays_inside_the_tick_budget() -> void:
	var bench: GDScript = load("res://tools/bench_sim.gd")
	var result: Dictionary = bench.run_encounter(3, 600)
	assert_true(int(result.peak_missiles) > 0 and int(result.peak_craft) > 0, "a real load: salvos (%d missiles) and wings (%d craft) in flight" % [
		result.peak_missiles, result.peak_craft])
	assert_less_equal(result.mean_ms, 8.0, "mean tick time (ms) of a 3-hostile encounter with wings and salvos (worst %.1f ms)" % result.worst_ms)
