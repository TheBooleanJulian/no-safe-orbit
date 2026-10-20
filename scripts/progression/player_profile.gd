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
## v6: each vessel's automation policy (ShipInstance.policy); older vessels
##     get the Defensive preset, which is what they already did.
## v5: the tutorial's and the mission chain's progress (an existing player
##     is not offered the tutorial again; [F2] still starts it).
## v7: where the ship is docked (location), the locations on the map
##     (known_locations: Earth and the Moon to start) and the encounter size
##     picked for the next sortie; older saves are at Earth, size 1.
## v8: the mission board (board, board_sortie, board_seed) and the
##     accepted contract (active_contract); older saves get a fresh board.
## v9: the jump drive's reserve in the vessel's stores
##     (condition.stores.jump_reserve_kg); older vessels start it full.
## v10: artifact surveys — the next sortie's survey target and the codex of
##     objects surveyed; older saves have surveyed nothing.
const SCHEMA_VERSION := 10
## Ships per encounter the map offers (EnemyFactory spawns them).
const MAX_ENCOUNTER := 3
## Locations every player knows from the start (brokers sell more).
const STARTING_LOCATIONS := ["earth", "moon"]
## The last good save, kept beside the profile (rolling, one deep).
const BACKUP_SUFFIX := ".bak"
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
## What load_or_new() had to do to get a profile (restored a backup, kept a
## damaged file aside…), for the player to read; "" when the load was clean.
static var load_notice := ""

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
## Tutorial.to_dict() and MissionChain.to_dict().
var tutorial: Dictionary = {"state": "offer", "step": 0}
var campaign: Dictionary = {"step": 0}
## What M fires (MissileSalvo.Mode) and the sequence mode's warhead order.
## The station the vessel is docked at and launches from (Location id).
var location: String = Location.DEFAULT_ID
var known_locations: Array = STARTING_LOCATIONS.duplicate()
## Ships in the next encounter, 1–MAX_ENCOUNTER (picked on the map).
var encounter_size: int = 1
## The mission board (ContractBoard): offers, the sortie count they were
## made for, the profile's seed for them; the accepted contract ({} = none).
var board: Array = []
var board_sortie: int = -1
var board_seed: int = 0
var active_contract: Dictionary = {}
## Milestone 14: the artifact the next sortie surveys ("" = an ordinary
## sortie) and the codex: artifact id -> the sortie it was surveyed on.
var survey_target: String = ""
var codex: Dictionary = {}
var missile_mode: int = MissileSalvo.Mode.ALL
var missile_order: Array = MissileSalvo.DEFAULT_ORDER.duplicate()
## The schema the profile was read from (SCHEMA_VERSION for a new one).
var loaded_schema: int = SCHEMA_VERSION
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

## Crew for hire at the station: [{name, role, skill, fee}], refreshed each
## sortie.
var hire_pool: Array = []
## The quartermaster's stock: [{id (equipment), price}], refreshed each sortie.
var vendor_stock: Array = []
## Earth Shipyard upgrades bought: TechTree id -> level.
var tech: Dictionary = {}

## Loot RNG, persisted so reloading cannot re-roll a pull.
var _rng := RandomNumberGenerator.new()

const HIRE_POOL_SIZE := 4
## Hiring fee: base plus per skill level (credits).
const HIRE_FEE := 40
const HIRE_FEE_PER_SKILL := 40
const VENDOR_STOCK_SIZE := 3
## Quartermaster prices by rarity (credits).
const VENDOR_PRICES := [0, 450, 1200, 3000, 8000]


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	board_seed = int(_rng.seed % 2147483647)


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


# --- Crew, quartermaster, upgrades ------------------------------------------------

