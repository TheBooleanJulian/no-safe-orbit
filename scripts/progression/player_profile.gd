class_name PlayerProfile
extends RefCounted
## The player's persistent state (spec §15): credits, what is banked at the
## station (spare parts, parts and blueprints found in salvage), loot pity,
## and the vessel in the hangar with whatever is in its cargo hold.
## Saved as versioned JSON (plain data, never code) at `path`.
##
## Ownership model (docs/ARCHITECTURE.md → Progression):
## - COMMON parts: unlimited, fabricated from spare parts.
## - Rarer equipment: `inventory[id]` units banked in total. Any design —
##   any vessel in the hangar — may use up to that many: the yard moves
##   units between hulls as they are refitted.
## - Rarer hull modules and rooms: blueprints, unlocked once banked.
## - Salvage goes into the vessel's cargo hold. It is only safe once banked
##   at the station (bank_cargo). Losing the vessel loses the cargo — and
##   only the cargo: a respawn fee in credits rehires, rebuilds and rearms
##   the same design.

## v3: a hangar of vessels (one active) instead of a single vessel.
## v4: parts that stopped being common are granted to the saves using them.
const SCHEMA_VERSION := 4
## Equipment that was common before v4: owners get as many units as their
## designs already use.
const NO_LONGER_COMMON_V4 := ["kinetic_cannon"]
## Earth Shipyard's fee for laying down a new hull (credits); its parts are
## paid in spare parts like any refit.
const NEW_HULL_FEE := 250
const DEFAULT_PATH := "user://profile.json"
const STARTING_SPARE_PARTS := 60
const STARTING_CREDITS := 300
## Respawn: base fee plus a fee per berth (rehiring the crew).
const RESPAWN_BASE_FEE := 50
const RESPAWN_FEE_PER_BERTH := 5
## Station shop: spare parts bought in lots.
const PARTS_LOT := 10
const PARTS_LOT_PRICE := 25
## Spare parts a duplicate blueprint is scrapped for, by rarity.
const DUPLICATE_SPARES := [0, 10, 25, 60, 150]
const LOOT_LOG_LIMIT := 40

## Where load_or_new()/save() read and write (tests point this elsewhere).
static var path := DEFAULT_PATH

var spare_parts: int = STARTING_SPARE_PARTS
var credits: int = STARTING_CREDITS
## The last sortie's debrief (CombatLog.to_dict()), {} = none.
var last_debrief: Dictionary = {}
var inventory: Dictionary = {}  # equipment id (String) -> units owned
var unlocks: Dictionary = {}    # hull/room id (String) -> true
var pity: Dictionary = {"since_rare": 0, "since_legendary": 0}
var total_pulls: int = 0
var missions_completed: int = 0
var vessels_lost: int = 0
var loot_log: PackedStringArray = PackedStringArray()
## Every vessel in the hangar, and which one is flown and edited.
var vessels: Array[ShipInstance] = []
var active_vessel: int = 0
## Set by the shipyard while a new hull is on the slip (not saved): every
## vessel's rarer parts are then spoken for, the active one's included.
var designing_new: bool = false
## The active vessel; null until the first launch. Assigning replaces it.
var vessel: ShipInstance:
	get:
		return vessels[active_vessel] if active_vessel >= 0 and active_vessel < vessels.size() else null
	set(v):
		if v == null:
			return
		if vessels.is_empty():
			vessels.append(v)
			active_vessel = 0
		else:
			vessels[active_vessel] = v

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
		var free := owned(id)
		if need > free:
			var def: EquipmentDefinition = catalog.equipment[id]
			report.add(ShipValidator.Severity.ERROR, &"part_not_owned",
				"%s: the design uses %d but you own %d. Find more in salvage or remove %s." % [
					def.display_name, need, owned(id), "it" if need - free == 1 else "some"], used[id][1])


## Rarer equipment units `bp` uses, by definition id.
static func rare_units(bp: ShipBlueprint, catalog: ConstructionCatalog) -> Dictionary:
	var out := {}
	for e in bp.equipment:
		var def: EquipmentDefinition = catalog.equipment.get(e.def_id)
		if def != null and def.rarity != Rarity.Tier.COMMON:
			out[String(e.def_id)] = int(out.get(String(e.def_id), 0)) + 1
	return out


# --- Loot ------------------------------------------------------------------------

## Roll `n` drops (not yet stowed or banked). Returns them in order.
func pull(n: int, catalog: ConstructionCatalog) -> Array[LootRoller.Drop]:
	var pool := LootRoller.build_pool(catalog)
	var out: Array[LootRoller.Drop] = []
	for i in n:
		var d := LootRoller.pull(_rng, pool, pity)
		if d == null:
			break
		total_pulls += 1
		out.append(d)
	return out


## Open `n` salvage crates: each holds loot with `chance`, else it is empty
## (null in the result). Pity only counts crates that hold loot.
func open_crates(n: int, chance: float, catalog: ConstructionCatalog) -> Array:
	var pool := LootRoller.build_pool(catalog)
	var out := []
	for i in n:
		total_pulls += 1
		if _rng.randf() >= chance:
			out.append(null)
			continue
		out.append(LootRoller.pull(_rng, pool, pity))
	return out


