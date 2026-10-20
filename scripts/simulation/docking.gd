class_name Docking
extends RefCounted
## Physical connection between two ships for boarding (spec §9 "Connection
## requirements"). The attacker extends a gangway from one of its docking
## collars to either a docking collar on the target (quick to seal) or any
## outer face of the target's hull that has a room behind it (the gangway
## cuts in: slow, and that room vents).
##
## Tolerances, measured port to port:
##   range ≤ GANGWAY_MAX_M; relative speed ≤ MAX_REL_SPEED_MPS;
##   relative turn rate ≤ MAX_REL_RATE_RAD_S; the gangway leaves the collar
##   within MAX_MISALIGN_DEG of its axis and meets the target face within
##   MAX_MISALIGN_DEG of square.

const GANGWAY_MAX_M := 25.0
const MAX_REL_SPEED_MPS := 0.5
const MAX_REL_RATE_RAD_S := 0.06
const MAX_MISALIGN_DEG := 20.0
const COLLAR_SEAL_S := 10.0
const HULL_CUT_S := 45.0


## A place a gangway can attach: body-frame point on the hull surface and
## outward normal, and the room it opens into.
class Port:
	## &"collar" or &"hull".
	var kind: StringName
	var position_body: Vector3
	var normal_body: Vector3
	var room: int
	## Collar equipment id ("" for a hull face).
	var equipment_id: String = ""

	func world_position(ship: ShipState) -> Vector3:
		return ship.position + ship.orientation * position_body

	func world_normal(ship: ShipState) -> Vector3:
		return ship.orientation * normal_body


## Docking collars that open into a room. Ours must work (powered) to extend
## a gangway; the target's need only be intact to be mated to.
static func collars(systems: ShipSystems, need_power: bool = true) -> Array[Port]:
	var out: Array[Port] = []
	if systems == null:
		return out
	for e in systems.equipment:
		if e.def.kind != EquipmentDefinition.Kind.DOCKING_COLLAR or e.destroyed() or (need_power and not e.powered):
			continue
		var placed := systems.blueprint.equipment[e.index]
		var room: int = systems.grid.room_at.get(placed.cell, -1)
		if room < 0:
			continue
		var p := Port.new()
		p.kind = &"collar"
		p.position_body = e.body_position
		p.normal_body = Vector3(ShipGrid.FACE_NORMALS[placed.face])
		p.room = room
		p.equipment_id = e.id
		out.append(p)
	return out


## Every outer hull face with a room behind it (where a gangway can cut in).
## Cached per ship (they depend on its blueprint only).
static func hull_ports(systems: ShipSystems) -> Array[Port]:
	var out: Array[Port] = []
	if systems.hull_port_cached:
		out.assign(systems.hull_port_cache)
		return out
	var grid := systems.grid
	var c := ShipGrid.CELL_SIZE_M
	for cell: Vector3i in grid.room_at:
		for face: StringName in ShipGrid.FACE_NORMALS:
			var n: Vector3i = ShipGrid.FACE_NORMALS[face]
			if grid.is_hull(cell + n):
				continue
			var p := Port.new()
			p.kind = &"hull"
			p.position_body = ShipGrid.cell_center_m(cell) + Vector3(n) * c * 0.5 - systems.stats.center_of_mass_m
			p.normal_body = Vector3(n)
			p.room = grid.room_at[cell]
			out.append(p)
	systems.hull_port_cache = out.duplicate()
	systems.hull_port_cached = true
	return out


## Measures one attacker port against one target port.
## {ok, range, rel_speed, rel_rate, misalign_deg, problems: PackedStringArray}
static func assess(a: ShipState, a_port: Port, b: ShipState, b_port: Port) -> Dictionary:
	var pa := a_port.world_position(a)
	var pb := b_port.world_position(b)
	var na := a_port.world_normal(a)
	var nb := b_port.world_normal(b)
	var d := pb - pa
	var range_m := d.length()
	var axis := d / range_m if range_m > 1e-6 else na
	var out_angle := rad_to_deg(na.angle_to(axis))
	var face_angle := rad_to_deg(nb.angle_to(-na))
	var misalign := maxf(out_angle, face_angle)
	var rel_speed := (b.velocity - a.velocity).length()
	var rel_rate := (a.orientation * a.angular_velocity - b.orientation * b.angular_velocity).length()
	var problems := PackedStringArray()
	if range_m > GANGWAY_MAX_M:
		problems.append("range %.0f m > %.0f m" % [range_m, GANGWAY_MAX_M])
	if rel_speed > MAX_REL_SPEED_MPS:
		problems.append("relative speed %.2f m/s > %.1f m/s" % [rel_speed, MAX_REL_SPEED_MPS])
	if rel_rate > MAX_REL_RATE_RAD_S:
		problems.append("relative turn rate %.1f°/s > %.1f°/s" % [rad_to_deg(rel_rate), rad_to_deg(MAX_REL_RATE_RAD_S)])
	if misalign > MAX_MISALIGN_DEG:
		problems.append("misaligned %.0f° > %.0f°" % [misalign, MAX_MISALIGN_DEG])
	return {"ok": problems.is_empty(), "range": range_m, "rel_speed": rel_speed, "rel_rate": rel_rate,
		"misalign_deg": misalign, "problems": problems}


## The best gangway connection from `a` to `b`: an acceptable one if any
## (target collars preferred, then the nearest hull face), else the closest
## attempt. {a_port, b_port, assessment} or {} if `a` has no collar.
static func best(a: ShipState, b: ShipState) -> Dictionary:
	var mine := collars(a.systems)
	if mine.is_empty() or b.systems == null:
		return {}
	var theirs := collars(b.systems, false)
	theirs.append_array(hull_ports(b.systems))
	# Rank every pair on range and alignment alone (relative speed and turn
	# rate are the same for every pair), then assess the winner in full —
	# the same choice as assessing every pair, without building hundreds of
	# problem lists.
	var best_score := INF
	var best_pair: Array = []
	for pa in mine:
		var pa_w := pa.world_position(a)
		var na := pa.world_normal(a)
		for pb in theirs:
			var d := pb.world_position(b) - pa_w
			var range_m := d.length()
			var axis := d / range_m if range_m > 1e-6 else na
			var misalign := maxf(rad_to_deg(na.angle_to(axis)), rad_to_deg(pb.world_normal(b).angle_to(-na)))
			var pair_ok := range_m <= GANGWAY_MAX_M and misalign <= MAX_MISALIGN_DEG
			# Acceptable beats unacceptable; a collar beats a hull cut; then range and alignment.
			var score: float = (0.0 if pair_ok else 1e6) + (0.0 if pb.kind == &"collar" else 1e3) + range_m + misalign
			if score < best_score:
				best_score = score
				best_pair = [pa, pb]
	if best_pair.is_empty():
		return {}
	return {"a_port": best_pair[0], "b_port": best_pair[1], "assessment": assess(a, best_pair[0], b, best_pair[1])}