## New faces at the station and new stock on the quartermaster's shelves.
func refresh_station(catalog: ConstructionCatalog) -> void:
	hire_pool.clear()
	for i in HIRE_POOL_SIZE:
		var skill := 0 if _rng.randf() < 0.55 else (1 if _rng.randf() < 0.75 else 2)
		hire_pool.append({"name": CrewNames.pick(_rng), "role": _rng.randi() % CrewRoster.Role.size(), "skill": skill,
			"fee": HIRE_FEE + HIRE_FEE_PER_SKILL * skill})
	# Each station's own shelves and prices (Location).
	var here := Location.by_id(location)
	for c in hire_pool:
		c.fee = roundi(float(c.fee) * here.price_factor)
	vendor_stock.clear()
	var ids: Array = []
	for id in ConstructionCatalog.sorted_ids(catalog.equipment):
		var def: EquipmentDefinition = catalog.equipment[id]
		if def.rarity != Rarity.Tier.COMMON and def.rarity <= mini(here.vendor_max_rarity, Rarity.Tier.EPIC) and not def.legacy:
			ids.append(id)
	for i in mini(here.vendor_stock_size, ids.size()):
		var id: StringName = ids.pop_at(_rng.randi() % ids.size())
		vendor_stock.append({"id": String(id), "price": roundi(VENDOR_PRICES[catalog.equipment[id].rarity] * here.price_factor)})


## Berths on the active vessel's design.
func berths(catalog: ConstructionCatalog) -> int:
	var grid := ShipGrid.build(vessel.blueprint, catalog)
	return ShipStats.compute(vessel.blueprint, grid).crew_capacity


## Hire candidate `i` onto the active vessel. "" or why not.
func hire(i: int, catalog: ConstructionCatalog) -> String:
	if i < 0 or i >= hire_pool.size():
		return "no such candidate"
	vessel.ensure_crew(catalog)
	if vessel.crew.size() >= berths(catalog):
		return "no free berth — dismiss someone or build more quarters"
	var c: Dictionary = hire_pool[i]
	if credits < int(c.fee):
		return "%s's fee is %d credits; you have %d" % [c.name, c.fee, credits]
	credits -= int(c.fee)
	vessel.crew.append({"name": c.name, "role": c.role, "skill": c.skill})
	hire_pool.remove_at(i)
	vessel.record("Hired %s (%s)" % [c.name, CrewRoster.ROLE_NAMES[c.role]])
	return ""


func dismiss(i: int) -> String:
	if i < 0 or i >= vessel.crew.size():
		return "no such crew member"
	var c: Dictionary = vessel.crew.pop_at(i)
	vessel.record("Dismissed %s" % c.name)
	return ""


## Give crew member `i` a new role (at the station: no walking).
func set_crew_role(i: int, role: int) -> void:
	if i >= 0 and i < vessel.crew.size():
		vessel.crew[i].role = clampi(role, 0, CrewRoster.Role.size() - 1)


## Buy the quartermaster's item `i`: one unit into the station bank.
func buy_stock(i: int, catalog: ConstructionCatalog) -> String:
	if i < 0 or i >= vendor_stock.size():
		return "sold out"
	var item: Dictionary = vendor_stock[i]
	if credits < int(item.price):
		return "%d credits needed; you have %d" % [item.price, credits]
	credits -= int(item.price)
	inventory[str(item.id)] = owned(StringName(item.id)) + 1
	vendor_stock.remove_at(i)
	var def: EquipmentDefinition = catalog.equipment.get(StringName(item.id))
	loot_log.append("Bought: %s" % (def.display_name if def != null else str(item.id)))
	return ""


func tech_level(id: String) -> int:
	return int(tech.get(id, 0))


## Buy the next level of upgrade `id`. "" or why not.
func buy_tech(id: String) -> String:
	if TechTree.node(id).is_empty():
		return "no such upgrade"
	var cost := TechTree.next_cost(tech_level(id))
	if cost < 0:
		return "already at the top level"
	if credits < cost:
		return "%d credits needed; you have %d" % [cost, credits]
	credits -= cost
	tech[id] = tech_level(id) + 1
	return ""


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


