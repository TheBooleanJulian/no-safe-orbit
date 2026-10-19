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
## When set, validation also checks the parts are owned / unlocked.
var profile: PlayerProfile

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


func place_module(def_id: StringName, base_cell: Vector3i, rotation: int, flip: bool = false) -> String:
	_checkpoint()
	var m := blueprint.add_module(def_id, base_cell, rotation, flip)
	_refresh()
	return m.id


## Which faces an armour paint stroke covers.
enum PlateFaces { ALL, SIDES, TOP, UNDERSIDE }


## Paint armour plates of `mm` (0 removes them) on the plateable faces of
## the cells of `rect` (x, z) on `deck`, filtered by `faces`. Returns how
## many plates changed.
func paint_armor(deck: int, rect: Rect2i, mm: int, faces: PlateFaces = PlateFaces.ALL) -> int:
	var changes := {}
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var cell := Vector3i(x, deck, z)
			for face in grid.plateable_faces(cell):
				var top := face == &"dorsal"
				var bottom := face == &"ventral"
				match faces:
					PlateFaces.SIDES:
						if top or bottom:
							continue
					PlateFaces.TOP:
						if not top:
							continue
					PlateFaces.UNDERSIDE:
						if not bottom:
							continue
				var key := ShipBlueprint.plate_key(cell, face)
				if int(blueprint.armor.get(key, 0)) != mm:
					changes[key] = mm
	if changes.is_empty():
		return 0
	_checkpoint()
	for key in changes:
		if changes[key] <= 0:
			blueprint.armor.erase(key)
		else:
			blueprint.armor[key] = changes[key]
	_refresh()
	return changes.size()


## Lay (or with `on` false, remove) power conduit in the hull cells of
## `rect` (x, z) on `deck`. Returns how many cells changed.
func paint_bus(deck: int, rect: Rect2i, on: bool) -> int:
	var changes: Array[String] = []
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var cell := Vector3i(x, deck, z)
			var key := ShipBlueprint.cell_key(cell)
			if on and grid.is_hull(cell) and not blueprint.bus.has(key):
				changes.append(key)
			elif not on and blueprint.bus.has(key):
				changes.append(key)
	if changes.is_empty():
		return 0
	_checkpoint()
	for key in changes:
		if on:
			blueprint.bus[key] = true
		else:
			blueprint.bus.erase(key)
	_refresh()
	return changes.size()


## Replace the bus with a tree that reaches every system that makes or
## draws power and every room that draws it: grown from the first power
## distribution unit (else reactor) along the shortest hull paths. Returns
## the number of conduit cells, or 0 if there is nothing to route.
func auto_route_bus() -> int:
	var terminals: Array = []  # Array of Array[Vector3i]
	var root: Array = []
	for i in blueprint.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or (def.power_kw == 0.0 and def.kind != EquipmentDefinition.Kind.POWER_DISTRIBUTION):
			continue
		var all_cells: Array = [blueprint.equipment[i].cell] if def.is_external() else grid.equipment_cells(i)
		var cells: Array = all_cells.filter(func(c: Vector3i) -> bool: return grid.is_hull(c))
		if cells.is_empty():
			continue
		if def.kind == EquipmentDefinition.Kind.POWER_DISTRIBUTION and root.is_empty():
			root = cells
		terminals.append(cells)
	for r in blueprint.rooms:
		var def: RoomDefinition = catalog.rooms.get(r.def_id)
		if def != null and def.power_kw_per_cell < 0.0:
			terminals.append(ShipGrid.room_cells(r))
	if root.is_empty():
		for i in blueprint.equipment.size():
			var def := grid.equipment_def(i)
			if def != null and def.kind == EquipmentDefinition.Kind.REACTOR:
				root = grid.equipment_cells(i)
				break
	if root.is_empty() or terminals.is_empty():
		return 0
	var tree := {}
	for c in root:
		tree[c] = true
	var pending := terminals.duplicate()
	while not pending.is_empty():
		pending = pending.filter(func(t: Array) -> bool: return not t.any(func(c: Vector3i) -> bool: return tree.has(c)))
		if pending.is_empty():
			break
		var wanted := {}
		for t in pending:
			for c in t:
				wanted[c] = true
		# Multi-source BFS from the tree through hull cells to the nearest wanted cell.
		var came := {}
		var queue: Array[Vector3i] = []
		for c in tree:
			came[c] = c
			queue.append(c)
		var found := Vector3i(1 << 20, 0, 0)
		while not queue.is_empty():
			var c: Vector3i = queue.pop_front()
			if wanted.has(c) and not tree.has(c):
				found = c
				break
			for face: StringName in ShipGrid.FACE_NORMALS:
				var nc: Vector3i = c + ShipGrid.FACE_NORMALS[face]
				if grid.is_hull(nc) and not came.has(nc):
					came[nc] = c
					queue.append(nc)
		if found.x == 1 << 20:
			break  # the rest cannot be reached through the hull
		var c2 := found
		while not tree.has(c2):
			tree[c2] = true
			c2 = came[c2]
	_checkpoint()
	blueprint.bus.clear()
	for c in tree:
		blueprint.bus[ShipBlueprint.cell_key(c)] = true
	_refresh()
	return blueprint.bus.size()


