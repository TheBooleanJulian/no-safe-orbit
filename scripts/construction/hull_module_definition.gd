class_name HullModuleDefinition
extends Resource
## Reusable hull section (spec §6A): an axis-aligned box of grid cells with
## structural connectors on its faces. Placed and rotated (90° steps about +Y)
## by ShipBlueprint. Data lives in data/catalog/hull/*.tres.
## Units: cells (ShipGrid.CELL_SIZE_M), kg, mm.

@export var id: StringName
@export var display_name: String = "Hull module"
## Size in cells: x = width (port→starboard), y = decks, z = length (fore→aft).
@export var size_cells: Vector3i = Vector3i(4, 2, 4)
@export var structure_mass_kg: float = 40_000.0
## Connector type per face in the module's own frame, e.g. {"aft": "spine"}.
## Faces: fore, aft, port, starboard, dorsal, ventral. Missing = no connector.
## Two touching modules attach where facing connectors match.
@export var connectors: Dictionary = {}
## Pressurised interior: rooms may only be placed in interior cells.
@export var interior: bool = true
## Outer armour thickness (used by the damage model from Milestone 3).
@export var armor_mm: float = 20.0
@export var color: Color = Color(0.55, 0.6, 0.66)


func connector(face: StringName) -> StringName:
	return StringName(connectors.get(String(face), ""))


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id must be set")
	if size_cells.x <= 0 or size_cells.y <= 0 or size_cells.z <= 0:
		problems.append("%s: size_cells must be positive" % id)
	if structure_mass_kg <= 0.0:
		problems.append("%s: structure_mass_kg must be positive" % id)
	for face in connectors:
		if not ShipGrid.FACE_NORMALS.has(StringName(face)):
			problems.append("%s: unknown connector face '%s'" % [id, face])
	return problems
