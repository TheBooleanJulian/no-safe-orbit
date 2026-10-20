class_name DerelictField
extends RefCounted
## Wrecks that stay (Milestone 14, part 2). Every beaten ship left behind at
## the end of a sortie joins its location's derelict field, saved in the
## profile (PlayerProfile.derelicts). Later sorties there find up to
## SPAWN_PER_SORTIE of them a few kilometres out: G within beacon range
## salvages one again, for less each time (RESALVAGE_FACTOR per earlier
## salvage, no bounty), and stripping it leaves less for next time. Each
## sortie flown anywhere, every derelict loses DECAY of what is left; below
## BREAKUP_INTACT, or after MAX_AGE sorties, it breaks up and is gone.
##
## A record: {id, location, name, template (data/blueprints file), mission,
## variant (EnemyFactory.design's), intact (0–1), salvaged (times), age
## (sorties)}. The hull is rebuilt from template, mission and variant, then
## wrecked to `intact` (wreck_to), so the save stays small.

const MAX_PER_LOCATION := 6
const SPAWN_PER_SORTIE := 2
const DECAY := 0.85
const BREAKUP_INTACT := 0.1
const MAX_AGE := 8
const RESALVAGE_FACTOR := 0.5
## What a re-salvage strips from what is left.
const STRIP_FACTOR := 0.5
## Where they are found: this far out (m), seeded per record.
const SPAWN_MIN_M := 4000.0
const SPAWN_MAX_M := 7000.0


## Add a beaten ship to `location_id`'s field (the oldest past the limit go).
static func record(derelicts: Array, location_id: String, ship_name: String, template: String, mission: int, variant: int,
		intact: float, salvaged: int) -> void:
	var serial := 0
	for d in derelicts:
		serial = maxi(serial, int(str(d.id).trim_prefix("d")))
	derelicts.append({"id": "d%d" % (serial + 1), "location": location_id, "name": ship_name, "template": template,
		"mission": mission, "variant": variant, "intact": clampf(intact, 0.0, 1.0), "salvaged": salvaged, "age": 0})
	var here := derelicts.filter(func(d: Dictionary) -> bool: return d.location == location_id)
	while here.size() > MAX_PER_LOCATION:
		derelicts.erase(here.pop_front())


## A sortie went by: every derelict decays and ages; returns a line for each
## that broke up (and is gone).
static func age_all(derelicts: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for d in derelicts.duplicate():
		d.intact = float(d.intact) * DECAY
		d.age = int(d.age) + 1
		if float(d.intact) < BREAKUP_INTACT or int(d.age) >= MAX_AGE:
			derelicts.erase(d)
			lines.append("The derelict %s broke up (%s)" % [d.name, Location.by_id(str(d.location)).display_name])
	return lines


## The derelicts a sortie at `location_id` finds: the newest, at most
## SPAWN_PER_SORTIE.
static func at(derelicts: Array, location_id: String) -> Array:
	var here := derelicts.filter(func(d: Dictionary) -> bool: return d.location == location_id)
	here.reverse()
	return here.slice(0, SPAWN_PER_SORTIE)


static func by_id(derelicts: Array, id: String) -> Dictionary:
	for d in derelicts:
		if str(d.id) == id:
			return d
	return {}


## Where a derelict lies relative to the start (seeded, so it stays put).
static func spawn_offset(d: Dictionary) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("derelict|%s|%s" % [d.id, d.location])
	var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)).normalized()
	return dir * rng.randf_range(SPAWN_MIN_M, SPAWN_MAX_M)


## Wreck a rebuilt hull to `intact` (its systems' surviving hit points):
## the reactors are dead (a derelict has no power), then the rest are worn
## at random until it is down to `intact`; modules are holed in proportion.
## Hit points are set directly — a long-dead hulk doesn't explode again.
## Seeded.
static func wreck_to(sys: ShipSystems, intact: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for e in sys.equipment:
		if e.def.kind == EquipmentDefinition.Kind.REACTOR:
			e.hp = 0.0
	var order: Array = sys.equipment.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = order[i]
		order[i] = order[j]
		order[j] = swap
	var guard := 0
	while _intact(sys) > intact + 1e-3 and guard < 50:
		guard += 1
		for e: ShipSystems.EquipmentState in order:
			if _intact(sys) <= intact + 1e-3:
				break
			e.hp = maxf(e.hp - e.max_hp * rng.randf_range(0.2, 0.6), 0.0)
	for m in sys.modules:
		if rng.randf() < (1.0 - intact) * 0.5:
			m.structure = maxf(m.structure - m.max_structure * rng.randf_range(0.3, 1.0), 0.0)
	sys.invalidate()
	sys.solve_power()


static func _intact(sys: ShipSystems) -> float:
	return sys.intact_fraction()


## A re-salvage's yield: {scrap (credits), pulls (crates)} for a derelict
## salvaged `times` before, from its intact scrap value and crate count.
static func resalvage_yield(scrap_value: int, pulls: int, times: int) -> Dictionary:
	var f := pow(RESALVAGE_FACTOR, times)
	return {"scrap": roundi(scrap_value * Salvage.BEACON_SCRAP_RATE * f), "pulls": maxi(roundi(pulls * f), 1)}
