class_name ShipInstance
extends RefCounted
## One physical vessel (spec §2 "Core data boundaries", §13 "Persistence"):
## the design it was built to plus its own condition and history. The
## blueprint is a copy: editing a saved design never changes a vessel until
## it is refitted at the yard.

const HISTORY_LIMIT := 50
## Cargo volumes (m³): a spare part, a blueprint data core; equipment by
## mass (see equipment_m3).
const SPARE_PART_M3 := 0.25
const BLUEPRINT_M3 := 0.1

var name: String = ""
var blueprint: ShipBlueprint
## ShipSystems.condition(): damage keyed by stable part ids ({} = like new).
var condition: Dictionary = {}
## Cargo hold contents, at risk until banked: {spare_parts: int,
## equipment: {id: units}, blueprints: {id: [kind, rarity, count]}}.
var cargo: Dictionary = {}
## Craft not like new, by rack id: {"hull": fraction, "lost": bool}.
var wing: Dictionary = {}
var sorties: int = 0
var salvaged: int = 0
## Service record, newest last.
var history: PackedStringArray = PackedStringArray()
## Hired crew, one per berth: [{name, role (CrewRoster.Role), skill,
## sorties served}].
## Empty = the standard (unnamed) complement — older saves until named.
var crew: Array = []
## The vessel's automation (ShipPolicy.to_dict()); set in Tab › POLICY.
var policy: Dictionary = ShipPolicy.preset("Defensive").to_dict()


## Name the standard complement once (older saves, new vessels): the same
## people, now with names, so they can be managed and replaced one by one.
func ensure_crew(catalog: ConstructionCatalog) -> void:
	if not crew.is_empty():
		return
	var grid := ShipGrid.build(blueprint, catalog)
	var roster := CrewRoster.default_for(blueprint, grid, ShipStats.compute(blueprint, grid))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	for m in roster.members:
		crew.append({"name": CrewNames.pick(rng), "role": m.role, "skill": 0})


## Docked: the dead leave the roster (their berths are free to hire into);
## the condition then carries no dead to recruit. Returns their names.
func bury_dead() -> PackedStringArray:
	var out := PackedStringArray()
	var c: Dictionary = condition.get("crew", {})
	var dead: Dictionary = c.get("dead", {})
	if crew.is_empty() or dead.is_empty():
		return out
	for role_name in dead:
		var role := CrewRoster.ROLE_NAMES.find(str(role_name))
		var left := int(dead[role_name])
		# Casualties fall on the first of each role (CrewRoster.apply_casualties).
		var i := 0
		while left > 0 and i < crew.size():
			if int(crew[i].role) == role:
				out.append(str(crew[i].name))
				crew.remove_at(i)
				left -= 1
			else:
				i += 1
	c.erase("dead")
	if c.is_empty():
		condition.erase("crew")
	return out


static func fresh(bp: ShipBlueprint) -> ShipInstance:
	var v := ShipInstance.new()
	v.blueprint = bp.duplicate_blueprint()
	v.name = bp.name
	v.condition = {}
	return v


func record(line: String) -> void:
	history.append(line)
	if history.size() > HISTORY_LIMIT:
		history.remove_at(0)


func is_damaged() -> bool:
	for key in ["equipment", "modules", "breached", "hatches", "crew", "plates"]:
		var part: Variant = condition.get(key, [])
		if not part.is_empty():
			return true
	return not wing.is_empty()


func cargo_is_empty() -> bool:
	return int(cargo.get("spare_parts", 0)) == 0 and (cargo.get("equipment", {}) as Dictionary).is_empty() \
		and (cargo.get("blueprints", {}) as Dictionary).is_empty()


## Crated volume of one unit of equipment (m³).
static func equipment_m3(def: EquipmentDefinition) -> float:
	return maxf(1.0, def.mass_kg / 2000.0) if def != null else 1.0


## Volume the hold's contents take up (m³).
func cargo_volume_m3(catalog: ConstructionCatalog) -> float:
	var v := int(cargo.get("spare_parts", 0)) * SPARE_PART_M3
	for id in cargo.get("equipment", {}):
		v += equipment_m3(catalog.equipment.get(StringName(id))) * int(cargo.equipment[id])
	for id in cargo.get("blueprints", {}):
		v += BLUEPRINT_M3 * int((cargo.blueprints[id] as Array)[2])
	v += float(cargo.get("freight", {}).get("m3", 0))
	return v


## Each line of the hold: {kind, id, units, m3}, cheapest to lose first
## (spare parts, then equipment by rarity, then blueprints, then a cargo
## contract's freight — jettisoning that fails the contract).
func cargo_lines(catalog: ConstructionCatalog) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parts := int(cargo.get("spare_parts", 0))
	if parts > 0:
		out.append({"kind": "spare_parts", "id": "spare_parts", "name": "Spare parts", "units": parts, "m3": parts * SPARE_PART_M3, "rarity": -1})
	var eq: Array[Dictionary] = []
	for id in cargo.get("equipment", {}):
		var def: EquipmentDefinition = catalog.equipment.get(StringName(id))
		var units := int(cargo.equipment[id])
		eq.append({"kind": "equipment", "id": str(id), "name": def.display_name if def != null else str(id), "units": units,
			"m3": equipment_m3(def) * units, "rarity": def.rarity if def != null else 0})
	eq.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rarity < b.rarity)
	out.append_array(eq)
	for id in cargo.get("blueprints", {}):
		var entry: Array = cargo.blueprints[id]
		out.append({"kind": "blueprints", "id": str(id), "name": "%s blueprint" % id, "units": int(entry[2]), "m3": BLUEPRINT_M3 * int(entry[2]), "rarity": int(entry[1])})
	var freight: Dictionary = cargo.get("freight", {})
	if not freight.is_empty():
		out.append({"kind": "freight", "id": "freight", "name": "Contract freight: %s" % freight.what, "units": 1, "m3": float(freight.m3), "rarity": 99})
	return out


