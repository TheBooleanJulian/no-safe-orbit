class_name ShipEditor
extends RefCounted
## Editing operations on a blueprint, independent of any UI so they can be
## tested headless. After every successful edit the grid, stats and
## validation report are re-derived from the blueprint, and `revision` bumps.

signal changed

var blueprint: ShipBlueprint
var catalog: ConstructionCatalog
var grid: ShipGrid
var stats: ShipStats
var report: ShipValidator.Report
var revision: int = 0


func _init(p_blueprint: ShipBlueprint, p_catalog: ConstructionCatalog) -> void:
	catalog = p_catalog
	set_blueprint(p_blueprint)


func set_blueprint(bp: ShipBlueprint) -> void:
	blueprint = bp
	_refresh()


func place_module(def_id: StringName, base_cell: Vector3i, rotation: int) -> String:
	var m := blueprint.add_module(def_id, base_cell, rotation)
	_refresh()
	return m.id


func place_room(def_id: StringName, deck: int, rect: Rect2i) -> String:
	var r := blueprint.add_room(def_id, deck, rect.abs())
	_refresh()
	return r.id


func place_equipment(def_id: StringName, cell: Vector3i, face: StringName = &"") -> String:
	var def: EquipmentDefinition = catalog.equipment.get(def_id)
	var e := blueprint.add_equipment(def_id, cell, face if def != null and def.is_external() else &"")
	_refresh()
	return e.id


## Adds a hatch between two cells, or removes the one already there.
## Returns true if a hatch now exists.
func toggle_hatch(a: Vector3i, b: Vector3i) -> bool:
	for h in blueprint.hatches:
		if (h.a == a and h.b == b) or (h.a == b and h.b == a):
			blueprint.remove(h.id)
			_refresh()
			return false
	blueprint.add_hatch(a, b)
	_refresh()
	return true


func remove(id: String) -> bool:
	var ok := blueprint.remove(id)
	if ok:
		_refresh()
	return ok


## Moves a module, room or equipment by whole cells (deck = y).
func move(id: String, delta: Vector3i) -> bool:
	var item: Variant = blueprint.find(id)
	if item is ShipBlueprint.PlacedModule:
		item.position += delta
	elif item is ShipBlueprint.PlacedRoom:
		item.deck += delta.y
		item.rect.position += Vector2i(delta.x, delta.z)
	elif item is ShipBlueprint.PlacedEquipment:
		item.cell += delta
	elif item is ShipBlueprint.Hatch:
		item.a += delta
		item.b += delta
	else:
		return false
	_refresh()
	return true


## Turns a module a quarter turn counter-clockwise about its own corner cell.
func rotate_module(id: String) -> bool:
	var item: Variant = blueprint.find(id)
	if not item is ShipBlueprint.PlacedModule:
		return false
	item.rotation = (item.rotation + 1) % 4
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


func _refresh() -> void:
	grid = ShipGrid.build(blueprint, catalog)
	stats = ShipStats.compute(blueprint, grid)
	report = ShipValidator.validate(blueprint, catalog, grid, stats)
	revision += 1
	changed.emit()
