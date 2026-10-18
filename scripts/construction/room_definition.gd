class_name RoomDefinition
extends Resource
## Reusable room type (spec §6B, §12). A placed room is a rectangle of cells
## on one deck. Every room provides a capability or capacity; values scale
## with the room's cell count. Data lives in data/catalog/rooms/*.tres.
## Units: kg, kW (negative power = draw), rounds, m³.

@export var id: StringName
@export var display_name: String = "Room"
## Functional role, used by validation and equipment placement:
## command, access, engineering, quarters, magazine, life_support, cargo.
@export var role: StringName = &"access"
@export var mass_per_cell_kg: float = 1000.0
@export var power_kw_per_cell: float = 0.0
@export var heat_kw_per_cell: float = 0.0
@export var crew_capacity_per_cell: int = 0
@export var rounds_per_cell: int = 0
@export var cargo_m3_per_cell: float = 0.0
@export var color: Color = Color(0.4, 0.5, 0.6)


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id must be set")
	if mass_per_cell_kg < 0.0:
		problems.append("%s: mass_per_cell_kg must not be negative" % id)
	return problems