## Buy a ship to `bp` from the dealer, its standard crew hired, and make it
## the active vessel. "" or why not (paid only on success).
func buy_ship(bp: ShipBlueprint, catalog: ConstructionCatalog) -> String:
	var price := ServiceYard.dealer_price(bp, catalog)
	if int(price.total) > credits:
		return "%s costs %d credits; you have %d" % [bp.name, price.total, credits]
	credits -= int(price.total)
	var v := ShipInstance.fresh(bp.duplicate_blueprint())
	v.ensure_crew(catalog)
	v.record("Bought from the dealer for %d credits (crew of %d included)" % [price.total, price.crew_count])
	vessels.append(v)
	active_vessel = vessels.size() - 1
	return ""


## Scrap vessel `index` for spare parts (ServiceYard.scrap_value); its hold
## goes with it. Not the last vessel. Returns the parts, or -1.
func scrap_vessel(index: int, catalog: ConstructionCatalog) -> int:
	if index < 0 or index >= vessels.size() or vessels.size() <= 1:
		return -1
	var parts := ServiceYard.scrap_value(vessels[index], catalog)
	spare_parts += parts
	vessels.remove_at(index)
	active_vessel = clampi(active_vessel if active_vessel < index else active_vessel - 1, 0, vessels.size() - 1)
	return parts


## Sorties flown in every vessel (and lost ones): the board refreshes on it.
func sorties_flown() -> int:
	var n := vessels_lost
	for v in vessels:
		n += v.sorties
	return n


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
	for n in vessel.bury_dead():
		lost.append("%s killed in action" % n)
	vessel.sorties += 1
	refresh_station(ConstructionCatalog.default_catalog())
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
		"hire_pool": hire_pool.duplicate(true),
		"vendor_stock": vendor_stock.duplicate(true),
		"tech": tech.duplicate(),
		"tutorial": tutorial.duplicate(),
		"campaign": campaign.duplicate(),
		"missile_mode": missile_mode,
		"missile_order": missile_order.duplicate(),
		"location": location,
		"known_locations": known_locations.duplicate(),
		"encounter_size": encounter_size,
		"board": board.duplicate(true),
		"board_sortie": board_sortie,
		"board_seed": board_seed,
		"active_contract": active_contract.duplicate(true),
		"survey_target": survey_target,
		"codex": codex.duplicate(),
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
	p.loaded_schema = int(version)
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
		BlueprintFix.prune_plates(v.blueprint, ShipGrid.build(v.blueprint, ConstructionCatalog.default_catalog()))
	p.active_vessel = clampi(int(d.get("active_vessel", 0)), 0, maxi(p.vessels.size() - 1, 0))
	for c in d.get("hire_pool", []):
		if c is Dictionary:
			p.hire_pool.append({"name": str(c.get("name", "")), "role": int(c.get("role", 6)), "skill": int(c.get("skill", 0)), "fee": int(c.get("fee", HIRE_FEE))})
	for s in d.get("vendor_stock", []):
		if s is Dictionary:
			p.vendor_stock.append({"id": str(s.get("id", "")), "price": int(s.get("price", 0))})
	var tk: Variant = d.get("tech", {})
	if tk is Dictionary:
		for id in tk:
			p.tech[str(id)] = clampi(int(tk[id]), 0, TechTree.MAX_LEVEL)
	_read_v5_progress(p, d)
	p.missile_mode = clampi(int(d.get("missile_mode", MissileSalvo.Mode.ALL)), 0, MissileSalvo.Mode.size() - 1)
	var order: Variant = d.get("missile_order", [])
	p.missile_order = MissileSalvo.sanitize_order(order if order is Array else [])
	_read_v7_map(p, d)
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


