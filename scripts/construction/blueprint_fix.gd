class_name BlueprintFix
extends RefCounted
## Repairs designs saved before a part changed shape, when they are loaded:
## a long external system (radiator panels) whose span no longer fits is
## slid along its axis, or turned, to the nearest spot where every cell is a
## free, flat exterior face. If nothing fits it stays put (the validator
## then says so). Returns what it moved.
## Armour plates left on faces a later deck or module covered (or on cells
## that are no longer hull) are dropped by prune_plates.

static func fit_spans(bp: ShipBlueprint, catalog: ConstructionCatalog) -> PackedStringArray:
	var moved := PackedStringArray()
	var grid := ShipGrid.build(bp, catalog)
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or not def.is_external() or def.length_cells <= 1:
			continue
		if _span_ok(grid, bp, i, bp.equipment[i].cell, bp.equipment[i].rotation):
			continue
		var e := bp.equipment[i]
		var best: Array = []
		for rot in [e.rotation, (e.rotation + 1) % 2]:
			var step := ShipGrid.external_step(e.face, rot)
			for shift in range(0, def.length_cells):
				for sign in [-1, 1]:
					var start: Vector3i = e.cell + step * shift * sign
					if best.is_empty() and _span_ok(grid, bp, i, start, rot):
						best = [start, rot]
		if not best.is_empty():
			e.cell = best[0]
			e.rotation = best[1]
			moved.append(e.id)
			grid = ShipGrid.build(bp, catalog)
	return moved


static func _span_ok(grid: ShipGrid, bp: ShipBlueprint, index: int, start: Vector3i, rot: int) -> bool:
	var e := bp.equipment[index]
	var def := grid.equipment_def(index)
	var step := ShipGrid.external_step(e.face, rot)
	var taken := {}
	for j in bp.equipment.size():
		if j == index:
			continue
		var other := grid.equipment_def(j)
		if other != null and other.is_external():
			for c in grid.external_cells(j):
				taken["%s|%s" % [c, bp.equipment[j].face]] = true
	for k in def.length_cells:
		var c: Vector3i = start + step * k
		if not grid.is_exterior_face(c, e.face) or grid.slope_faces(c).has(e.face) or taken.has("%s|%s" % [c, e.face]):
			return false
	return true


## Drop armour plates that can no longer be reached: on a cell that is not
## hull, or on a face that is not exterior any more. A wedge's slope plate
## is stored under its plate_face, which plateable_faces already reports.
## Returns how many went.
static func prune_plates(bp: ShipBlueprint, grid: ShipGrid) -> int:
	var gone := 0
	for key: String in bp.armor.keys():
		var cf := ShipBlueprint.parse_plate_key(key)
		if not grid.plateable_faces(cf[0]).has(cf[1]):
			bp.armor.erase(key)
			gone += 1
	return gone
