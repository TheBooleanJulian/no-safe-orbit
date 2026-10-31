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
## Rooms of the same type side by side on a deck are one space: no hatch
## between them is needed. Room index -> the indices it opens into.
var open_rooms: Dictionary = {}
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
	for cell: Vector3i in g.room_at:
		var ra: int = g.room_at[cell]
		for d in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
			var rb: int = g.room_at.get(cell + d, -1)
			if rb >= 0 and rb != ra and p_blueprint.rooms[ra].def_id == p_blueprint.rooms[rb].def_id:
				if not (g.open_rooms.get_or_add(ra, []) as Array).has(rb):
					g.open_rooms[ra].append(rb)
					g.open_rooms.get_or_add(rb, []).append(ra)
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


## Float version of rotate_dir.
static func rotate_vec(v: Vector3, quarter_turns: int) -> Vector3:
	for i in posmod(quarter_turns, 4):
		v = Vector3(v.z, v.y, -v.x)
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


func is_wedge(index: int) -> bool:
	var def := module_def(index)
	return def != null and def.is_wedge()


## Whether a cell belongs to a sloped (wedge) module.
func is_wedge_cell(cell: Vector3i) -> bool:
	return module_at.has(cell) and is_wedge(module_at[cell])


## Outward unit normal of a wedge's slope, grid frame.
func wedge_normal(index: int) -> Vector3:
	var m := blueprint.modules[index]
	var s := module_def(index).size_cells
	var n := Vector3(0, -s.z if m.flip else s.z, -s.y).normalized()
	return rotate_vec(n, m.rotation)


## Whether a point (grid cell units, i.e. metres / CELL_SIZE_M) lies in the
## solid part of wedge `index` (it must be inside the module's box).
func wedge_contains(index: int, p: Vector3) -> bool:
	var m := blueprint.modules[index]
	var s := Vector3(module_def(index).size_cells)
	var rs := Vector3(module_size(index))
	# Into the module's own frame: centre, undo the turn, back to its corner.
	var local := rotate_vec(p - (Vector3(m.position) + rs * 0.5), -m.rotation) + s * 0.5
	var height := local.y / s.y
	if m.flip:
		height = 1.0 - height
	return height <= local.z / s.z + 1e-6


## The two grid faces of a wedge cell that its slope replaces (its own fore
## face and its top — bottom when flipped). Systems cannot mount there.
## Where internal craft bay `index` opens: [cell, face] of the first outside
## wall, floor or roof (not a slope) among its cells and its room's — the
## underside first; [] if it is shut in.
static func door_face(bp: ShipBlueprint, grid: ShipGrid, index: int) -> Array:
	var cells: Array = grid.equipment_cells(index)
	var r: int = grid.room_at.get(bp.equipment[index].cell, -1)
	if r >= 0:
		for c in room_cells(bp.rooms[r]):
			if not cells.has(c):
				cells.append(c)
	for face: StringName in [&"ventral", &"port", &"starboard", &"dorsal", &"aft", &"fore"]:
		for c: Vector3i in cells:
			if grid.is_exterior_face(c, face) and not grid.slope_faces(c).has(face):
				return [c, face]
	return []


func slope_faces(cell: Vector3i) -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_wedge_cell(cell):
		return out
	var m := blueprint.modules[module_at[cell]]
	out.append(face_of(rotate_dir(Vector3i(0, 0, -1), m.rotation)))
	out.append(&"ventral" if m.flip else &"dorsal")
	return out


## The face key a wedge cell's slope plate is stored under (its top, or
## bottom when flipped); a box cell's plates use their own faces.
func plate_face(cell: Vector3i, face: StringName) -> StringName:
	var slopes := slope_faces(cell)
	return slopes[1] if slopes.has(face) else face


## Faces of `cell` that can carry an armour plate: exterior faces, with a
## wedge's slope counted once (under plate_face).
func plateable_faces(cell: Vector3i) -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_hull(cell):
		return out
	for face: StringName in FACE_NORMALS:
		if not is_exterior_face(cell, face):
			continue
		var f := plate_face(cell, face)
		if not out.has(f):
			out.append(f)
	return out


## Plate area factor: a slope plate is larger than the cell face it stands
## for (hypotenuse over run).
func plate_area_factor(cell: Vector3i, face: StringName) -> float:
	if not is_wedge_cell(cell) or not slope_faces(cell).has(face):
		return 1.0
	var s := module_def(module_at[cell]).size_cells
	return sqrt(float(s.z * s.z + s.y * s.y)) / float(s.z)


