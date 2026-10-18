class_name ShipEditor
extends RefCounted
## Editing operations on a blueprint, independent of any UI so they can be
## tested headless. After every successful edit the grid, stats and
## validation report are re-derived from the blueprint, and `revision` bumps.
## Every edit can be undone and redone (snapshot history).

signal changed

const HISTORY_LIMIT := 200

var blueprint: ShipBlueprint
var catalog: ConstructionCatalog
var grid: ShipGrid
var stats: ShipStats
var report: ShipValidator.Report
var revision: int = 0

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func _init(p_blueprint: ShipBlueprint, p_catalog: ConstructionCatalog) -> void:
	catalog = p_catalog
	set_blueprint(p_blueprint)


## Replace the design (load / template). Clears the undo history.
func set_blueprint(bp: ShipBlueprint) -> void:
	blueprint = bp
	_undo.clear()
	_redo.clear()
	_refresh()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(blueprint.to_dict())
	_restore(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(blueprint.to_dict())
	_restore(_redo.pop_back())
	return true


func place_module(def_id: StringName, base_cell: Vector3i, rotation: int) -> String:
	_checkpoint()
	var m := blueprint.add_module(def_id, base_cell, rotation)
	_refresh()
	return m.id


func place_room(def_id: StringName, deck: int, rect: Rect2i) -> String:
	_checkpoint()
	var r := blueprint.add_room(def_id, deck, rect.abs())
	_refresh()
	return r.id


func place_equipment(def_id: StringName, cell: Vector3i, face: StringName = &"", rotation: int = 0) -> String:
	_checkpoint()
	var def: EquipmentDefinition = catalog.equipment.get(def_id)
	var external := def != null and def.is_external()
	var e := blueprint.add_equipment(def_id, cell, face if external else &"", 0 if external else rotation)
	_refresh()
	return e.id


## Adds a hatch between two cells, or removes the one already there.
## Returns true if a hatch now exists.
func toggle_hatch(a: Vector3i, b: Vector3i) -> bool:
	_checkpoint()
	for h in blueprint.hatches:
		if (h.a == a and h.b == b) or (h.a == b and h.b == a):
			blueprint.remove(h.id)
			_refresh()
			return false
	blueprint.add_hatch(a, b)
	_refresh()
	return true


func remove(id: String) -> bool:
	if blueprint.find(id) == null:
		return false
	_checkpoint()
	blueprint.remove(id)
	_refresh()
	return true


## Moves a part by whole cells (deck = y). A module carries everything that
## lies entirely inside it: rooms, equipment and hatches.
func move(id: String, delta: Vector3i) -> bool:
	var item: Variant = blueprint.find(id)
	if item == null:
		return false
	_checkpoint()
	if item is ShipBlueprint.PlacedModule:
		var contents := _contents_of(item)
		item.position += delta
		for room: ShipBlueprint.PlacedRoom in contents.rooms:
			_shift_room(room, delta)
		for e: ShipBlueprint.PlacedEquipment in contents.equipment:
			e.cell += delta
		for h: ShipBlueprint.Hatch in contents.hatches:
			h.a += delta
			h.b += delta
	elif item is ShipBlueprint.PlacedRoom:
		_shift_room(item, delta)
	elif item is ShipBlueprint.PlacedEquipment:
		item.cell += delta
	elif item is ShipBlueprint.Hatch:
		item.a += delta
		item.b += delta
	_refresh()
	return true


## Turns a module a quarter turn counter-clockwise (seen from above) about
## its own centre, carrying its contents. Four turns restore it exactly.
## Internal equipment turns in place.
func rotate_module(id: String) -> bool:
	var m: Variant = blueprint.find(id)
	if not m is ShipBlueprint.PlacedModule or not catalog.hull.has(m.def_id):
		return false
	var index := blueprint.modules.find(m)
	var size := grid.module_size(index)
	var contents := _contents_of(m)
	_checkpoint()
	var old_pos: Vector3i = m.position
	# Keep the centre: new corner = centre − rotated half-size (rounded down).
	var new_pos := Vector3i(
		floori(old_pos.x + size.x * 0.5 - size.z * 0.5), old_pos.y,
		floori(old_pos.z + size.z * 0.5 - size.x * 0.5))
	# Cell map for a quarter turn: (x, z) → (x' + Δz, z' + sx − 1 − Δx).
	var turn := func(c: Vector3i) -> Vector3i:
		return Vector3i(new_pos.x + (c.z - old_pos.z), c.y, new_pos.z + size.x - 1 - (c.x - old_pos.x))
	m.position = new_pos
	m.rotation = (m.rotation + 1) % 4
	for room: ShipBlueprint.PlacedRoom in contents.rooms:
		var a: Vector3i = turn.call(Vector3i(room.rect.position.x, room.deck, room.rect.position.y))
		var b: Vector3i = turn.call(Vector3i(room.rect.end.x - 1, room.deck, room.rect.end.y - 1))
		room.rect = Rect2i(mini(a.x, b.x), mini(a.z, b.z), absi(b.x - a.x) + 1, absi(b.z - a.z) + 1)
	for e: ShipBlueprint.PlacedEquipment in contents.equipment:
		var i := blueprint.equipment.find(e)
		var def := grid.equipment_def(i)
		if def.is_external():
			e.cell = turn.call(e.cell)
			e.face = ShipGrid.face_of(ShipGrid.rotate_dir(ShipGrid.FACE_NORMALS[e.face], 1))
		else:
			var lo := Vector3i(1 << 20, 0, 1 << 20)
			for c in grid.equipment_cells(i):
				var t: Vector3i = turn.call(c)
				lo = Vector3i(mini(lo.x, t.x), t.y, mini(lo.z, t.z))
			e.cell = lo
			e.rotation = (e.rotation + 1) % 4
	for h: ShipBlueprint.Hatch in contents.hatches:
		h.a = turn.call(h.a)
		h.b = turn.call(h.b)
	_refresh()
	return true


## Id of the topmost part at a cell: external equipment on `face` (if given),
## then internal equipment, room, module. "" if nothing.
func item_at(cell: Vector3i, face: StringName = &"") -> String:
	if face != &"":
		for e in blueprint.equipment:
			if e.cell == cell and e.face == face:
				return e.id
	if grid.equipment_at.has(cell):
		return blueprint.equipment[grid.equipment_at[cell]].id
	if grid.room_at.has(cell):
		return blueprint.rooms[grid.room_at[cell]].id
	if grid.module_at.has(cell):
		return blueprint.modules[grid.module_at[cell]].id
	return ""


## Cells occupied by a part, for highlighting (external equipment: its cell).
func cells_of(id: String) -> Array[Vector3i]:
	var item: Variant = blueprint.find(id)
	var cells: Array[Vector3i] = []
	if item is ShipBlueprint.PlacedModule:
		if catalog.hull.has(item.def_id):
			cells = grid.module_cells(blueprint.modules.find(item))
	elif item is ShipBlueprint.PlacedRoom:
		cells = ShipGrid.room_cells(item)
	elif item is ShipBlueprint.PlacedEquipment:
		var i := blueprint.equipment.find(item)
		var def := grid.equipment_def(i)
		if def == null or def.is_external():
			cells.append(item.cell)
		else:
			cells = grid.equipment_cells(i)
	elif item is ShipBlueprint.Hatch:
		cells.append(item.a)
		cells.append(item.b)
	return cells


## Errors an edit would introduce, without changing the blueprint. `edit`
## receives a scratch copy of the blueprint to modify.
func preview_new_errors(edit: Callable) -> Array[ShipValidator.Issue]:
	var scratch := blueprint.duplicate_blueprint()
	edit.call(scratch)
	var before := {}
	for issue in report.errors():
		before[issue.message] = true
	var out: Array[ShipValidator.Issue] = []
	for issue in ShipValidator.validate(scratch, catalog).errors():
		if not before.has(issue.message):
			out.append(issue)
	return out


## Rooms, equipment and hatches lying entirely inside a module's cells.
func _contents_of(m: ShipBlueprint.PlacedModule) -> Dictionary:
	var out := {"rooms": [], "equipment": [], "hatches": []}
	var index := blueprint.modules.find(m)
	if not catalog.hull.has(m.def_id):
		return out
	var inside := {}
	for c in grid.module_cells(index):
		inside[c] = true
	var all_inside := func(cells: Array) -> bool:
		return not cells.is_empty() and cells.all(func(c: Vector3i) -> bool: return inside.has(c))
	for r in blueprint.rooms:
		if all_inside.call(ShipGrid.room_cells(r)):
			out.rooms.append(r)
	for i in blueprint.equipment.size():
		var e := blueprint.equipment[i]
		var def := grid.equipment_def(i)
		if def == null:
			continue
		var cells: Array = [e.cell] if def.is_external() else grid.equipment_cells(i)
		if all_inside.call(cells):
			out.equipment.append(e)
	for h in blueprint.hatches:
		if inside.has(h.a) and inside.has(h.b):
			out.hatches.append(h)
	return out


static func _shift_room(room: ShipBlueprint.PlacedRoom, delta: Vector3i) -> void:
	room.deck += delta.y
	room.rect.position += Vector2i(delta.x, delta.z)


func _checkpoint() -> void:
	_undo.append(blueprint.to_dict())
	if _undo.size() > HISTORY_LIMIT:
		_undo.pop_front()
	_redo.clear()


func _restore(d: Dictionary) -> void:
	var errors := PackedStringArray()
	blueprint = ShipBlueprint.from_dict(d, errors)
	_refresh()


func _refresh() -> void:
	grid = ShipGrid.build(blueprint, catalog)
	stats = ShipStats.compute(blueprint, grid)
	report = ShipValidator.validate(blueprint, catalog, grid, stats)
	revision += 1
	changed.emit()
