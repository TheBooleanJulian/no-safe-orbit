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
## Ammunition stowage (kg per cell): shared by every gun type aboard by
## mount count, so each calibre gets (its share ÷ its round mass) rounds.
@export var ammo_kg_per_cell: float = 0.0
@export var cargo_m3_per_cell: float = 0.0
@export var color: Color = Color(0.4, 0.5, 0.6)
@export_group("Progression")
## COMMON parts are always available; rarer ones must be found as loot.
@export var rarity: Rarity.Tier = Rarity.Tier.COMMON
## Relative chance of this part among loot drops of the same rarity.
@export var drop_weight: float = 10.0


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id must be set")
	if drop_weight < 0.0:
		problems.append("%s: drop_weight must not be negative" % id)
	if mass_per_cell_kg < 0.0:
		problems.append("%s: mass_per_cell_kg must not be negative" % id)
	return problems
