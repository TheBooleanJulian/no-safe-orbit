class_name Grapple
extends RefCounted
## The grappling arm: a manipulator on an external mount that grabs a ship
## alongside — typically a tumbling, disabled hulk no gangway could mate
## with. While HOLDING, every tick it:
##   - takes the target's tumble out (STABILISE_RAD_S2) until it turns with us;
##   - drags its velocity to ours (PULL_MPS2; momentum shared, like a gangway);
##   - if both ships have a docking collar: turns the target (ALIGN_RAD_S) so
##     its collar faces ours and reels it in to DOCK_GAP_M — then [V] mates;
##   - siphons propellant and rounds out of a disabled or captured hulk into
##     our tanks and magazines.
## It lets go if the target ends up out of reach, the arm is wrecked, or a
## ship is gone.

enum State { HOLDING, RELEASED, BROKEN }

## Arm to the target's hull (hit box), to grab and to keep hold (× 1.3).
const REACH_M := 60.0
const GRAB_MAX_REL_SPEED_MPS := 5.0
const STABILISE_RAD_S2 := 0.25
const PULL_MPS2 := 1.5
const ALIGN_RAD_S := 0.15
## Collar-to-collar gap the arm reels a hulk in to (inside gangway reach).
const DOCK_GAP_M := 10.0
const REEL_MPS := 1.0
const SIPHON_PROPELLANT_KG_S := 400.0
const SIPHON_ROUNDS_S := 20.0

var attacker_id: StringName
var target_id: StringName
var arm_id: String
var state: State = State.HOLDING
var reason: String = ""
var siphoned_kg: float = 0.0
var siphoned_rounds: int = 0
## Set once the hulk is steady (and lined up, with collars): logged once.
var steady: bool = false
var _round_accum := 0.0


## Working grappling arms on a ship.
static func arms(systems: ShipSystems) -> Array[ShipSystems.EquipmentState]:
	var out: Array[ShipSystems.EquipmentState] = []
	if systems == null:
		return out
	for e in systems.equipment:
		if e.def.kind == EquipmentDefinition.Kind.GRAPPLE and e.working():
			out.append(e)
	return out


static func arm_position(ship: ShipState, e: ShipSystems.EquipmentState) -> Vector3:
	return ship.position + ship.orientation * e.body_position


## Distance from a world point to ship `b`'s hull box (0 inside it).
static func gap_to(b: ShipState, point: Vector3) -> float:
	var local := b.orientation.inverse() * (point - b.position) - b.config.hit_box_center
	var h := b.config.hit_box_half_extents
	var nearest := Vector3(clampf(local.x, -h.x, h.x), clampf(local.y, -h.y, h.y), clampf(local.z, -h.z, h.z))
	return local.distance_to(nearest)


## Where arm `arm_id` of `a` grips `b`: the point of `b`'s hull box nearest
## the arm (world), for the views.
static func grip_point(a: ShipState, b: ShipState, arm_id: String) -> Vector3:
	var e := a.systems.equipment_by_id(arm_id) if a.systems != null else null
	var from := arm_position(a, e) if e != null else a.position
	var local := b.orientation.inverse() * (from - b.position) - b.config.hit_box_center
	var h := b.config.hit_box_half_extents
	var nearest := Vector3(clampf(local.x, -h.x, h.x), clampf(local.y, -h.y, h.y), clampf(local.z, -h.z, h.z))
	return b.position + b.orientation * (nearest + b.config.hit_box_center)


## The arm nearest to `b`, or null.
static func nearest_arm(a: ShipState, b: ShipState) -> ShipSystems.EquipmentState:
	var best: ShipSystems.EquipmentState
	var best_gap := INF
	for e in arms(a.systems):
		var g := gap_to(b, arm_position(a, e))
		if g < best_gap:
			best_gap = g
			best = e
	return best


## Why `a` can't grab `b` now ("" = it can).
static func block_reason(a: ShipState, b: ShipState) -> String:
	if b == null or not b.is_active():
		return "nothing to grab"
	var arm := nearest_arm(a, b)
	if arm == null:
		return "no working grappling arm"
	var gap := gap_to(b, arm_position(a, arm))
	if gap > REACH_M:
		return "out of reach (%.0f m > %.0f m from the arm)" % [gap, REACH_M]
	var rel := (b.velocity - a.velocity).length()
	if rel > GRAB_MAX_REL_SPEED_MPS:
		return "closing too fast (%.1f m/s > %.0f m/s)" % [rel, GRAB_MAX_REL_SPEED_MPS]
	return ""


