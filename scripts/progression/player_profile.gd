class_name PlayerProfile
extends RefCounted
## The player's persistent state (spec §15): spare parts, the parts and
## blueprints found in salvage, loot pity, and the vessel in the hangar.
## Saved as versioned JSON (plain data, never code) at `path`.
##
## Ownership model (docs/ARCHITECTURE.md → Progression):
## - COMMON parts: unlimited, fabricated from spare parts.
## - Rarer equipment: `inventory[id]` units owned in total, installed or not.
##   A design may use at most that many.
## - Rarer hull modules and rooms: blueprints, unlocked once found.
## - A rarer unit destroyed in flight is written off when the vessel docks;
##   a lost vessel writes off every rarer unit it carried.

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://profile.json"
const STARTING_SPARE_PARTS := 60
## Spare parts a duplicate blueprint is scrapped for, by rarity.
const DUPLICATE_SPARES := [0, 10, 25, 60, 150]
const LOOT_LOG_LIMIT := 40

## Where load_or_new()/save() read and write (tests point this elsewhere).
static var path := DEFAULT_PATH

var spare_parts: int = STARTING_SPARE_PARTS
var inventory: Dictionary = {}  # equipment id (String) -> units owned
var unlocks: Dictionary = {}    # hull/room id (String) -> true
var pity: Dictionary = {"since_rare": 0, "since_legendary": 0}
var total_pulls: int = 0
var missions_completed: int = 0
var vessels_lost: int = 0
var loot_log: PackedStringArray = PackedStringArray()
## The vessel in the hangar; null until the first launch.
var vessel: ShipInstance

## Loot RNG, persisted so reloading cannot re-roll a pull.
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


# --- Ownership ---------------------------------------------------------------

func owned(id: StringName) -> int:
	return int(inventory.get(String(id), 0))


func is_unlocked(def: Resource) -> bool:
	return def.rarity == Rarity.Tier.COMMON or unlocks.has(String(def.id))


## Ownership errors for a design: locked hull/room blueprints and more
## rarer equipment than owned. Appended to `report`.
func check_design(bp: ShipBlueprint, catalog: ConstructionCatalog, report: ShipValidator.Report) -> void:
	for m in bp.modules:
		var def: HullModuleDefinition = catalog.hull.get(m.def_id)
		if def != null and not is_unlocked(def):
			report.add(ShipValidator.Severity.ERROR, &"blueprint_locked",
				"%s %s: %s blueprint not found yet. Salvage it, or use another module." % [def.display_name, m.id, Rarity.name_of(def.rarity)], m.id)
	for r in bp.rooms:
		var def: RoomDefinition = catalog.rooms.get(r.def_id)
		if def != null and not is_unlocked(def):
			report.add(ShipValidator.Severity.ERROR, &"blueprint_locked",
				"%s %s: %s blueprint not found yet. Salvage it, or use another room." % [def.display_name, r.id, Rarity.name_of(def.rarity)], r.id)
	var used := {}  # def id -> [count, first part id]
	for e in bp.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def == null or def.rarity == Rarity.Tier.COMMON:
			continue
		if not used.has(e.def_id):
			used[e.def_id] = [0, e.id]
		used[e.def_id][0] += 1
	for id in used:
		var need: int = used[id][0]
		if need > owned(id):
			var def: EquipmentDefinition = catalog.equipment[id]
			report.add(ShipValidator.Severity.ERROR, &"part_not_owned",
				"%s: the design uses %d but you own %d. Find more in salvage or remove %s." % [
					def.display_name, need, owned(id), "it" if need - owned(id) == 1 else "some"], used[id][1])


## Rarer equipment units `bp` uses, by definition id.
static func rare_units(bp: ShipBlueprint, catalog: ConstructionCatalog) -> Dictionary:
	var out := {}
	for e in bp.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def != null and def.rarity != Rarity.Tier.COMMON:
			out[String(e.def_id)] = int(out.get(String(e.def_id), 0)) + 1
	return out


# --- Loot ------------------------------------------------------------------------

## Pull `n` drops and grant them. Returns the drops in order.
func pull(n: int, catalog: ConstructionCatalog) -> Array[LootRoller.Drop]:
	var pool := LootRoller.build_pool(catalog)
	var out: Array[LootRoller.Drop] = []
	for i in n:
		var d := LootRoller.pull(_rng, pool, pity)
		if d == null:
			break
		grant(d)
		total_pulls += 1
		out.append(d)
	return out


func grant(d: LootRoller.Drop) -> void:
	match d.kind:
		&"spares":
			spare_parts += d.amount
		&"equipment":
			inventory[String(d.def_id)] = owned(d.def_id) + 1
		_:
			if unlocks.has(String(d.def_id)):
				d.duplicate = true
				d.amount = DUPLICATE_SPARES[d.rarity]
				spare_parts += d.amount
			else:
				unlocks[String(d.def_id)] = true
	loot_log.append("%s: %s" % [Rarity.name_of(d.rarity), d.describe()])
	if loot_log.size() > LOOT_LOG_LIMIT:
		loot_log.remove_at(0)


## Pulls left until each pity guarantee (1 = the next pull).
func pity_countdown() -> Vector2i:
	return Vector2i(LootRoller.RARE_PITY - int(pity.since_rare), LootRoller.LEGENDARY_PITY - int(pity.since_legendary))


# --- Vessel ------------------------------------------------------------------------

## The hangar vessel, created from `bp` the first time.
func ensure_vessel(bp: ShipBlueprint) -> ShipInstance:
	if vessel == null:
		vessel = ShipInstance.fresh(bp)
		vessel.record("Commissioned as %s" % bp.name)
	return vessel


