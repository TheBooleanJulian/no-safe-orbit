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
## A round stopped by the first plate it meets at this incidence or steeper
## (degrees from the normal) is deflected rather than shattered: it
## ricochets off the plate (the world flies it on, slower).
const RICOCHET_MIN_DEG := 60.0
## Armour lost each time a round breaks through a plate / is stopped by it.
const ARMOR_LOSS_PENETRATED_MM := 3.0
const ARMOR_LOSS_STOPPED_MM := 1.0


## Fraction t ∈ [0, 1] along the body-frame segment a→b where it first enters
## solid hull, or -1 if it never does (e.g. it only crosses the empty
## corners of the hull's bounding box, or the empty half of a wedge).
static func first_hull_entry(systems: ShipSystems, a_body: Vector3, b_body: Vector3) -> float:
	var c := ShipGrid.CELL_SIZE_M
	var com := systems.stats.center_of_mass_m
	var d := b_body - a_body
	var length := d.length()
	if length < 1e-6:
		return 0.0 if systems.grid.is_hull(_cell_of((a_body + com) / c)) else -1.0
	var dir := d / length
	var start := (a_body + com) / c
	var steps := ShipGrid.traverse(start, dir, length / c)
	for i in steps.size():
		var t1: float = steps[i + 1].t if i + 1 < steps.size() else length / c
		var span := _solid_span(systems.grid, steps[i].cell, start, dir, steps[i].t, t1)
		if not span.is_empty():
			return clampf(float(span.t) * c / length, 0.0, 1.0)
	return -1.0


## The part of a ray inside one cell that is solid hull. {} when the cell is
## not hull or the ray only crosses a wedge's empty half; else {t, t_out}
## (cell units along the ray) and whether it enters / leaves through the
## wedge's slope (slope_in / slope_out).
static func _solid_span(grid: ShipGrid, cell: Vector3i, start: Vector3, dir: Vector3, t0: float, t1: float) -> Dictionary:
	if not grid.is_hull(cell):
		return {}
	var mi: int = grid.module_at[cell]
	if not grid.is_wedge(mi):
		return {"t": t0, "t_out": t1, "slope_in": false, "slope_out": false}
	var eps := minf(1e-4, (t1 - t0) * 0.25)
	var in0 := grid.wedge_contains(mi, start + dir * (t0 + eps))
	var in1 := grid.wedge_contains(mi, start + dir * (t1 - eps))
	if not in0 and not in1:
		return {}
	if in0 and in1:
		return {"t": t0, "t_out": t1, "slope_in": false, "slope_out": false}
	# Crosses the slope inside the cell: find where (bisection).
	var lo := t0
	var hi := t1
	for k in 24:
		var mid := (lo + hi) * 0.5
		if grid.wedge_contains(mi, start + dir * mid) == in0:
			lo = mid
		else:
			hi = mid
	var tc := (lo + hi) * 0.5
	if in1:
		return {"t": tc, "t_out": t1, "slope_in": true, "slope_out": false}
	return {"t": t0, "t_out": tc, "slope_in": false, "slope_out": true}


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
	var met_armor := false
	var inside := false
	var hit_rooms := {}
	var hit_equipment := {}
	report.entry_pen_mm = pen_mm
	report.path_body.append(point_body)
	report.add("Round arrives with %.0f mm penetration" % pen_mm)
	var steps := ShipGrid.traverse(start, dir, reach)
	var prev := Vector3i(1 << 20, 0, 0)
	for i in steps.size():
		var cell: Vector3i = steps[i].cell
		var t0: float = steps[i].t
		var t1: float = steps[i + 1].t if i + 1 < steps.size() else reach
		var n: Vector3i = steps[i].normal
		var span := _solid_span(grid, cell, start, dir, t0, t1)
		if span.is_empty():
			if inside:
				# Out through the face between the last solid cell and this one.
				pen = _leave(systems, prev, ShipGrid.face_of(n), Vector3(n), dir, (start + dir * t0) * c - com, pen, report)
				inside = false
			if pen <= 0.0:
				break
			prev = cell
			continue
		var here := (start + dir * float(span.t)) * c - com
		if not inside:
			if i == 0 and not span.slope_in:
				met_armor = true  # started inside the hull (fired from within): no armour
			else:
				# In through the slope, or through the face crossed from the last cell.
				var face: StringName = grid.slope_faces(cell)[1] if span.slope_in else ShipGrid.face_of(-n)
				var outward: Vector3 = grid.wedge_normal(grid.module_at[cell]) if span.slope_in else -Vector3(n)
				if not span.slope_in:
					pen = _strike_external(systems, systems.external_at(cell, face), pen, report, here)
				if pen > 0.0:
					var first_plate := not met_armor
					if first_plate:
						report.entry_normal_body = outward
					var cos_i := absf(dir.dot(outward))
					pen = _armor(systems, cell, face, cos_i, pen, report, first_plate, here)
					met_armor = true
					var incidence := rad_to_deg(acos(clampf(cos_i, 0.0, 1.0)))
					if pen <= 0.0 and first_plate and incidence >= RICOCHET_MIN_DEG:
						report.ricochet = true
						report.ricochet_normal_body = outward
						report.event(&"ricochet", "", here, "Deflected at %.0f° incidence — ricochets off the plate" % incidence)
			report.exit_pen_mm = 0.0  # back inside a hull
			inside = true
		else:
			# Between two solid cells: a bulkhead if the rooms differ.
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
		if pen > 0.0:
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
			if not report.lines[-1].begins_with("Stopped"):
				report.event(&"spent", "", here, "Spent inside module %s" % bp.modules[grid.module_at[cell]].id)
			report.exit_pen_mm = 0.0
			break
		if span.slope_out:
			# Out through the wedge's slope, inside this cell.
			var slope_face: StringName = grid.slope_faces(cell)[1]
			pen = _leave(systems, cell, slope_face, grid.wedge_normal(grid.module_at[cell]), dir,
				(start + dir * float(span.t_out)) * c - com, pen, report)
			inside = false
			if pen <= 0.0:
				break
		prev = cell
	if report.exit_pen_mm > 0.0:
		report.path_body.append(report.exit_point_body + dir * c * 3.0)
	systems.update_pressure()
	return report


