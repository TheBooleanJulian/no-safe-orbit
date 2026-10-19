class_name DamageReport
extends RefCounted
## What one round did to a ship, in order, in plain words (spec §7: "produce
## readable feedback about what failed and why"), plus the round's path and
## the events along it in the ship's body frame, for the hit replay.

var lines: PackedStringArray = PackedStringArray()
## The round got through at least one layer of hull armour.
var penetrated: bool = false
## Stopped by the first armour it met.
var stopped_by_armor: bool = false
var destroyed_ids: PackedStringArray = PackedStringArray()
var damaged_ids: PackedStringArray = PackedStringArray()
var breached_rooms: PackedStringArray = PackedStringArray()
var destroyed_hatches: PackedStringArray = PackedStringArray()
var wrecked_modules: PackedStringArray = PackedStringArray()
## Propellant lost with destroyed tanks (kg).
var propellant_lost_kg: float = 0.0
## Penetration on arrival and on leaving the ship (0 = it stayed inside).
var entry_pen_mm: float = 0.0
var exit_pen_mm: float = 0.0
## Where it left the hull for good (body frame), when exit_pen_mm > 0.
var exit_point_body: Vector3 = Vector3.ZERO
## Outward hull normals (body frame) where it came in and went out.
var entry_normal_body: Vector3 = Vector3.ZERO
var exit_normal_body: Vector3 = Vector3.ZERO
## Deflected by the first plate it met (Penetration.RICOCHET_MIN_DEG).
var ricochet: bool = false
var ricochet_normal_body: Vector3 = Vector3.ZERO
## Body-frame points along the round's path (first = where it reached the hull).
var path_body: PackedVector3Array = PackedVector3Array()
## [{pos: Vector3 (body), kind: StringName, id: String, text: String}] in order.
## Kinds: armor_pen, armor_stop, system_damaged, system_destroyed, breach,
## hatch, bulkhead_stop, exit, spent.
var events: Array[Dictionary] = []


func add(text: String) -> void:
	lines.append(text)


## A line of the report that also marks a point on the replay path.
func event(kind: StringName, id: String, pos: Vector3, text: String) -> void:
	lines.append(text)
	events.append({"pos": pos, "kind": kind, "id": id, "text": text})
	path_body.append(pos)


## Short headline for HUD panels.
func headline() -> String:
	if ricochet:
		return "deflected — ricochet"
	if stopped_by_armor:
		return "stopped by armour"
	var parts := PackedStringArray()
	if not destroyed_ids.is_empty():
		parts.append("%d destroyed" % destroyed_ids.size())
	if not damaged_ids.is_empty():
		parts.append("%d damaged" % damaged_ids.size())
	if not breached_rooms.is_empty():
		parts.append("%d breached" % breached_rooms.size())
	if parts.is_empty():
		return "penetrated, no system hit" if penetrated else "glancing hit"
	return ", ".join(parts)


## Severity for choosing which hit to replay: destroyed > damaged > breach >
## penetration > stopped.
func severity() -> int:
	if not destroyed_ids.is_empty():
		return 4
	if not damaged_ids.is_empty():
		return 3
	if not breached_rooms.is_empty():
		return 2
	return 1 if penetrated else 0