## v7: location, known locations and encounter size (defaults for older
## saves: docked at Earth, Earth and the Moon known, one ship).
static func _read_v7_map(p: PlayerProfile, d: Dictionary) -> void:
	var known: Variant = d.get("known_locations", [])
	if known is Array:
		for id in known:
			if str(id) not in p.known_locations and Location.by_id(str(id)).id == str(id):
				p.known_locations.append(str(id))
	var here := str(d.get("location", Location.DEFAULT_ID))
	p.location = here if here in p.known_locations else Location.DEFAULT_ID
	p.encounter_size = clampi(int(d.get("encounter_size", 1)), 1, MAX_ENCOUNTER)
	_read_v8_board(p, d)


## v8: the mission board and the accepted contract (older saves: a fresh
## board on the next visit to the yard, no contract).
static func _read_v8_board(p: PlayerProfile, d: Dictionary) -> void:
	var b: Variant = d.get("board", [])
	if b is Array:
		for c in b:
			if c is Dictionary and (c as Dictionary).has("goal") and (c as Dictionary).has("id"):
				p.board.append((c as Dictionary).duplicate(true))
	p.board_sortie = int(d.get("board_sortie", -1))
	p.board_seed = int(d.get("board_seed", hash(str(d.get("rng", {})))))
	var a: Variant = d.get("active_contract", {})
	if a is Dictionary and (a as Dictionary).has("goal"):
		p.active_contract = (a as Dictionary).duplicate(true)
	# v10: surveys (an unknown or missing artifact is dropped).
	var target := str(d.get("survey_target", ""))
	p.survey_target = target if Artifact.by_id(target) != null else ""
	var c: Variant = d.get("codex", {})
	if c is Dictionary:
		for id in c:
			if Artifact.by_id(str(id)) != null:
				p.codex[str(id)] = int(c[id])


## The docked vessel's tanks: {mass_kg (with what is aboard), main_kg,
## capacity_kg, reserve_kg, reserve_capacity_kg}. No stores = full.
func vessel_tanks(catalog: ConstructionCatalog) -> Dictionary:
	var stats := ShipStats.compute(vessel.blueprint, ShipGrid.build(vessel.blueprint, catalog))
	var stores: Dictionary = vessel.condition.get("stores", {})
	var drive := JumpDrive.standard()
	var reserve_cap := drive.reserve_capacity_kg(stats.propellant_capacity_kg)
	var main := minf(float(stores.get("propellant_kg", stats.propellant_capacity_kg)), stats.propellant_capacity_kg)
	var reserve := minf(float(stores.get("jump_reserve_kg", reserve_cap)), reserve_cap)
	return {"mass_kg": stats.mass_kg + main + reserve, "main_kg": main, "capacity_kg": stats.propellant_capacity_kg,
		"reserve_kg": reserve, "reserve_capacity_kg": reserve_cap}


## Propellant (kg) the docked vessel's jump to `location_id` would burn.
func jump_cost_kg(location_id: String, catalog: ConstructionCatalog) -> float:
	var here := Location.by_id(location)
	var there := Location.by_id(location_id)
	if here.id == there.id:
		return 0.0
	return JumpDrive.standard().cost_kg(float(vessel_tanks(catalog).mass_kg), Location.distance_m(here, there))


# --- Artifact surveys (Milestone 14) ------------------------------------------------

## Propellant (kg) a survey of `a` burns beyond an ordinary sortie: for a
## deep-space object, the jump out and back, paid at launch with the tanks
## full; 0 for one in a location's orbit.
func survey_cost_kg(a: Artifact, catalog: ConstructionCatalog) -> float:
	if not a.is_deep_space():
		return 0.0
	var t := vessel_tanks(catalog)
	var full_mass := float(t.mass_kg) - float(t.main_kg) - float(t.reserve_kg) + float(t.capacity_kg) + float(t.reserve_capacity_kg)
	return 2.0 * JumpDrive.standard().cost_kg(full_mass, a.distance_from(Location.by_id(location)))


