class_name PdCoverage
extends RefCounted
## Point-defence coverage of a design (Milestone 15: PD that scales with hull
## size). A direction is covered when some PD mount can fire along it: within
## its arc (no more than WorldSimulation.TURRET_ARC_MIN_DOT below its face)
## and with no hull of its own in the way — the rules the simulation's PD
## uses. Coverage is the share of DIRECTIONS (evenly spread over the sphere)
## covered. A hull wants a mount per AREA_PER_MOUNT_M2 of outside surface:
## a long hull shadows its own mounts, and a big one draws more fire.

const DIRECTIONS := 48
const AREA_PER_MOUNT_M2 := 1500.0
## The barrel sits this far off the face (m), as in flight.
const TURRET_HEIGHT_M := 1.0


## {mounts, recommended, coverage (0..1), area_m2} for the design in `grid`.
static func of(grid: ShipGrid) -> Dictionary:
	var bp := grid.blueprint
	var mounts: Array = []  # [position (grid m), normal]
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or def.kind != EquipmentDefinition.Kind.POINT_DEFENCE:
			continue
		var n := Vector3(ShipGrid.FACE_NORMALS.get(bp.equipment[i].face, Vector3i.ZERO))
		if n == Vector3.ZERO:
			continue
		mounts.append([grid.equipment_position_m(i) + n * TURRET_HEIGHT_M, n])
	var faces := 0
	for i in bp.modules.size():
		faces += grid.exterior_face_count(i)
	var area := faces * ShipGrid.CELL_SIZE_M * ShipGrid.CELL_SIZE_M
	var covered := 0
	if not mounts.is_empty():
		var reach := grid.cell_bounds().size.length() + 2.0
		for k in DIRECTIONS:
			var d := _direction(k)
			for m: Array in mounts:
				if d.dot(m[1]) >= WorldSimulation.TURRET_ARC_MIN_DOT and not _blocked(grid, m[0] + d * 0.5, d, reach):
					covered += 1
					break
	return {"mounts": mounts.size(), "recommended": ceili(area / AREA_PER_MOUNT_M2), "coverage": float(covered) / DIRECTIONS, "area_m2": area}


## The k-th of DIRECTIONS points spread evenly over the sphere (Fibonacci).
static func _direction(k: int) -> Vector3:
	var y := 1.0 - 2.0 * (k + 0.5) / DIRECTIONS
	var r := sqrt(maxf(1.0 - y * y, 0.0))
	var a := k * PI * (3.0 - sqrt(5.0))
	return Vector3(cos(a) * r, y, sin(a) * r)


## Does a ray from `start` (grid m) along `dir` meet a hull cell within `reach` cells?
static func _blocked(grid: ShipGrid, start: Vector3, dir: Vector3, reach: float) -> bool:
	for step: Dictionary in ShipGrid.traverse(start / ShipGrid.CELL_SIZE_M, dir, reach):
		if grid.is_hull(step.cell):
			return true
	return false