## Connector type of a module on a face given in grid (ship) orientation.
func module_connector(index: int, grid_face: StringName) -> StringName:
	var m := blueprint.modules[index]
	# Undo the module's rotation to find the face in its own frame.
	var local_normal := rotate_dir(FACE_NORMALS[grid_face], -m.rotation)
	return module_def(index).connector(face_of(local_normal))


func equipment_def(index: int) -> EquipmentDefinition:
	return catalog.equipment.get(blueprint.equipment[index].def_id)


## Internal footprint in cells (x, z) after the equipment's rotation.
func equipment_footprint(index: int) -> Vector2i:
	var def := equipment_def(index)
	if def == null:
		return Vector2i.ONE
	var fp := def.footprint_cells
	return Vector2i(fp.y, fp.x) if posmod(blueprint.equipment[index].rotation, 2) == 1 else fp


func equipment_cells(index: int) -> Array[Vector3i]:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	var cells: Array[Vector3i] = []
	if def == null or def.is_external():
		return cells
	var fp := equipment_footprint(index)
	for x in fp.x:
		for z in fp.y:
			cells.append(e.cell + Vector3i(x, 0, z))
	return cells


## A long radiator's rotation that stands it straight out from the face as
## a fin (play-test batch 9): one hull cell, its length outwards. 0–3 lie
## along or across the hull as before (rotation mod 2).
const FIN_ROTATION := 4


static func is_fin(def: EquipmentDefinition, rotation: int) -> bool:
	return rotation == FIN_ROTATION and def != null and def.kind == EquipmentDefinition.Kind.RADIATOR and def.length_cells > 1


## The space a fin stands in: the cells straight out from its face.
func fin_cells(index: int) -> Array[Vector3i]:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	var out: Array[Vector3i] = []
	if not is_fin(def, e.rotation):
		return out
	var n: Vector3i = FACE_NORMALS.get(e.face, Vector3i.ZERO)
	for k in range(1, def.length_cells + 1):
		out.append(e.cell + n * k)
	return out


## Step from one cell of a long external system to the next: aft, or
## (turned) across the ship; never along the face normal (then sideways or up).
static func external_step(face: StringName, rotation: int) -> Vector3i:
	var n: Vector3i = FACE_NORMALS.get(face, Vector3i.ZERO)
	if posmod(rotation, 2) == 0:
		return Vector3i(1, 0, 0) if n.z != 0 else Vector3i(0, 0, 1)
	return Vector3i(0, 1, 0) if n.x != 0 else Vector3i(1, 0, 0)


## The two directions across `face` a sized part's patch grows in from its
## cell (always the positive axes).
static func face_tangents(face: StringName) -> Array[Vector3i]:
	var n: Vector3i = FACE_NORMALS.get(face, Vector3i.ZERO)
	if n.x != 0:
		return [Vector3i(0, 0, 1), Vector3i(0, 1, 0)]
	if n.y != 0:
		return [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]
	return [Vector3i(1, 0, 0), Vector3i(0, 1, 0)]


## The hull cells a part of tier `size` covers on `face` from `cell`.
static func patch(cell: Vector3i, face: StringName, size: int) -> Array[Vector3i]:
	var t := face_tangents(face)
	var out: Array[Vector3i] = []
	for a in maxi(size, 1):
		for b in maxi(size, 1):
			out.append(cell + t[0] * a + t[1] * b)
	return out


## The space a part of tier `size` stands in off `face` (`out` cells — its
## size unless it stands taller — from every cell of its patch): it must be
## clear of hull.
static func standing(cell: Vector3i, face: StringName, size: int, out_cells: int = 0) -> Array[Vector3i]:
	var n: Vector3i = FACE_NORMALS.get(face, Vector3i.ZERO)
	var out: Array[Vector3i] = []
	for c in patch(cell, face, size):
		for k in range(1, maxi(maxi(size, out_cells), 1) + 1):
			out.append(c + n * k)
	return out


## The space external system `index` stands in (empty for a fin, which
## has fin_cells, and for internal equipment).
func standing_cells(index: int) -> Array[Vector3i]:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	if def == null or not def.is_external() or is_fin(def, e.rotation):
		return []
	return standing(e.cell, e.face, def.size_cells, def.stands_out())


