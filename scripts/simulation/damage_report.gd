class_name DamageReport
extends RefCounted
## What one round did to a ship, in order, in plain words (spec §7: "produce
## readable feedback about what failed and why").

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


func add(text: String) -> void:
	lines.append(text)


## Short headline for HUD panels.
func headline() -> String:
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