## Jettison one whole line of the hold. Returns what went.
func vent(kind: String, id: String) -> String:
	match kind:
		"spare_parts":
			var n := int(cargo.get("spare_parts", 0))
			cargo.erase("spare_parts")
			return "%d spare parts" % n if n > 0 else ""
		"equipment", "blueprints":
			var table: Dictionary = cargo.get(kind, {})
			if not table.has(id):
				return ""
			table.erase(id)
			if table.is_empty():
				cargo.erase(kind)
			return "%s %s" % [id, "blueprint" if kind == "blueprints" else "(all units)"]
		"freight":
			var f: Dictionary = cargo.get("freight", {})
			cargo.erase("freight")
			return "%d m³ of contract freight (%s)" % [int(f.m3), f.what] if not f.is_empty() else ""
	return ""


## Jettison the cheapest cargo until it fits in `capacity_m3`: spare parts
## first (only as many as needed), then equipment one unit at a time by
## rarity, then blueprints. Returns what went.
func vent_excess(capacity_m3: float, catalog: ConstructionCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	var over := cargo_volume_m3(catalog) - capacity_m3
	if over <= 1e-6:
		return out
	var parts := int(cargo.get("spare_parts", 0))
	if parts > 0:
		var n := mini(parts, ceili(over / SPARE_PART_M3 - 1e-6))
		cargo["spare_parts"] = parts - n
		if parts - n == 0:
			cargo.erase("spare_parts")
		out.append("%d spare parts" % n)
		over -= n * SPARE_PART_M3
	for line in cargo_lines(catalog):
		if over <= 1e-6:
			break
		if line.kind != "equipment":
			continue
		var eq: Dictionary = cargo.equipment
		while over > 1e-6 and int(eq.get(line.id, 0)) > 0:
			eq[line.id] = int(eq[line.id]) - 1
			over -= line.m3 / line.units
			out.append("%s ×1" % line.name)
		if int(eq.get(line.id, 0)) <= 0:
			eq.erase(line.id)
	if cargo.has("equipment") and (cargo.equipment as Dictionary).is_empty():
		cargo.erase("equipment")
	while over > 1e-6 and cargo.has("blueprints") and not (cargo.blueprints as Dictionary).is_empty():
		var id: String = (cargo.blueprints as Dictionary).keys()[0]
		over -= BLUEPRINT_M3 * int((cargo.blueprints[id] as Array)[2])
		out.append(vent("blueprints", id))
	return out


## One line: what is in the hold.
func cargo_summary() -> String:
	if cargo_is_empty():
		return "empty"
	var parts := PackedStringArray()
	if int(cargo.get("spare_parts", 0)) > 0:
		parts.append("%d spare parts" % int(cargo.spare_parts))
	for id in cargo.get("equipment", {}):
		parts.append("%s ×%d" % [id, int(cargo.equipment[id])])
	for id in cargo.get("blueprints", {}):
		parts.append("%s blueprint" % id)
	return ", ".join(parts)


## Crew killed, by role name ({} = full complement).
func dead_crew() -> Dictionary:
	return condition.get("crew", {}).get("dead", {})


## Condition of equipment `id` as a hit-point fraction (1 = like new).
func equipment_fraction(id: String) -> float:
	return float(condition.get("equipment", {}).get(id, 1.0))


func to_dict() -> Dictionary:
	return {
		"name": name,
		"blueprint": blueprint.to_dict(),
		"condition": condition.duplicate(true),
		"cargo": cargo.duplicate(true),
		"wing": wing.duplicate(true),
		"sorties": sorties,
		"salvaged": salvaged,
		"history": Array(history),
		"crew": crew.duplicate(true),
		"policy": policy.duplicate(true),
	}


static func from_dict(d: Dictionary, errors: PackedStringArray) -> ShipInstance:
	if not d.get("blueprint") is Dictionary:
		errors.append("Vessel has no blueprint")
		return null
	var bp := ShipBlueprint.from_dict(d.blueprint, errors)
	if bp == null:
		return null
	var v := ShipInstance.new()
	v.blueprint = bp
	v.name = str(d.get("name", bp.name))
	var c: Variant = d.get("condition", {})
	v.condition = (c as Dictionary).duplicate(true) if c is Dictionary else {}
	# JSON reads every number back as a float: crew counts are whole people.
	var crew: Variant = v.condition.get("crew", {})
	if crew is Dictionary:
		for kind in crew:
			if crew[kind] is Dictionary:
				for role in crew[kind]:
					crew[kind][role] = int(crew[kind][role])
	var wg: Variant = d.get("wing", {})
	v.wing = (wg as Dictionary).duplicate(true) if wg is Dictionary else {}
	var cg: Variant = d.get("cargo", {})
	v.cargo = (cg as Dictionary).duplicate(true) if cg is Dictionary else {}
	v.sorties = int(d.get("sorties", 0))
	v.salvaged = int(d.get("salvaged", 0))
	for entry in d.get("crew", []):
		if entry is Dictionary:
			v.crew.append({"name": str(entry.get("name", "")), "role": int(entry.get("role", 6)), "skill": int(entry.get("skill", 0)),
				"sorties": int(entry.get("sorties", 0))})
	for line in d.get("history", []):
		v.history.append(str(line))
	# Before schema 6 there was none: the Defensive preset (point defence on,
	# no automatic fire) — what those ships already did.
	var pol: Variant = d.get("policy", {})
	v.policy = ShipPolicy.from_dict(pol if pol is Dictionary else {}).to_dict()
	return v