## Whether `def` fits on `face` at `cell`: its whole patch exterior, flat
## hull faces none of which `taken` ("cell|face" -> true) holds, and the
## space it stands in clear of hull.
func can_mount(def: EquipmentDefinition, cell: Vector3i, face: StringName, taken: Dictionary = {}) -> bool:
	if not def.allowed_faces.has(face):
		return false
	for c in patch(cell, face, def.size_cells):
		if not is_exterior_face(c, face) or slope_faces(c).has(face) or taken.has("%s|%s" % [c, face]):
			return false
	for c in standing(cell, face, def.size_cells, def.stands_out()):
		if is_hull(c):
			return false
	return true


## Hull cells an external system's face spans (one for most systems; its
## tier's N × N patch for a sized one).
func external_cells(index: int) -> Array[Vector3i]:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	var out: Array[Vector3i] = [e.cell]
	if def == null or is_fin(def, e.rotation):
		return out
	if def.size_cells > 1:
		return patch(e.cell, e.face, def.size_cells)
	var step := external_step(e.face, e.rotation)
	for k in range(1, maxi(def.length_cells, 1)):
		out.append(e.cell + step * k)
	return out


## Where equipment sits, in grid metres: footprint centre (internal) or the
## centre of the hull face it is mounted on (external; the middle of the
## span for a long one).
func equipment_position_m(index: int) -> Vector3:
	var e := blueprint.equipment[index]
	var def := equipment_def(index)
	if def != null and def.is_external():
		var cells := external_cells(index)
		var mid := Vector3.ZERO
		for c in cells:
			mid += cell_center_m(c)
		return mid / cells.size() + Vector3(FACE_NORMALS.get(e.face, Vector3i.ZERO)) * CELL_SIZE_M * 0.5
	var fp := equipment_footprint(index)
	return (Vector3(e.cell) + Vector3(fp.x, 1, fp.y) * 0.5) * CELL_SIZE_M


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


## Structural attachments: for each module index, the modules it shares at
## least one face with (any common face welds them together; connector
## types are descriptive only).
func attachments() -> Array[Array]:
	var n := blueprint.modules.size()
	var attached: Array[Array] = []
	for i in n:
		attached.append([])
	for i in n:
		if module_def(i) == null:
			continue
		for cell in module_cells(i):
			for face: StringName in FACE_NORMALS:
				var other: int = module_at.get(cell + FACE_NORMALS[face], -1)
				if other >= 0 and other != i and not attached[i].has(other):
					attached[i].append(other)
	return attached


## Hatch id between two neighbouring cells, or "".
func hatch_between(a: Vector3i, b: Vector3i) -> String:
	for h in blueprint.hatches:
		if (h.a == a and h.b == b) or (h.a == b and h.b == a):
			return h.id
	return ""


## Cells a ray passes through (Amanatides–Woo voxel traversal), in grid cell
## units: `start` and the result positions are in cells, `dir` is a unit
## vector, `max_cells` the length to walk. Each step is
## {cell: Vector3i, t: float (cells from start), normal: Vector3i (face of
## the previous cell crossed into this one; ZERO for the first)}.
static func traverse(start: Vector3, dir: Vector3, max_cells: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell := Vector3i(floori(start.x), floori(start.y), floori(start.z))
	var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z))))
	var t_next := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if absf(dir[axis]) > 1e-9:
			t_delta[axis] = 1.0 / absf(dir[axis])
			var boundary := float(cell[axis] + (1 if step[axis] > 0 else 0))
			t_next[axis] = (boundary - start[axis]) / dir[axis]
	out.append({"cell": cell, "t": 0.0, "normal": Vector3i.ZERO})
	for i in 512:
		var axis := 0
		if t_next.y < t_next[axis]:
			axis = 1
		if t_next.z < t_next[axis]:
			axis = 2
		var t := t_next[axis]
		if t > max_cells:
			break
		var normal := Vector3i.ZERO
		normal[axis] = step[axis]
		cell += normal
		t_next[axis] += t_delta[axis]
		out.append({"cell": cell, "t": t, "normal": normal})
	return out


## Faces of a module's cells open to space (its radiating surface).
func exterior_face_count(index: int) -> int:
	var n := 0
	for cell in module_cells(index):
		for face: StringName in FACE_NORMALS:
			if not is_hull(cell + FACE_NORMALS[face]):
				n += 1
	return n


## Range of occupied decks / x / z across the hull (for editor views).
func cell_bounds() -> AABB:
	var b := hull_bounds_m()
	return AABB(b.position / CELL_SIZE_M, b.size / CELL_SIZE_M)
