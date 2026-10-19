class_name CoolantLoop
extends RefCounted
## Coolant loops — optional, like the power bus: pipes through hull cells
## that carry heat from the reactors out to the radiators. A design with no
## coolant cells cools as before (every radiator works). With pipes laid, a
## radiator only rejects heat when its mount cell is piped into a loop that
## reaches a reactor, so a cut pipe (combat) can strand radiators.
## Auto-routed in the shipyard like the bus (ShipEditor.auto_route_coolant).


## Whether the design routes its coolant (else every radiator works).
static func routed(bp: ShipBlueprint) -> bool:
	return not bp.coolant.is_empty()


## Radiators (equipment index -> true) on a loop that reaches a reactor,
## skipping pipe cells in `cut` (cell keys). Only meaningful when routed().
static func cooled_radiators(bp: ShipBlueprint, grid: ShipGrid, cut: Dictionary = {}) -> Dictionary:
	var comp := {}  # cell key -> loop id
	var loops := 0
	for key: String in bp.coolant:
		if comp.has(key) or cut.has(key):
			continue
		comp[key] = loops
		var queue: Array[Vector3i] = [ShipBlueprint.parse_cell_key(key)]
		while not queue.is_empty():
			var c: Vector3i = queue.pop_front()
			for face: StringName in ShipGrid.FACE_NORMALS:
				var nk := ShipBlueprint.cell_key(c + ShipGrid.FACE_NORMALS[face])
				if bp.coolant.has(nk) and not comp.has(nk) and not cut.has(nk):
					comp[nk] = loops
					queue.append(c + ShipGrid.FACE_NORMALS[face])
		loops += 1
	var hot := {}  # loop ids reaching a reactor
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def != null and def.kind == EquipmentDefinition.Kind.REACTOR:
			for c in grid.equipment_cells(i):
				var k := ShipBlueprint.cell_key(c)
				if comp.has(k):
					hot[comp[k]] = true
	var out := {}
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or def.kind != EquipmentDefinition.Kind.RADIATOR:
			continue
		for c in grid.external_cells(i):
			var k := ShipBlueprint.cell_key(c)
			if comp.has(k) and hot.has(comp[k]):
				out[i] = true
				break
	return out


## What the auto-router must join: the reactors (root) and every radiator's
## mount cells and every other heat-making system (terminals).
static func route_ends(bp: ShipBlueprint, grid: ShipGrid) -> Dictionary:
	var root: Array = []
	var terminals: Array = []
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null:
			continue
		var cells: Array = (grid.external_cells(i) if def.is_external() else grid.equipment_cells(i)).filter(
			func(c: Vector3i) -> bool: return grid.is_hull(c))
		if cells.is_empty():
			continue
		if def.kind == EquipmentDefinition.Kind.REACTOR:
			root.append_array(cells)
			terminals.append(cells)
		elif def.kind == EquipmentDefinition.Kind.RADIATOR or (def.heat_kw > 0.0 and not def.is_external()):
			terminals.append(cells)
	return {"root": root, "terminals": terminals}
