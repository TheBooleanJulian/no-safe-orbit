class_name ShipValidator
extends RefCounted
## Checks a blueprint (spec §6 "Validation"). ERRORS mean the design is
## physically or structurally invalid and cannot launch. WARNINGS are
## trade-offs the player may accept: unconventional designs are allowed.
## Every message names the part and says what to change.


enum Severity { ERROR, WARNING }


class Issue:
	var severity: Severity
	## Stable machine-readable code, e.g. "module_detached" (used by tests/UI).
	var code: StringName
	var message: String
	## Id of the module/room/hatch/equipment concerned ("" for whole-ship).
	var subject: String

	func _to_string() -> String:
		return "%s %s: %s" % ["ERROR" if severity == Severity.ERROR else "WARN", code, message]


class Report:
	var issues: Array[Issue] = []

	func has_errors() -> bool:
		return issues.any(func(i: Issue) -> bool: return i.severity == Severity.ERROR)

	func errors() -> Array[Issue]:
		return _with(Severity.ERROR)

	func warnings() -> Array[Issue]:
		return _with(Severity.WARNING)

	func _with(severity: Severity) -> Array[Issue]:
		var out: Array[Issue] = []
		for i in issues:
			if i.severity == severity:
				out.append(i)
		return out

	func add(severity: Severity, code: StringName, message: String, subject: String) -> void:
		ShipValidator._add(self, severity, code, message, subject)

	func has_code(code: StringName) -> bool:
		return issues.any(func(i: Issue) -> bool: return i.code == code)

	func summary() -> String:
		return "\n".join(issues.map(func(i: Issue) -> String: return str(i)))


## Engine thrust may use at most this fraction of RCS torque to hold attitude.
const MAX_THRUST_TORQUE_FRACTION := 0.5


static func validate(bp: ShipBlueprint, catalog: ConstructionCatalog,
		grid: ShipGrid = null, stats: ShipStats = null) -> Report:
	var report := Report.new()
	if grid == null:
		grid = ShipGrid.build(bp, catalog)
	for msg in grid.unknown:
		_add(report, Severity.ERROR, &"unknown_definition", msg, "")
	if bp.modules.is_empty():
		_add(report, Severity.ERROR, &"no_hull", "The design has no hull modules.", "")
		return report
	_check_structure(bp, grid, report)
	_check_rooms(bp, grid, report)
	_check_hatches(bp, grid, report)
	_check_equipment(bp, grid, report)
	_check_access(bp, grid, report)
	if stats == null:
		stats = ShipStats.compute(bp, grid)
	_check_systems(bp, grid, stats, report)
	_check_coolant(bp, grid, report)
	return report