## Back from a sortie with `after` (ShipSystems.condition()). Rarer units
## destroyed during the sortie are written off. Returns what was lost.
func dock(after: Dictionary, catalog: ConstructionCatalog) -> PackedStringArray:
	var lost := PackedStringArray()
	var before: Dictionary = vessel.condition.get("equipment", {})
	var now: Dictionary = after.get("equipment", {})
	for e in vessel.blueprint.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def == null or def.rarity == Rarity.Tier.COMMON:
			continue
		if float(now.get(e.id, 1.0)) <= 0.0 and float(before.get(e.id, 1.0)) > 0.0:
			inventory[String(e.def_id)] = maxi(owned(e.def_id) - 1, 0)
			lost.append("%s %s destroyed — written off" % [def.display_name, e.id])
	vessel.condition = after.duplicate(true)
	# The wounded recover ashore; the dead must be replaced (ServiceYard).
	var crew: Dictionary = vessel.condition.get("crew", {})
	crew.erase("wounded")
	if crew.is_empty():
		vessel.condition.erase("crew")
	vessel.sorties += 1
	vessel.record("Sortie %d: docked%s" % [vessel.sorties, " damaged" if vessel.is_damaged() else ""])
	for line in lost:
		vessel.record(line)
	return lost


## The vessel was lost: every rarer unit aboard that was still intact is
## written off; the fleet issues a new hull of the same design (the
## blueprint survives — spec §13).
func lose_vessel(catalog: ConstructionCatalog) -> PackedStringArray:
	var lost := PackedStringArray()
	for e in vessel.blueprint.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def == null or def.rarity == Rarity.Tier.COMMON or vessel.equipment_fraction(e.id) <= 0.0:
			continue
		inventory[String(e.def_id)] = maxi(owned(e.def_id) - 1, 0)
		lost.append("%s %s lost with the ship" % [def.display_name, e.id])
	var replacement := ShipInstance.fresh(vessel.blueprint)
	replacement.history = vessel.history.duplicate()
	replacement.record("%s lost after %d sorties; replacement hull issued" % [vessel.name, vessel.sorties])
	vessel = replacement
	vessels_lost += 1
	return lost


# --- Files -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"spare_parts": spare_parts,
		"inventory": inventory.duplicate(),
		"unlocks": unlocks.keys(),
		"pity": pity.duplicate(),
		"total_pulls": total_pulls,
		"missions_completed": missions_completed,
		"vessels_lost": vessels_lost,
		"loot_log": Array(loot_log),
		# 64-bit RNG values do not survive JSON numbers (doubles): strings.
		"rng": {"seed": str(_rng.seed), "state": str(_rng.state)},
		"vessel": vessel.to_dict() if vessel != null else null,
	}


static func from_dict(d: Dictionary, errors: PackedStringArray) -> PlayerProfile:
	var version: Variant = d.get("schema_version")
	if not (version is float or version is int):
		errors.append("Profile has no schema_version")
		return null
	if int(version) > SCHEMA_VERSION:
		errors.append("Profile schema %d is newer than this game supports (%d)" % [int(version), SCHEMA_VERSION])
		return null
	# Future schema migrations go here, oldest first.
	var p := PlayerProfile.new(1)
	p.spare_parts = int(d.get("spare_parts", STARTING_SPARE_PARTS))
	var inv: Variant = d.get("inventory", {})
	if inv is Dictionary:
		for k in inv:
			p.inventory[str(k)] = maxi(int(inv[k]), 0)
	for k in d.get("unlocks", []):
		p.unlocks[str(k)] = true
	var pt: Variant = d.get("pity", {})
	if pt is Dictionary:
		p.pity = {"since_rare": int(pt.get("since_rare", 0)), "since_legendary": int(pt.get("since_legendary", 0))}
	p.total_pulls = int(d.get("total_pulls", 0))
	p.missions_completed = int(d.get("missions_completed", 0))
	p.vessels_lost = int(d.get("vessels_lost", 0))
	for line in d.get("loot_log", []):
		p.loot_log.append(str(line))
	var rng: Variant = d.get("rng", {})
	if rng is Dictionary and rng.has("seed") and rng.has("state"):
		p._rng.seed = str(rng.seed).to_int()
		p._rng.state = str(rng.state).to_int()
	if d.get("vessel") is Dictionary:
		p.vessel = ShipInstance.from_dict(d.vessel, errors)
	return p


func save(file_path: String = "") -> Error:
	var target := file_path if file_path != "" else path
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var tmp := target + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t", false))
	file.close()
	# Write, then swap in: a crash mid-write never leaves a half-written profile.
	var abs_target := ProjectSettings.globalize_path(target)
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(abs_target)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_target)


static func load_file(file_path: String, errors: PackedStringArray) -> PlayerProfile:
	if not FileAccess.file_exists(file_path):
		errors.append("No profile at %s" % file_path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file_path)) != OK or not json.data is Dictionary:
		errors.append("Profile is not valid JSON (line %d)" % json.get_error_line())
		return null
	return from_dict(json.data, errors)


## The saved profile, or a new one when there is none. An unreadable
## profile is kept aside (never overwritten) and a new one started.
static func load_or_new() -> PlayerProfile:
	if not FileAccess.file_exists(path):
		return PlayerProfile.new()
	var errors := PackedStringArray()
	var p := load_file(path, errors)
	if p == null:
		var aside := path + ".unreadable"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(aside))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(aside))
		GameLog.warn("profile", "Could not read %s (%s); kept it as %s and started a new profile" % [path, "; ".join(errors), aside])
		return PlayerProfile.new()
	for e in errors:
		GameLog.warn("profile", e)
	return p
