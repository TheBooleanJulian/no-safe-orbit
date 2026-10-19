class_name ShipInstance
extends RefCounted
## One physical vessel (spec §2 "Core data boundaries", §13 "Persistence"):
## the design it was built to plus its own condition and history. The
## blueprint is a copy: editing a saved design never changes a vessel until
## it is refitted at the yard.

const HISTORY_LIMIT := 50

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
	for key in ["equipment", "modules", "breached", "hatches", "crew"]:
		var part: Variant = condition.get(key, [])
		if not part.is_empty():
			return true
	return not wing.is_empty()


func cargo_is_empty() -> bool:
	return int(cargo.get("spare_parts", 0)) == 0 and (cargo.get("equipment", {}) as Dictionary).is_empty() \
		and (cargo.get("blueprints", {}) as Dictionary).is_empty()


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
	var wg: Variant = d.get("wing", {})
	v.wing = (wg as Dictionary).duplicate(true) if wg is Dictionary else {}
	var cg: Variant = d.get("cargo", {})
	v.cargo = (cg as Dictionary).duplicate(true) if cg is Dictionary else {}
	v.sorties = int(d.get("sorties", 0))
	v.salvaged = int(d.get("salvaged", 0))
	for line in d.get("history", []):
		v.history.append(str(line))
	return v