## Leaving the hull from `cell` through `face` (outward normal `n`): the
## plate and skin again, then any system mounted there.
static func _leave(systems: ShipSystems, cell: Vector3i, face: StringName, n: Vector3, dir: Vector3, here: Vector3,
		pen: float, report: DamageReport) -> float:
	var cos_i := absf(dir.dot(n))
	pen = _armor(systems, cell, face, cos_i, pen, report, false, here, true)
	if pen > 0.0:
		pen = _strike_external(systems, systems.external_at(cell, face), pen, report, here)
	if pen > 0.0:
		report.exit_pen_mm = pen
		report.exit_point_body = here
		report.exit_normal_body = n
		report.event(&"exit", "", here, "Exits the hull with %.0f mm left" % pen)
	return pen


## Skin plus any plate on this face, at its effective thickness for the
## incidence (capped for grazing hits). Wear comes off the plate first.
static func _armor(systems: ShipSystems, cell: Vector3i, face: StringName, cos_i: float, pen: float, report: DamageReport,
		is_first: bool, here: Vector3, exiting: bool = false) -> float:
	var mi: int = systems.grid.module_at[cell]
	var m := systems.modules[mi]
	var id := systems.blueprint.modules[mi].id
	var key := ShipBlueprint.plate_key(cell, systems.grid.plate_face(cell, face))
	var skin := m.armor_mm if not m.wrecked() else 0.0
	var plate: float = systems.plates.get(key, 0.0)
	var total := skin + plate
	if total <= 0.0:
		return pen
	var effective := minf(total / maxf(cos_i, 1e-3), total * MAX_OBLIQUITY_FACTOR)
	var angle := rad_to_deg(acos(clampf(cos_i, 0.0, 1.0)))
	var side := "exit" if exiting else "outer"
	var what := "%.0f mm skin%s" % [skin, " + %.0f mm plate" % plate if plate > 0.0 else ""]
	var stopped := pen <= effective
	var wear := ARMOR_LOSS_STOPPED_MM if stopped else ARMOR_LOSS_PENETRATED_MM
	if plate > 0.0:
		systems.plates[key] = maxf(plate - wear, 0.0)
	else:
		m.armor_mm = maxf(m.armor_mm - wear, 0.0)
	if stopped:
		report.stopped_by_armor = is_first
		report.event(&"armor_stop", id, here, "Stopped by %s %s armour: %s = %.0f mm effective at %.0f° vs %.0f mm" % [
			id, side, what, effective, angle, pen])
		return 0.0
	report.penetrated = true
	report.event(&"armor_pen", id, here, "Penetrates %s %s armour (%s, %.0f mm effective at %.0f°): %.0f mm left" % [
		id, side, what, effective, angle, pen - effective])
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
	var blasts := systems.explosions.size()
	var destroyed := systems.damage_equipment(e, absorbed)
	if destroyed:
		report.destroyed_ids.append(e.id)
		report.event(&"system_destroyed", e.id, here, "%s %s destroyed (%.0f mm absorbed)" % [e.def.display_name, e.id, absorbed])
		if e.def.kind == EquipmentDefinition.Kind.PROPELLANT_TANK:
			report.propellant_lost_kg += e.def.propellant_capacity_kg
		for blast in systems.explosions.slice(blasts):
			for line in blast.lines:
				report.event(&"explosion", e.id, blast.pos_body, line)
	else:
		report.damaged_ids.append(e.id)
		report.event(&"system_damaged", e.id, here, "%s %s damaged (%.0f mm absorbed, %.0f%% condition left)" % [
			e.def.display_name, e.id, absorbed, 100.0 * e.hp / e.max_hp])
	return pen - absorbed


static func _cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))