static func grab(a: ShipState, b: ShipState) -> Grapple:
	if block_reason(a, b) != "":
		return null
	var g := Grapple.new()
	g.attacker_id = a.id
	g.target_id = b.id
	g.arm_id = nearest_arm(a, b).id
	return g


func holding() -> bool:
	return state == State.HOLDING


func release() -> void:
	if holding():
		state = State.RELEASED
		reason = "released"


## Advance one tick. Returns a log line when something worth saying happens.
func step(a: ShipState, b: ShipState, dt: float) -> String:
	if not holding():
		return ""
	if a == null or b == null or not a.is_active() or not b.is_active():
		return _break("a ship is gone")
	var arm := a.systems.equipment_by_id(arm_id) if a.systems != null else null
	if arm == null or not arm.working():
		return _break("the arm is out of action")
	if gap_to(b, arm_position(a, arm)) > REACH_M * 1.3:
		return _break("the target pulled out of reach")
	# Tumble out: the target's spin goes to ours.
	var wa := a.orientation * a.angular_velocity
	var wb := b.orientation * b.angular_velocity
	wb = wa + (wb - wa).limit_length(maxf((wb - wa).length() - STABILISE_RAD_S2 * dt, 0.0))
	b.angular_velocity = b.orientation.inverse() * wb
	var spin_out := (wb - wa).length() < 0.01
	# Line a collar up with ours and reel it in, once it has stopped tumbling.
	var want_rel := Vector3.ZERO
	var aligned := true
	var ports := _collar_pair(a, b)
	if spin_out and not ports.is_empty():
		var pa: Docking.Port = ports[0]
		var pb: Docking.Port = ports[1]
		var na := pa.world_normal(a)
		var nb := pb.world_normal(b)
		var angle := nb.angle_to(-na)
		if angle > 1e-3:
			var axis := nb.cross(-na)
			if axis.length() < 1e-6:
				axis = na.cross(Vector3.UP if absf(na.y) < 0.9 else Vector3.RIGHT)
			b.orientation = (Quaternion(axis.normalized(), minf(angle, ALIGN_RAD_S * dt)) * b.orientation).normalized()
		aligned = angle < deg_to_rad(Docking.MAX_MISALIGN_DEG * 0.5)
		if aligned:
			var error := (pa.world_position(a) + na * DOCK_GAP_M) - pb.world_position(b)
			want_rel = (error * 0.2).limit_length(REEL_MPS)
			aligned = error.length() < 2.0
	# Velocity: pulled toward ours (plus the reel), momentum shared.
	var dv := (b.velocity - a.velocity) - want_rel
	var change := dv.limit_length(PULL_MPS2 * dt)
	var ma := a.mass_kg()
	var mb := b.mass_kg()
	b.velocity -= change * ma / (ma + mb)
	a.velocity += change * mb / (ma + mb)
	var line := ""
	if b.systems != null and (b.systems.is_disabled() or b.systems.captured):
		line = _siphon(a, b, dt)
	if not steady and spin_out and aligned and (b.velocity - a.velocity).length() < Docking.MAX_REL_SPEED_MPS:
		steady = true
		return "Grappling arm: %s steady%s" % [b.display_name, " and lined up — [V] gangway" if not ports.is_empty() else ""]
	return line


## Our working collar and theirs that are closest, [ours, theirs] or [].
func _collar_pair(a: ShipState, b: ShipState) -> Array:
	var best := []
	var best_d := INF
	for pa in Docking.collars(a.systems):
		for pb in Docking.collars(b.systems, false):
			var d := pa.world_position(a).distance_to(pb.world_position(b))
			if d < best_d:
				best_d = d
				best = [pa, pb]
	return best


func _siphon(a: ShipState, b: ShipState, dt: float) -> String:
	if not a.config.unlimited_propellant:
		var kg := minf(SIPHON_PROPELLANT_KG_S * dt, minf(b.propellant_kg, a.config.propellant_capacity_kg - a.propellant_kg))
		if kg > 0.0:
			b.propellant_kg -= kg
			a.propellant_kg += kg
			siphoned_kg += kg
	if a.config.cannon != null:
		_round_accum += SIPHON_ROUNDS_S * dt
		var room := a.config.cannon.magazine_rounds - a.cannon_rounds
		var n := mini(floori(_round_accum), room)
		if n > 0:
			_round_accum -= n
			var got := b.draw_rounds(n)
			if got > 0:
				a.set_rounds(a.cannon_rounds + got)
				siphoned_rounds += got
	return ""


func _break(why: String) -> String:
	state = State.BROKEN
	reason = why
	return "Grappling arm lost hold: %s" % why