## Routed coolant: radiators off a reactor's loop reject nothing.
static func _check_coolant(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	if not CoolantLoop.routed(bp):
		return
	var cooled := CoolantLoop.cooled_radiators(bp, grid)
	var cold := PackedStringArray()
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def != null and def.kind == EquipmentDefinition.Kind.RADIATOR and not cooled.has(i):
			cold.append(bp.equipment[i].id)
	if not cold.is_empty():
		_add(report, Severity.WARNING, &"radiator_uncooled",
			"%d radiator%s not piped to a reactor (%s): no heat goes there. Auto-route the coolant loop." % [
				cold.size(), "" if cold.size() == 1 else "s", ", ".join(cold)], cold[0])


static func _add(report: Report, severity: Severity, code: StringName, message: String, subject: String) -> void:
	var issue := Issue.new()
	issue.severity = severity
	issue.code = code
	issue.message = message
	issue.subject = subject
	report.issues.append(issue)


static func _cell_text(c: Vector3i) -> String:
	return "(x %d, deck %d, z %d)" % [c.x, c.y, c.z]


# --- Hull -------------------------------------------------------------------

static func _check_structure(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	var reported := {}
	for o in grid.module_overlaps:
		var key := "%d-%d" % [o[1], o[2]]
		if reported.has(key):
			continue
		reported[key] = true
		_add(report, Severity.ERROR, &"module_overlap", "Modules %s and %s overlap at %s." % [
			bp.modules[o[1]].id, bp.modules[o[2]].id, _cell_text(o[0])], bp.modules[o[2]].id)

	# Attachment graph: modules that share at least one face.
	var n := bp.modules.size()
	var attached := grid.attachments()
	# Everything must be attached, directly or indirectly, to the first module.
	var seen := {0: true}
	var queue := [0]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j in attached[i]:
			if not seen.has(j):
				seen[j] = true
				queue.append(j)
	for i in n:
		if seen.has(i) or grid.module_def(i) == null:
			continue
		_add(report, Severity.ERROR, &"module_detached",
			"Module %s (%s) is not structurally attached: it shares no face with the rest of the hull. Move it so one of its faces touches another module." % [
				bp.modules[i].id, grid.module_def(i).display_name], bp.modules[i].id)


# --- Rooms and hatches ------------------------------------------------------

static func _check_rooms(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	for r in bp.rooms:
		if r.rect.size.x <= 0 or r.rect.size.y <= 0:
			_add(report, Severity.ERROR, &"room_empty", "Room %s has no cells." % r.id, r.id)
			continue
		for cell in ShipGrid.room_cells(r):
			if not grid.is_interior(cell):
				var where := "outside the hull" if not grid.is_hull(cell) else "in an unpressurised module"
				_add(report, Severity.ERROR, &"room_outside_hull",
					"Room %s (%s) extends %s at %s." % [r.id, _room_name(grid, r), where, _cell_text(cell)], r.id)
				break
	var reported := {}
	for o in grid.room_overlaps:
		var key := "%d-%d" % [o[1], o[2]]
		if not reported.has(key):
			reported[key] = true
			_add(report, Severity.ERROR, &"room_overlap", "Rooms %s and %s overlap at %s." % [
				bp.rooms[o[1]].id, bp.rooms[o[2]].id, _cell_text(o[0])], bp.rooms[o[2]].id)


static func _room_name(grid: ShipGrid, r: ShipBlueprint.PlacedRoom) -> String:
	var def: RoomDefinition = grid.catalog.rooms.get(r.def_id)
	return def.display_name if def != null else String(r.def_id)


static func _check_hatches(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	for h in bp.hatches:
		var d := h.b - h.a
		if absi(d.x) + absi(d.y) + absi(d.z) != 1:
			_add(report, Severity.ERROR, &"hatch_not_adjacent",
				"Hatch %s joins %s and %s, which are not neighbouring cells." % [h.id, _cell_text(h.a), _cell_text(h.b)], h.id)
			continue
		var ra: int = grid.room_at.get(h.a, -1)
		var rb: int = grid.room_at.get(h.b, -1)
		if ra < 0 or rb < 0:
			_add(report, Severity.ERROR, &"hatch_not_between_rooms",
				"Hatch %s must have a room on both sides (%s → %s)." % [h.id, _cell_text(h.a), _cell_text(h.b)], h.id)
		elif ra == rb:
			_add(report, Severity.ERROR, &"hatch_inside_room",
				"Hatch %s is inside room %s; hatches join two different rooms." % [h.id, bp.rooms[ra].id], h.id)


## Crew access: every room must be reachable from a command room via hatches.
static func _check_access(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	var start := -1
	for i in bp.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(bp.rooms[i].def_id)
		if def != null and def.role == &"command":
			start = i
			break
	if start < 0:
		_add(report, Severity.ERROR, &"no_command",
			"No command room (bridge): the ship cannot be piloted. Add a bridge.", "")
		return
	var links := {}
	for h in bp.hatches:
		var ra: int = grid.room_at.get(h.a, -1)
		var rb: int = grid.room_at.get(h.b, -1)
		if ra >= 0 and rb >= 0 and ra != rb:
			links.get_or_add(ra, []).append(rb)
			links.get_or_add(rb, []).append(ra)
	# Same-type rooms side by side are one space.
	for ra in grid.open_rooms:
		for rb in grid.open_rooms[ra]:
			links.get_or_add(ra, []).append(rb)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for j in links.get(i, []):
			if not seen.has(j):
				seen[j] = true
				queue.append(j)
	for i in bp.rooms.size():
		if not seen.has(i) and grid.catalog.rooms.has(bp.rooms[i].def_id):
			_add(report, Severity.WARNING, &"room_unreachable",
				"Room %s (%s) cannot be reached from the bridge: crew cannot get there to operate or repair it. Add a hatch." % [
					bp.rooms[i].id, _room_name(grid, bp.rooms[i])], bp.rooms[i].id)


# --- Equipment ----------------------------------------------------------------

## A main engine off the aft face is fed from an engine room behind it.
const ENGINE_ROOM_ID := &"engine_room"


static func _check_equipment(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	var mounts := {}  # "cell|face" -> equipment id
	for i in bp.equipment.size():
		var e := bp.equipment[i]
		var def := grid.equipment_def(i)
		if def == null:
			continue
		if def.is_external():
			if not def.allowed_faces.has(e.face):
				_add(report, Severity.ERROR, &"equipment_bad_face",
					"%s %s cannot mount on a %s face (allowed: %s)." % [def.display_name, e.id, e.face,
						", ".join(def.allowed_faces.map(func(f: StringName) -> String: return String(f)))], e.id)
			else:
				for cell in grid.external_cells(i):
					if not grid.is_exterior_face(cell, e.face):
						_add(report, Severity.ERROR, &"equipment_not_exterior",
							"%s %s must sit on an exterior hull face; the %s face of %s is %s." % [def.display_name, e.id,
								e.face, _cell_text(cell), "not hull" if not grid.is_hull(cell) else "covered by another module"], e.id)
						break
					if grid.slope_faces(cell).has(e.face):
						_add(report, Severity.ERROR, &"equipment_on_slope",
							"%s %s is on the sloped face of a wedge at %s: systems need a flat face. Put it on a block." % [
								def.display_name, e.id, _cell_text(cell)], e.id)
						break
				for cell in grid.fin_cells(i):
					if grid.is_hull(cell):
						_add(report, Severity.ERROR, &"fin_blocked",
							"%s %s stands out %d cells from its face as a fin; the hull at %s is in the way." % [
								def.display_name, e.id, def.length_cells, _cell_text(cell)], e.id)
						break
				if def.kind == EquipmentDefinition.Kind.MAIN_ENGINE and e.face != &"aft":
					var room: int = grid.room_at.get(e.cell, -1)
					if room < 0 or bp.rooms[room].def_id != ENGINE_ROOM_ID:
						_add(report, Severity.ERROR, &"engine_needs_engine_room",
							"%s %s on a %s face needs an engine room on the inside of that cell (aft faces don't)." % [
								def.display_name, e.id, e.face], e.id)
			for cell in grid.external_cells(i):
				var key := "%s|%s" % [cell, e.face]
				if mounts.has(key):
					_add(report, Severity.ERROR, &"equipment_overlap",
						"%s and %s are mounted on the same face." % [mounts[key], e.id], e.id)
				mounts[key] = e.id
			continue
		# Internal: whole footprint inside one room of an allowed role.
		var room_index := -2
		for cell in grid.equipment_cells(i):
			var r: int = grid.room_at.get(cell, -1)
			room_index = r if room_index == -2 else (room_index if room_index == r else -1)
		if room_index < 0:
			_add(report, Severity.ERROR, &"equipment_outside_room",
				"%s %s must fit entirely inside one room." % [def.display_name, e.id], e.id)
			continue
		var room := bp.rooms[room_index]
		var room_def: RoomDefinition = grid.catalog.rooms.get(room.def_id)
		if room_def != null and not def.allowed_room_roles.has(room_def.role):
			_add(report, Severity.ERROR, &"equipment_wrong_room",
				"%s %s cannot be installed in %s (%s); it needs a room with role: %s." % [def.display_name, e.id,
					room.id, room_def.display_name,
					", ".join(def.allowed_room_roles.map(func(r: StringName) -> String: return String(r)))], e.id)
	var reported := {}
	for o in grid.equipment_overlaps:
		var key := "%d-%d" % [o[1], o[2]]
		if not reported.has(key):
			reported[key] = true
			_add(report, Severity.ERROR, &"equipment_overlap", "%s and %s overlap at %s." % [
				bp.equipment[o[1]].id, bp.equipment[o[2]].id, _cell_text(o[0])], bp.equipment[o[2]].id)


# --- Systems (warnings: trade-offs, not invalid designs) --------------------

static func _check_systems(bp: ShipBlueprint, grid: ShipGrid, stats: ShipStats, report: Report) -> void:
	if stats.power_draw_kw > stats.power_generation_kw:
		_add(report, Severity.WARNING, &"power_deficit",
			"Power deficit: systems draw %.0f kW but reactors supply %.0f kW. Add a reactor or remove loads." % [
				stats.power_draw_kw, stats.power_generation_kw], "")
	if stats.heat_generation_kw > stats.heat_rejection_kw:
		_add(report, Severity.WARNING, &"heat_deficit",
			"Heat deficit at full power: %.0f kW generated, %.0f kW rejected. Add radiators." % [
				stats.heat_generation_kw, stats.heat_rejection_kw], "")
	if stats.thrust_forward_n <= 0.0:
		_add(report, Severity.WARNING, &"no_main_engine",
			"No main engine on an aft face: only RCS thrust is available.", "")
	if stats.propellant_capacity_kg <= 0.0 and (stats.thrust_forward_n > 0.0 or stats.rcs_count > 0):
		_add(report, Severity.WARNING, &"no_propellant",
			"No propellant tanks: engines and RCS have nothing to burn. Add a propellant tank in a cargo hold or engineering room.", "")
	if stats.rcs_count == 0:
		_add(report, Severity.WARNING, &"no_rcs",
			"No RCS blocks: the ship cannot rotate or thrust sideways.", "")
	for axis in 3:
		var need := stats.thrust_misalignment_torque_nm[axis]
		var have := stats.torque_nm[axis]
		if need > 0.0 and need > MAX_THRUST_TORQUE_FRACTION * have:
			_add(report, Severity.WARNING, &"thrust_misaligned",
				"Main engines are off the centre of mass: full thrust needs %.0f%% of RCS %s authority to fly straight. Centre the engines or move mass." % [
					100.0 * need / maxf(have, 1.0), ["pitch", "yaw", "roll"][axis]], "")
			break
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or def.kind != EquipmentDefinition.Kind.CANNON:
			continue
		var e := bp.equipment[i]
		if _arc_obstructed(grid, e):
			_add(report, Severity.WARNING, &"weapon_arc_obstructed",
				"%s %s fires forward into its own hull. Mount it where nothing is ahead of it." % [def.display_name, e.id], e.id)
		if stats.rounds_capacity == 0:
			_add(report, Severity.WARNING, &"weapon_no_magazine",
				"%s %s has no magazine to feed it: 0 rounds. Add a magazine room." % [def.display_name, e.id], e.id)
	if stats.pd_gun != null and stats.pd_rounds_capacity == 0:
		_add(report, Severity.WARNING, &"pd_no_magazine",
			"Point defence draws its rounds from the magazine, and there is none: it can't fire. Add a magazine room.", "")


	if not bp.bus.is_empty():
		_check_bus(bp, grid, report)
	var buried := 0
	for key: String in bp.armor:
		var cf := ShipBlueprint.parse_plate_key(key)
		if not grid.plateable_faces(cf[0]).has(cf[1]):
			buried += 1
	if buried > 0:
		_add(report, Severity.WARNING, &"armor_buried",
			"%d armour plate%s on faces that are covered or not hull: dead weight. Repaint the armour." % [buried, "" if buried == 1 else "s"], "")
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def != null and def.kind == EquipmentDefinition.Kind.DOCKING_COLLAR and grid.room_at.get(bp.equipment[i].cell, -1) < 0:
			_add(report, Severity.WARNING, &"collar_leads_nowhere",
				"%s %s opens into no room: nobody can use it. Put a room behind it." % [def.display_name, bp.equipment[i].id], bp.equipment[i].id)


## Routed power: conduits only run through hull; every network with a
## reactor needs a distribution unit; every powered system should be on a
## network that has both.
static func _check_bus(bp: ShipBlueprint, grid: ShipGrid, report: Report) -> void:
	var outside := 0
	for key: String in bp.bus:
		if not grid.is_hull(ShipBlueprint.parse_cell_key(key)):
			outside += 1
	if outside > 0:
		_add(report, Severity.WARNING, &"bus_outside_hull",
			"%d power conduit cell%s outside the hull carry nothing." % [outside, "" if outside == 1 else "s"], "")
	var net_of := {}
	var nets := 0
	for key: String in bp.bus:
		if net_of.has(key) or not grid.is_hull(ShipBlueprint.parse_cell_key(key)):
			continue
		net_of[key] = nets
		var queue := [key]
		while not queue.is_empty():
			var cell := ShipBlueprint.parse_cell_key(queue.pop_front())
			for face: StringName in ShipGrid.FACE_NORMALS:
				var nk := ShipBlueprint.cell_key(cell + ShipGrid.FACE_NORMALS[face])
				if bp.bus.has(nk) and not net_of.has(nk):
					net_of[nk] = nets
					queue.append(nk)
		nets += 1
	var net_for := func(i: int) -> int:
		var def := grid.equipment_def(i)
		var cells: Array = [bp.equipment[i].cell] if def.is_external() else grid.equipment_cells(i)
		for c in cells:
			if net_of.has(ShipBlueprint.cell_key(c)):
				return net_of[ShipBlueprint.cell_key(c)]
		return -1
	var reactor_nets := {}
	var pdu_nets := {}
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null:
			continue
		var net: int = net_for.call(i)
		if def.kind == EquipmentDefinition.Kind.REACTOR and net >= 0:
			reactor_nets[net] = true
		elif def.kind == EquipmentDefinition.Kind.POWER_DISTRIBUTION and net >= 0:
			pdu_nets[net] = true
	for net in reactor_nets:
		if not pdu_nets.has(net):
			_add(report, Severity.WARNING, &"bus_no_distribution",
				"A bus network with a reactor has no power distribution unit: its reactor feeds nothing. Put a distribution unit on it.", "")
			break
	var unpowered := PackedStringArray()
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or def.power_kw >= 0.0:
			continue
		var net: int = net_for.call(i)
		if net < 0 or not reactor_nets.has(net) or not pdu_nets.has(net):
			unpowered.append(bp.equipment[i].id)
	if not unpowered.is_empty():
		_add(report, Severity.WARNING, &"power_unrouted",
			"%d system%s not on a powered bus network (%s%s): route a conduit to %s, or use Auto-route." % [unpowered.size(),
				"" if unpowered.size() == 1 else "s", ", ".join(unpowered.slice(0, 6)), "…" if unpowered.size() > 6 else "",
				"it" if unpowered.size() == 1 else "them"], unpowered[0])


## Fixed forward-firing mounts: anything in the hull straight ahead (−z) of
## the mount, in the cell layer just outside its face, blocks the line of fire.
static func _arc_obstructed(grid: ShipGrid, e: ShipBlueprint.PlacedEquipment) -> bool:
	var start: Vector3i = e.cell + ShipGrid.FACE_NORMALS.get(e.face, Vector3i.ZERO)
	var lo := int(floor(grid.cell_bounds().position.z))
	for z in range(start.z - 1, lo - 1, -1):
		if grid.is_hull(Vector3i(start.x, start.y, z)):
			return true
	return false
