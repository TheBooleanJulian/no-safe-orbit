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
	return false


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
	v.sorties = int(d.get("sorties", 0))
	v.salvaged = int(d.get("salvaged", 0))
	for line in d.get("history", []):
		v.history.append(str(line))
	return v
