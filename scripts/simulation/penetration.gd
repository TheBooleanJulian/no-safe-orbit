class_name Penetration
extends RefCounted
## Deterministic kinetic penetration through a ship's cell grid (spec §7
## "Damage resolution"). The round's path is walked cell by cell:
##   entering the hull → any external system on that face, then the module's
##     armour at its effective thickness (thicker at oblique incidence);
##   inside → structure per cell, room breaches, bulkheads (which destroy any
##     hatch in them), internal systems that absorb their shielding;
##   leaving the hull → armour again, then any external system on that face;
## until its penetration (mm) is spent or it leaves the ship for good (it then
## flies on, slower). Not a finite-element model: a simple, explainable
## budget of millimetres. Every step is recorded with its position for the
## hit replay.

## Penetration lost per hull cell crossed (frames, cabling, fittings).
const STRUCTURE_MM_PER_CELL := 2.0
## Structure damage per hull cell crossed.
const STRUCTURE_DAMAGE_PER_CELL := 2.0
## Penetration lost crossing a bulkhead between rooms.
const BULKHEAD_MM := 8.0
## Effective armour is capped at this multiple of its thickness (grazing hits).
const MAX_OBLIQUITY_FACTOR := 3.0
## Armour lost each time a round breaks through a plate / is stopped by it.
const ARMOR_LOSS_PENETRATED_MM := 3.0
const ARMOR_LOSS_STOPPED_MM := 1.0


## Fraction t ∈ [0, 1] along the body-frame segment a→b where it first enters
## a hull cell, or -1 if it never does (e.g. it only crosses the empty
## corners of the hull's bounding box).
static func first_hull_entry(systems: ShipSystems, a_body: Vector3, b_body: Vector3) -> float:
	var c := ShipGrid.CELL_SIZE_M
	var com := systems.stats.center_of_mass_m
	var d := b_body - a_body
	var length := d.length()
	if length < 1e-6:
		return 0.0 if systems.grid.is_hull(_cell_of((a_body + com) / c)) else -1.0
	var dir := d / length
	for step in ShipGrid.traverse((a_body + com) / c, dir, length / c):
		if systems.grid.is_hull(step.cell):
			return clampf(step.t * c / length, 0.0, 1.0)
	return -1.0


## Apply one round to the ship. `point_body` is where it reached the hull
## (body frame), `dir_body` its direction relative to the ship, `pen_mm` its
## penetration at that impact speed. Mutates `systems` and returns a report.
static func apply(systems: ShipSystems, point_body: Vector3, dir_body: Vector3, pen_mm: float) -> DamageReport:
	var report := DamageReport.new()
	var grid := systems.grid
	var bp := systems.blueprint
	var c := ShipGrid.CELL_SIZE_M
	var com := systems.stats.center_of_mass_m
	var dir := dir_body.normalized()
	# Start one cell outside so the first hull cell is "entered".
	var start := (point_body + com) / c - dir
	var reach := grid.cell_bounds().size.length() + 4.0
	var pen := pen_mm
	var prev := Vector3i(1 << 20, 0, 0)
	var first := true
	var met_armor := false
	var hit_rooms := {}
	var hit_equipment := {}
	report.entry_pen_mm = pen_mm
	report.path_body.append(point_body)
	report.add("Round arrives with %.0f mm penetration" % pen_mm)
	var here := point_body
	var in_hull := false
	for step in ShipGrid.traverse(start, dir, reach):
		var cell: Vector3i = step.cell
		here = (start + dir * float(step.t)) * c - com
		in_hull = grid.is_hull(cell)
		var prev_in_hull := not first and grid.is_hull(prev)
		var n: Vector3i = step.normal
		if not first and n != Vector3i.ZERO:
			var cos_i := absf(dir.dot(Vector3(n)))
			if in_hull and not prev_in_hull:
				pen = _strike_external(systems, systems.external_at(cell, ShipGrid.face_of(-n)), pen, report, here)
				if pen > 0.0:
					pen = _armor(systems, grid.module_at[cell], cos_i, pen, report, not met_armor, here)
					met_armor = true
				report.exit_pen_mm = 0.0  # back inside a hull
			elif prev_in_hull and not in_hull:
				pen = _armor(systems, grid.module_at[prev], cos_i, pen, report, false, here, true)
				if pen > 0.0:
					pen = _strike_external(systems, systems.external_at(prev, ShipGrid.face_of(n)), pen, report, here)
				if pen > 0.0:
					report.exit_pen_mm = pen
					report.exit_point_body = here
					report.event(&"exit", "", here, "Exits the hull with %.0f mm left" % pen)
			elif prev_in_hull and in_hull:
				var ra: int = grid.room_at.get(prev, -1)
				var rb: int = grid.room_at.get(cell, -1)
				if ra != rb and (ra >= 0 or rb >= 0):
					var hatch := grid.hatch_between(prev, cell)
					if hatch != "" and not systems.destroyed_hatches.has(hatch):
						systems.destroy_hatch(hatch)
						report.destroyed_hatches.append(hatch)
						report.event(&"hatch", hatch, here, "Hatch %s destroyed — it can no longer seal" % hatch)
					pen -= BULKHEAD_MM
					if pen <= 0.0:
						report.event(&"bulkhead_stop", "", here, "Stopped by a bulkhead")
		elif first and in_hull:
			# Started inside the hull (a round fired from within): no armour.
			met_armor = true
		first = false
		if pen > 0.0 and in_hull:
			var mi: int = grid.module_at[cell]
			pen -= STRUCTURE_MM_PER_CELL
			if systems.damage_module(mi, STRUCTURE_DAMAGE_PER_CELL):
				report.wrecked_modules.append(bp.modules[mi].id)
				report.event(&"wrecked", bp.modules[mi].id, here, "Module %s structure fails — its power junction is cut" % bp.modules[mi].id)
			var ri: int = grid.room_at.get(cell, -1)
			if ri >= 0 and not hit_rooms.has(ri):
				hit_rooms[ri] = true
				if systems.breach_room(ri):
					report.breached_rooms.append(bp.rooms[ri].id)
					report.event(&"breach", bp.rooms[ri].id, here, "%s %s breached — venting, hatches sealing" % [systems._room_name(ri), bp.rooms[ri].id])
			var e := systems.equipment_at_cell(cell)
			if e != null and not hit_equipment.has(e.id) and pen > 0.0:
				hit_equipment[e.id] = true
				pen = _strike(systems, e, pen, report, here)
		if pen <= 0.0:
			if in_hull and not report.lines[-1].begins_with("Stopped"):
				report.event(&"spent", "", here, "Spent inside module %s" % bp.modules[grid.module_at[cell]].id)
			report.exit_pen_mm = 0.0
			break
		prev = cell
	if report.exit_pen_mm > 0.0:
		report.path_body.append(report.exit_point_body + dir * c * 3.0)
	systems.update_pressure()
	return report