## Developer aid (shipyard button): free credits for testing.
func dev_grant_credits(amount: int) -> void:
	credits += amount


## Put a drop in the vessel's cargo hold (at risk until banked).
func stow(d: LootRoller.Drop) -> void:
	var cargo := vessel.cargo
	match d.kind:
		&"spares":
			cargo["spare_parts"] = int(cargo.get("spare_parts", 0)) + d.amount
		&"equipment":
			var eq: Dictionary = cargo.get_or_add("equipment", {})
			eq[String(d.def_id)] = int(eq.get(String(d.def_id), 0)) + 1
		_:
			var bps: Dictionary = cargo.get_or_add("blueprints", {})
			bps[String(d.def_id)] = [String(d.kind), d.rarity, int(bps.get(String(d.def_id), [0, 0, 0])[2]) + 1]
	loot_log.append("%s: %s (in cargo)" % [Rarity.name_of(d.rarity), d.describe()])
	if loot_log.size() > LOOT_LOG_LIMIT:
		loot_log.remove_at(0)


## Unload the cargo hold into the station bank. Returns what was banked.
func bank_cargo(catalog: ConstructionCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	var cargo := vessel.cargo
	var parts := int(cargo.get("spare_parts", 0))
	if parts > 0:
		spare_parts += parts
		out.append("%d spare parts" % parts)
	var eq: Dictionary = cargo.get("equipment", {})
	for id in eq:
		inventory[str(id)] = owned(StringName(id)) + int(eq[id])
		var def: EquipmentDefinition = catalog.equipment.get(StringName(id))
		out.append("%s ×%d" % [def.display_name if def != null else str(id), int(eq[id])])
	var bps: Dictionary = cargo.get("blueprints", {})
	for id in bps:
		var entry: Array = bps[id]
		for k in int(entry[2]):
			var d := LootRoller.Drop.new()
			d.kind = StringName(entry[0])
			d.def_id = StringName(id)
			d.rarity = int(entry[1])
			var table: Dictionary = catalog.hull if d.kind == &"hull" else catalog.rooms
			d.display_name = table[d.def_id].display_name if table.has(d.def_id) else str(id)
			_bank_blueprint(d)
			out.append(d.describe())
	vessel.cargo = {}
	if not out.is_empty():
		vessel.record("Banked: %s" % ", ".join(out))
	return out


## Bank a drop directly (no cargo stage).
func grant(d: LootRoller.Drop) -> void:
	match d.kind:
		&"spares":
			spare_parts += d.amount
		&"equipment":
			inventory[String(d.def_id)] = owned(d.def_id) + 1
		_:
			_bank_blueprint(d)
	loot_log.append("%s: %s" % [Rarity.name_of(d.rarity), d.describe()])
	if loot_log.size() > LOOT_LOG_LIMIT:
		loot_log.remove_at(0)


func _bank_blueprint(d: LootRoller.Drop) -> void:
	if unlocks.has(String(d.def_id)):
		d.duplicate = true
		d.amount = DUPLICATE_SPARES[d.rarity]
		spare_parts += d.amount
	else:
		unlocks[String(d.def_id)] = true


## Buy a lot of spare parts at the station. False if credits are short.
func buy_spare_parts() -> bool:
	if credits < PARTS_LOT_PRICE:
		return false
	credits -= PARTS_LOT_PRICE
	spare_parts += PARTS_LOT
	return true


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


## Spare parts and credits a new hull to `bp` costs: every part built new,
## and the yard's fee.
func new_hull_cost(bp: ShipBlueprint, catalog: ConstructionCatalog) -> Vector2i:
	var empty := ShipInstance.new()
	empty.blueprint = ShipBlueprint.new()
	return Vector2i(ServiceYard.total_cost(ServiceYard.refit_jobs(empty, bp, catalog)), NEW_HULL_FEE)


## Lay down a new vessel to `bp` and make it the active one. Returns "" on
## success, or why not (the cost is only taken on success).
func commission(bp: ShipBlueprint, catalog: ConstructionCatalog) -> String:
	var cost := new_hull_cost(bp, catalog)
	if cost.x > spare_parts:
		return "A new hull to this design needs %d spare parts; you have %d" % [cost.x, spare_parts]
	if cost.y > credits:
		return "The yard's fee is %d credits; you have %d" % [cost.y, credits]
	spare_parts -= cost.x
	credits -= cost.y
	var v := ShipInstance.fresh(bp)
	v.record("Commissioned as %s (%d spare parts, %d credits)" % [bp.name, cost.x, cost.y])
	vessels.append(v)
	active_vessel = vessels.size() - 1
	return ""


## Make vessel `index` the active one (flown and edited).
func select_vessel(index: int) -> bool:
	if index < 0 or index >= vessels.size():
		return false
	active_vessel = index
	return true


## Back at the station with `after` (ShipSystems.condition()): the vessel
## keeps its damage (repairs are paid for at the yard).
func dock(after: Dictionary, _catalog: ConstructionCatalog) -> PackedStringArray:
	var lost := PackedStringArray()
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


## Respawn fee for the vessel's design: rehire, rebuild, rearm.
func respawn_fee(catalog: ConstructionCatalog) -> int:
	var stats := ShipStats.compute(vessel.blueprint, ShipGrid.build(vessel.blueprint, catalog))
	return RESPAWN_BASE_FEE + RESPAWN_FEE_PER_BERTH * stats.crew_capacity


## The vessel was lost. Only its cargo goes with it: the station rehires,
## rebuilds and rearms the same design (parts installed in it included)
## for the respawn fee in credits (as much as the player has). Returns what
## was lost and paid.
func lose_vessel(catalog: ConstructionCatalog) -> PackedStringArray:
	var lost := PackedStringArray()
	var cargo := vessel.cargo
	if int(cargo.get("spare_parts", 0)) > 0:
		lost.append("%d spare parts in the hold lost" % int(cargo.spare_parts))
	for id in cargo.get("equipment", {}):
		lost.append("%s ×%d in the hold lost" % [id, int(cargo.equipment[id])])
	for id in cargo.get("blueprints", {}):
		lost.append("%s blueprint in the hold lost" % id)
	var fee := respawn_fee(catalog)
	var paid := mini(fee, credits)
	credits -= paid
	lost.append("Respawn fee: %d credits (rehire, rebuild, rearm)%s" % [paid, "" if paid == fee else " — all you had (%d due)" % fee])
	var replacement := ShipInstance.fresh(vessel.blueprint)
	replacement.history = vessel.history.duplicate()
	replacement.sorties = vessel.sorties
	replacement.salvaged = vessel.salvaged
	replacement.record("%s lost on sortie %d; rebuilt to the same design for %d credits" % [vessel.name, vessel.sorties + 1, paid])
	vessel = replacement
	vessels_lost += 1
	return lost


# --- Files -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"spare_parts": spare_parts,
		"credits": credits,
		"last_debrief": last_debrief.duplicate(true),
		"inventory": inventory.duplicate(),
		"unlocks": unlocks.keys(),
		"pity": pity.duplicate(),
		"total_pulls": total_pulls,
		"missions_completed": missions_completed,
		"vessels_lost": vessels_lost,
		"loot_log": Array(loot_log),
		# 64-bit RNG values do not survive JSON numbers (doubles): strings.
		"rng": {"seed": str(_rng.seed), "state": str(_rng.state)},
		"vessels": vessels.map(func(v: ShipInstance) -> Dictionary: return v.to_dict()),
		"active_vessel": active_vessel,
	}


