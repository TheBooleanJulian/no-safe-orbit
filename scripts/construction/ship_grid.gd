class_name ShipGrid
extends RefCounted
## Cell occupancy derived from a ShipBlueprint: which module, room and
## internal equipment occupies each cell. Rebuilt whenever the design
## changes; the validator, stats and editor views all query it.
## Overlaps and unknown definitions are recorded, not resolved.

## Edge length of one cell and the height of one deck (m).
const CELL_SIZE_M := 3.0

## Unit normals of the six faces, body/grid frame.
const FACE_NORMALS := {
	&"fore": Vector3i(0, 0, -1),
	&"aft": Vector3i(0, 0, 1),
	&"port": Vector3i(-1, 0, 0),
	&"starboard": Vector3i(1, 0, 0),
	&"dorsal": Vector3i(0, 1, 0),
	&"ventral": Vector3i(0, -1, 0),
}

var blueprint: ShipBlueprint
var catalog: ConstructionCatalog
var module_at: Dictionary = {}     # Vector3i -> module index
var room_at: Dictionary = {}       # Vector3i -> room index
var equipment_at: Dictionary = {}  # Vector3i -> equipment index (internal only)
## [cell, first index, second index] for each double-booked cell.
var module_overlaps: Array = []
var room_overlaps: Array = []
var equipment_overlaps: Array = []
## Human-readable problems such as unknown definition ids.
var unknown: PackedStringArray = PackedStringArray()


static func build(p_blueprint: ShipBlueprint, p_catalog: ConstructionCatalog) -> ShipGrid:
	var g := ShipGrid.new()
	g.blueprint = p_blueprint
	g.catalog = p_catalog
	for i in p_blueprint.modules.size():
		var m := p_blueprint.modules[i]
		if not p_catalog.hull.has(m.def_id):
			g.unknown.append("Module %s: unknown hull module '%s'" % [m.id, m.def_id])
			continue
		for cell in g.module_cells(i):
			if g.module_at.has(cell):
				g.module_overlaps.append([cell, g.module_at[cell], i])
			else:
				g.module_at[cell] = i
	for i in p_blueprint.rooms.size():
		var r := p_blueprint.rooms[i]
		if not p_catalog.rooms.has(r.def_id):
			g.unknown.append("Room %s: unknown room type '%s'" % [r.id, r.def_id])
			continue
		for cell in room_cells(r):
			if g.room_at.has(cell):
				g.room_overlaps.append([cell, g.room_at[cell], i])
			else:
				g.room_at[cell] = i
	for i in p_blueprint.equipment.size():
		var e := p_blueprint.equipment[i]
		var def: EquipmentDefinition = p_catalog.equipment.get(e.def_id)
		if def == null:
			g.unknown.append("Equipment %s: unknown equipment '%s'" % [e.id, e.def_id])
			continue
		if def.is_external():
			continue
		for cell in g.equipment_cells(i):
			if g.equipment_at.has(cell):
				g.equipment_overlaps.append([cell, g.equipment_at[cell], i])
			else:
				g.equipment_at[cell] = i
	return g


## Rotates a grid direction by quarter turns about +Y (counter-clockwise
## seen from above: fore → port → aft → starboard).
static func rotate_dir(v: Vector3i, quarter_turns: int) -> Vector3i:
	for i in posmod(quarter_turns, 4):
		v = Vector3i(v.z, v.y, -v.x)
	return v


static func face_of(normal: Vector3i) -> StringName:
	for face in FACE_NORMALS:
		if FACE_NORMALS[face] == normal:
			return face
	return &""


## Size in cells of a module after rotation.
static func rotated_size(size: Vector3i, quarter_turns: int) -> Vector3i:
	return Vector3i(size.z, size.y, size.x) if posmod(quarter_turns, 2) == 1 else size


static func room_cells(r: ShipBlueprint.PlacedRoom) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x in range(r.rect.position.x, r.rect.end.x):
		for z in range(r.rect.position.y, r.rect.end.y):
			cells.append(Vector3i(x, r.deck, z))
	return cells


## Centre of a cell in grid metres (grid origin at the corner of cell 0,0,0).
static func cell_center_m(cell: Vector3i) -> Vector3:
	return (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * CELL_SIZE_M


func module_def(index: int) -> HullModuleDefinition:
	return catalog.hull.get(blueprint.modules[index].def_id)


func module_size(index: int) -> Vector3i:
	var m := blueprint.modules[index]
	return rotated_size(module_def(index).size_cells, m.rotation)


func module_cells(index: int) -> Array[Vector3i]:
	var m := blueprint.modules[index]
	var size := module_size(index)
	var cells: Array[Vector3i] = []
	for x in size.x:
		for y in size.y:
			for z in size.z:
				cells.append(m.position + Vector3i(x, y, z))
	return cells


## Connector type of a module on a face given in grid (ship) orientation.
func module_connector(index: int, grid_face: StringName) -> StringName:
	var m := blueprint.modules[index]
	# Undo the module's rotation to find the face in its own frame.
	var local_normal := rotate_dir(FACE_NORMALS[grid_face], -m.rotation)
	return module_def(index).connector(face_of(local_normal))


func equipment_def(index: int) -> EquipmentDefinition:
	return catalog.equipment.get(blueprint.equipment[index].def_id)


func equipment_cells(index: int) -> Array[Vector3i]:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	var cells: Array[Vector3i] = []
	if def == null or def.is_external():
		return cells
	for x in def.footprint_cells.x:
		for z in def.footprint_cells.y:
			cells.append(e.cell + Vector3i(x, 0, z))
	return cells


## Where equipment sits, in grid metres: footprint centre (internal) or the
## centre of the hull face it is mounted on (external).
func equipment_position_m(index: int) -> Vector3:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	if def != null and def.is_external():
		return cell_center_m(e.cell) + Vector3(FACE_NORMALS.get(e.face, Vector3i.ZERO)) * CELL_SIZE_M * 0.5
	var size := Vector3(def.footprint_cells.x, 1, def.footprint_cells.y) if def != null else Vector3.ONE
	return (Vector3(e.cell) + size * 0.5) * CELL_SIZE_M


func is_hull(cell: Vector3i) -> bool:
	return module_at.has(cell)


func is_interior(cell: Vector3i) -> bool:
	return module_at.has(cell) and module_def(module_at[cell]).interior


## A hull cell's face is exterior when the neighbouring cell is not hull.
func is_exterior_face(cell: Vector3i, face: StringName) -> bool:
	return is_hull(cell) and FACE_NORMALS.has(face) and not is_hull(cell + FACE_NORMALS[face])


## Axis-aligned bounds of all hull cells in grid metres (empty if no hull).
func hull_bounds_m() -> AABB:
	var first := true
	var box := AABB()
	for cell: Vector3i in module_at:
		var cell_box := AABB(Vector3(cell) * CELL_SIZE_M, Vector3.ONE * CELL_SIZE_M)
		box = cell_box if first else box.merge(cell_box)
		first = false
	return box


## Range of occupied decks / x / z across the hull (for editor views).
func cell_bounds() -> AABB:
	var b := hull_bounds_m()
	return AABB(b.position / CELL_SIZE_M, b.size / CELL_SIZE_M)
