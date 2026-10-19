class_name DockingLink
extends RefCounted
## A gangway between two ships (spec §9). EXTENDING: the gangway reaches
## out and mates (collar) or cuts in (hull); it fails if the ships drift out
## of range or apart too fast. SEALED: grapples hold the ships together —
## each tick their relative velocity is cancelled with equal and opposite
## impulses (momentum conserved) and the target turns with the attacker. If
## that takes more than MAX_HOLD_FORCE_N (a ship thrusting away), or the
## ports end up out of reach, the gangway tears: SEVERED.

enum State { EXTENDING, SEALED, SEVERED, RELEASED }

const MAX_HOLD_FORCE_N := 200_000.0
## Extending fails above this relative speed (m/s).
const EXTEND_BREAK_SPEED_MPS := 1.0

var attacker_id: StringName
var target_id: StringName
var a_port: Docking.Port
var b_port: Docking.Port
var state: State = State.EXTENDING
var progress_s: float = 0.0
var required_s: float = 0.0
var reason: String = ""


static func create(attacker: ShipState, a_port: Docking.Port, target: ShipState, b_port: Docking.Port) -> DockingLink:
	var link := DockingLink.new()
	link.attacker_id = attacker.id
	link.target_id = target.id
	link.a_port = a_port
	link.b_port = b_port
	link.required_s = Docking.COLLAR_SEAL_S if b_port.kind == &"collar" else Docking.HULL_CUT_S
	return link


func active() -> bool:
	return state == State.EXTENDING or state == State.SEALED


func sealed() -> bool:
	return state == State.SEALED


func port_range(a: ShipState, b: ShipState) -> float:
	return a_port.world_position(a).distance_to(b_port.world_position(b))


## Advance one tick. Returns a log line when the state changes ("" otherwise).
func step(a: ShipState, b: ShipState, dt: float) -> String:
	if not active():
		return ""
	if a == null or b == null or not a.is_active() or not b.is_active():
		return _sever("a ship is gone")
	if port_range(a, b) > Docking.GANGWAY_MAX_M * 1.05:
		return _sever("ports drifted out of gangway reach")
	if state == State.EXTENDING:
		if (b.velocity - a.velocity).length() > EXTEND_BREAK_SPEED_MPS:
			return _sever("relative speed too high while extending")
		progress_s += dt
		if progress_s < required_s:
			return ""
		state = State.SEALED
		_hold(a, b, dt, true)
		if b_port.kind == &"hull" and b.systems != null:
			var room := b_port.room
			b.systems.breach_room(room)
			b.config = b.systems.effective_config()
			return "Gangway cut into %s — the compartment vents" % b.systems.blueprint.rooms[room].id
		return "Gangway mated to collar %s and sealed" % b_port.equipment_id
	return _hold(a, b, dt, false)


## Grapples: cancel relative velocity, co-rotate. Severs if it takes too much force.
func _hold(a: ShipState, b: ShipState, dt: float, initial: bool) -> String:
	var ma := a.mass_kg()
	var mb := b.mass_kg()
	var dv := b.velocity - a.velocity
	var reduced := ma * mb / (ma + mb)
	if not initial and reduced * dv.length() / dt > MAX_HOLD_FORCE_N:
		return _sever("pulled apart (%.0f kN needed to hold)" % (reduced * dv.length() / dt / 1000.0))
	var j := dv * reduced
	a.velocity += j / ma
	b.velocity -= j / mb
	b.angular_velocity = b.orientation.inverse() * (a.orientation * a.angular_velocity)
	return ""


func release() -> void:
	if active():
		state = State.RELEASED
		reason = "released"


func _sever(why: String) -> String:
	state = State.SEVERED
	reason = why
	return "Gangway severed: %s" % why