## Turn a module upside down (a wedge's slope then faces down).
func flip_module(id: String) -> bool:
	var m: Variant = blueprint.find(id)
	if not m is ShipBlueprint.PlacedModule:
		return false
	_checkpoint()
	m.flip = not m.flip
	_refresh()
	return true


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
		_move_plates(contents.cells, func(c: Vector3i) -> Vector3i: return c + delta, 0)
		_move_bus(contents.cells, func(c: Vector3i) -> Vector3i: return c + delta)
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
	_move_plates(contents.cells, turn, 1)
	_move_bus(contents.cells, turn)
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
		# Pointing at the middle of a cell: the top or the underside.
		if face == &"dorsal" or face == &"ventral":
			for e in blueprint.equipment:
				if e.cell == cell and (e.face == &"dorsal" or e.face == &"ventral"):
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
	for issue in _validate(scratch).errors():
		if not before.has(issue.message):
			out.append(issue)
	return out


## Armour plates on `cells` follow their cells through `map`; side faces
## turn by `quarter_turns`.
func _move_plates(cells: Dictionary, map: Callable, quarter_turns: int) -> void:
	var moved := {}
	for key in blueprint.armor.keys():
		var cf := ShipBlueprint.parse_plate_key(key)
		if not cells.has(cf[0]):
			continue
		var face: StringName = cf[1]
		if face != &"dorsal" and face != &"ventral":
			face = ShipGrid.face_of(ShipGrid.rotate_dir(ShipGrid.FACE_NORMALS[face], quarter_turns))
		moved[ShipBlueprint.plate_key(map.call(cf[0]), face)] = blueprint.armor[key]
		blueprint.armor.erase(key)
	blueprint.armor.merge(moved, true)


## Conduit in `cells` follows its cells through `map`.
func _move_bus(cells: Dictionary, map: Callable) -> void:
	var moved := {}
	for key in blueprint.bus.keys():
		var c := ShipBlueprint.parse_cell_key(key)
		if cells.has(c):
			moved[ShipBlueprint.cell_key(map.call(c))] = true
			blueprint.bus.erase(key)
	blueprint.bus.merge(moved, true)


## Rooms, equipment and hatches lying entirely inside a module's cells
## (and the cells themselves, as a set).
func _contents_of(m: ShipBlueprint.PlacedModule) -> Dictionary:
	var out := {"rooms": [], "equipment": [], "hatches": [], "cells": {}}
	var index := blueprint.modules.find(m)
	if not catalog.hull.has(m.def_id):
		return out
	var inside := {}
	for c in grid.module_cells(index):
		inside[c] = true
	out.cells = inside
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
	report = _validate(blueprint, grid, stats)
	revision += 1
	changed.emit()


func _validate(bp: ShipBlueprint, p_grid: ShipGrid = null, p_stats: ShipStats = null) -> ShipValidator.Report:
	var r := ShipValidator.validate(bp, catalog, p_grid, p_stats)
	if profile != null:
		profile.check_design(bp, catalog, r)
	return r


## Re-validate after the profile changed (parts found, units written off).
func revalidate() -> void:
	_refresh()