## Make `artifact_id` the next sortie's survey ("" cancels). "" or why not:
## it must be surveyed from where the vessel is docked, and a deep-space
## round trip must fit in the full tanks and reserve.
func choose_survey(artifact_id: String, catalog: ConstructionCatalog) -> String:
	if artifact_id == "":
		survey_target = ""
		return ""
	var a := Artifact.by_id(artifact_id)
	if a == null:
		return "No record of that object"
	if not a.is_deep_space() and (a.location() == null or a.location().id != location):
		return "%s is surveyed from the %s — jump there first" % [a.display_name, a.location().station_name if a.location() != null else "?"]
	var t := vessel_tanks(catalog)
	var need := survey_cost_kg(a, catalog)
	var room := float(t.capacity_kg) + float(t.reserve_capacity_kg)
	if need > room:
		return "The round trip to %s burns %s; full tanks and the jump reserve hold %s — it needs a ship with more tankage for its mass" % [
			a.display_name, JumpDrive.tonnes(need), JumpDrive.tonnes(room)]
	survey_target = a.id
	return ""


## A survey finished: the record goes into the codex and the fee is paid
## (once per object). Returns the credits paid.
func complete_survey(artifact_id: String) -> int:
	var a := Artifact.by_id(artifact_id)
	if a == null or codex.has(artifact_id):
		return 0
	codex[artifact_id] = sorties_flown()
	credits += a.survey_credits
	loot_log.append("Surveyed %s: +%d credits" % [a.display_name, a.survey_credits])
	return a.survey_credits


## Locations an information broker sells (not on the map yet), in map order.
func brokers() -> Array[Location]:
	var out: Array[Location] = []
	for loc in Location.all():
		if loc.id not in known_locations and loc.broker_price > 0:
			out.append(loc)
	return out


## Buy a broker's charts: the location goes on the map. "" or why not.
func buy_location(location_id: String) -> String:
	var loc := Location.by_id(location_id)
	if loc.id != location_id or loc.broker_price <= 0:
		return "No broker sells charts for that"
	if location_id in known_locations:
		return "%s is already on your map" % loc.display_name
	if credits < loc.broker_price:
		return "%s wants %d credits for the charts; you have %d" % [loc.broker_name, loc.broker_price, credits]
	credits -= loc.broker_price
	known_locations.append(loc.id)
	loot_log.append("Charts bought: %s (%s)" % [loc.display_name, loc.station_name])
	return ""


## Jump the docked vessel to the station at a known location, paying the
## propellant from its main tank, then the drive's reserve (the yard refills
## both, for credits, at the next launch or in the ARMOURY). Returns "" or
## why not.
func relocate(location_id: String, catalog: ConstructionCatalog = null) -> String:
	if location_id not in known_locations:
		return "That location is not on your map"
	var there := Location.by_id(location_id)
	if there.id == location:
		return ""
	if catalog == null:
		catalog = ConstructionCatalog.default_catalog()
	var tanks := vessel_tanks(catalog)
	var cost := jump_cost_kg(there.id, catalog)
	var paid := JumpDrive.pay(float(tanks.main_kg), float(tanks.reserve_kg), cost)
	if not paid.ok:
		var short := ServiceYard.resupply_needs(vessel, catalog)
		return "The jump to %s burns %s; the tanks hold %s and the reserve %s — refuel in the ARMOURY (%d cr)" % [
			there.station_name, JumpDrive.tonnes(cost), JumpDrive.tonnes(tanks.main_kg), JumpDrive.tonnes(tanks.reserve_kg),
			int(short.credits)]
	var stores: Dictionary = vessel.condition.get("stores", {})
	if stores.is_empty():
		var stats := ShipStats.compute(vessel.blueprint, ShipGrid.build(vessel.blueprint, catalog))
		stores = {"propellant_kg": stats.propellant_capacity_kg, "rounds": stats.rounds_capacity}
	stores["propellant_kg"] = paid.main_kg
	stores["jump_reserve_kg"] = paid.reserve_kg
	vessel.condition["stores"] = stores
	vessel.record("Jumped to %s: %s of propellant" % [there.station_name, JumpDrive.tonnes(cost)])
	location = there.id
	refresh_station(catalog)
	return ""


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