static func _armor(systems: ShipSystems, mi: int, cos_i: float, pen: float, report: DamageReport,
		is_first: bool, here: Vector3, exiting: bool = false) -> float:
	var m := systems.modules[mi]
	var id := systems.blueprint.modules[mi].id
	var plate := m.armor_mm if not m.wrecked() else 0.0
	if plate <= 0.0:
		return pen
	var effective := minf(plate / maxf(cos_i, 1e-3), plate * MAX_OBLIQUITY_FACTOR)
	var angle := rad_to_deg(acos(clampf(cos_i, 0.0, 1.0)))
	var side := "exit" if exiting else "outer"
	if pen <= effective:
		m.armor_mm = maxf(m.armor_mm - ARMOR_LOSS_STOPPED_MM, 0.0)
		report.stopped_by_armor = is_first
		report.event(&"armor_stop", id, here, "Stopped by %s %s armour: %.0f mm plate = %.0f mm effective at %.0f° vs %.0f mm" % [
			id, side, plate, effective, angle, pen])
		return 0.0
	m.armor_mm = maxf(m.armor_mm - ARMOR_LOSS_PENETRATED_MM, 0.0)
	report.penetrated = true
	report.event(&"armor_pen", id, here, "Penetrates %s %s armour (%.0f mm, %.0f mm effective at %.0f°): %.0f mm left" % [
		id, side, plate, effective, angle, pen - effective])
	return pen - effective


static func _strike_external(systems: ShipSystems, e: ShipSystems.EquipmentState, pen: float,
		report: DamageReport, here: Vector3) -> float:
	if e == null or e.destroyed():
		return pen
	return _strike(systems, e, pen, report, here)


## A system in the round's path absorbs up to its shielding and takes that
## much damage. Destroyed tanks lose their propellant.
static func _strike(systems: ShipSystems, e: ShipSystems.EquipmentState, pen: float,
		report: DamageReport, here: Vector3) -> float:
	if e.destroyed():
		return pen
	var absorbed := minf(pen, e.def.shielding_mm())
	var destroyed := systems.damage_equipment(e, absorbed)
	if destroyed:
		report.destroyed_ids.append(e.id)
		report.event(&"system_destroyed", e.id, here, "%s %s destroyed (%.0f mm absorbed)" % [e.def.display_name, e.id, absorbed])
		if e.def.kind == EquipmentDefinition.Kind.PROPELLANT_TANK:
			report.propellant_lost_kg += e.def.propellant_capacity_kg
	else:
		report.damaged_ids.append(e.id)
		report.event(&"system_damaged", e.id, here, "%s %s damaged (%.0f mm absorbed, %.0f%% condition left)" % [
			e.def.display_name, e.id, absorbed, 100.0 * e.hp / e.max_hp])
	return pen - absorbed


static func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))