static func from_dict(d: Dictionary, errors: PackedStringArray) -> PlayerProfile:
	var version: Variant = d.get("schema_version")
	if not (version is float or version is int):
		errors.append("Profile has no schema_version")
		return null
	if int(version) > SCHEMA_VERSION:
		errors.append("Profile schema %d is newer than this game supports (%d)" % [int(version), SCHEMA_VERSION])
		return null
	# Migrations, oldest first. v1 → v2: credits and cargo added (defaults).
	# v2 → v3: the single "vessel" becomes the hangar's only vessel.
	var p := PlayerProfile.new(1)
	p.spare_parts = int(d.get("spare_parts", STARTING_SPARE_PARTS))
	p.credits = int(d.get("credits", STARTING_CREDITS))
	var debrief: Variant = d.get("last_debrief", {})
	p.last_debrief = (debrief as Dictionary).duplicate(true) if debrief is Dictionary else {}
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
		var v := ShipInstance.from_dict(d.vessel, errors)
		if v != null:
			p.vessels.append(v)
	for vd in d.get("vessels", []):
		if vd is Dictionary:
			var v := ShipInstance.from_dict(vd, errors)
			if v != null:
				p.vessels.append(v)
	for v in p.vessels:
		BlueprintFix.fit_spans(v.blueprint, ConstructionCatalog.default_catalog())
	p.active_vessel = clampi(int(d.get("active_vessel", 0)), 0, maxi(p.vessels.size() - 1, 0))
	if int(version) < 4:
		var designs: Array[ShipBlueprint] = []
		for v in p.vessels:
			designs.append(v.blueprint)
		for file in BlueprintIO.list_user():
			var bp := BlueprintIO.load_file(file, PackedStringArray())
			if bp != null:
				designs.append(bp)
		p.grant_used(NO_LONGER_COMMON_V4, designs)
	return p


## Migration aid: own at least as many of each of `ids` as any one of
## `designs` uses.
func grant_used(ids: Array, designs: Array[ShipBlueprint]) -> void:
	for id in ids:
		var most := 0
		for bp in designs:
			var n := 0
			for e in bp.equipment:
				if String(e.def_id) == id:
					n += 1
			most = maxi(most, n)
		if most > owned(StringName(id)):
			inventory[id] = most


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