## Atomic, with a rolling backup: the new profile is written to a temporary
## file and read back; only then does the current save become the backup
## (`.bak`, the last good save) and the new file take its place. A crash at
## any point leaves a whole profile or a whole backup, never a half-written
## file.
func save(file_path: String = "") -> Error:
	var target := file_path if file_path != "" else path
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var tmp := target + ".tmp"
	var text := JSON.stringify(to_dict(), "\t", false)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(tmp) != text:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return ERR_FILE_CORRUPT
	var abs_target := ProjectSettings.globalize_path(target)
	if FileAccess.file_exists(target):
		var bak := ProjectSettings.globalize_path(target + BACKUP_SUFFIX)
		DirAccess.remove_absolute(bak)
		var err := DirAccess.rename_absolute(abs_target, bak)
		if err != OK:
			return err
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_target)


## v4 → v5: tutorial and mission-chain progress. A pilot who has flown
## already isn't offered the tutorial; the chain starts at its first goal.
static func _read_v5_progress(p: PlayerProfile, d: Dictionary) -> void:
	var t: Variant = d.get("tutorial")
	if t is Dictionary:
		p.tutorial = Tutorial.from_dict(t).to_dict()
	else:
		var veteran := p.missions_completed > 0 or p.vessels_lost > 0 or not p.vessels.is_empty()
		p.tutorial = {"state": "skipped" if veteran else "offer", "step": 0}
	var c: Variant = d.get("campaign")
	p.campaign = MissionChain.from_dict(c if c is Dictionary else {}).to_dict()


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
## profile is kept aside (never overwritten) and the backup — the save
## before it — is loaded instead; only with no usable backup does a new
## profile start. A missing profile with a whole `.tmp` beside it (a save
## cut off between its renames) is finished from that. `load_notice` says which, for the player. Loading an
## older schema first copies the file to `<path>.v<old>` (the migration
## never touches the only copy).
static func load_or_new() -> PlayerProfile:
	load_notice = ""
	var bak := path + BACKUP_SUFFIX
	if not FileAccess.file_exists(path):
		# A save interrupted between its two renames left its new file, read
		# back whole, as .tmp. (A profile deleted on purpose stays deleted.)
		var tmp := path + ".tmp"
		var finished := load_file(tmp, PackedStringArray()) if FileAccess.file_exists(tmp) else null
		if finished != null:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
			load_notice = "PROFILE RECOVERED — the last save was interrupted; it has been finished"
			GameLog.warn("profile", "%s missing; finished the interrupted save from %s" % [path, tmp])
			return finished
		return PlayerProfile.new()
	var errors := PackedStringArray()
	var p := load_file(path, errors)
	if p == null:
		var aside := path + ".unreadable"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(aside))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(aside))
		var why := "; ".join(errors)
		var backup_errors := PackedStringArray()
		var restored := load_file(bak, backup_errors) if FileAccess.file_exists(bak) else null
		if restored != null:
			load_notice = "PROFILE DAMAGED (%s) — restored the previous save from its backup; the damaged file is kept as %s" % [why, aside.get_file()]
			GameLog.warn("profile", "Could not read %s (%s); kept it as %s and restored %s" % [path, why, aside, bak])
			return restored
		load_notice = "PROFILE DAMAGED (%s) and no usable backup — started a new profile; the damaged file is kept as %s" % [why, aside.get_file()]
		GameLog.warn("profile", "Could not read %s (%s); kept it as %s and started a new profile" % [path, why, aside])
		return PlayerProfile.new()
	for e in errors:
		GameLog.warn("profile", e)
	if p.loaded_schema < SCHEMA_VERSION:
		var keep := "%s.v%d" % [path, p.loaded_schema]
		if not FileAccess.file_exists(keep):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(keep))
		GameLog.info("profile", "Profile schema %d → %d; the original is kept as %s" % [p.loaded_schema, SCHEMA_VERSION, keep])
	return p
