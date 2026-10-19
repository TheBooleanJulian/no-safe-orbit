class_name CraftAI
extends RefCounted
## Flight and combat for autonomous craft (spec §11 "NPC-controlled
## fighters"): the player gives a directive; this turns it into stick and
## throttle for one tick. Same physics as every ship: it only produces a
## ShipControlInput.
##
## Directives:
##   INTERCEPT  engage the nearest hostile craft; none → screen the carrier
##   STRIKE     gun runs on the target ship, aiming at the chosen subsystem
##   RECON      hold station RECON_RANGE_M from the target, nose on it, never fire
##   ESCORT     fly a slot beside the carrier; engage hostile craft that close in
##   RETURN     fly to the rack and be recovered
## Disengage (risk tolerance): below these fractions of hull / propellant /
## ammunition the craft returns on its own — conservative early, aggressive
## late (DISENGAGE).

enum Directive { INTERCEPT, STRIKE, RECON, ESCORT, RETURN }
enum Risk { CONSERVATIVE, BALANCED, AGGRESSIVE }

const DIRECTIVE_NAMES := ["Intercept", "Strike", "Recon", "Escort", "Return"]
const RISK_NAMES := ["Conservative", "Balanced", "Aggressive"]
## Strike aim points: hull centre, or a subsystem kind.
const PRIORITY_NAMES := ["Hull", "Guns", "Engines", "Reactor"]
const PRIORITY_KINDS := [-1, EquipmentDefinition.Kind.CANNON, EquipmentDefinition.Kind.MAIN_ENGINE, EquipmentDefinition.Kind.REACTOR]
## [hull, propellant, ammunition] fractions below which a craft disengages.
const DISENGAGE := [[0.6, 0.4, 0.3], [0.35, 0.25, 0.1], [0.15, 0.1, 0.0]]

const STRIKE_RANGE_M := 600.0
const INTERCEPT_RANGE_M := 300.0
const RECON_RANGE_M := 1500.0
const ESCORT_OFFSET := Vector3(60, 25, 0)
## Formations: wingmen fan out by this angle around a target (radians) and
## escorts step out and back by this spacing (m) per rank.
const FORMATION_FAN_RAD := 0.45
const FORMATION_SPACING_M := 40.0
## Escorts break off to engage hostile craft within this range of the carrier.
const ESCORT_ENGAGE_M := 2500.0
## Position control: desired closing speed per metre of error (1/s), capped.
const POS_GAIN := 0.12
const MAX_CLOSING_MPS := 80.0
## Velocity control: reach the desired velocity in about this long (s).
const VEL_TAU_S := 1.5
const AIM_GAIN := 2.5


## Why a craft should break off ("" = it can carry on).
static func disengage_reason(craft: ShipState, risk: Risk) -> String:
	var limits: Array = DISENGAGE[risk]
	if craft.hull_fraction() < limits[0]:
		return "hull %d %%" % roundi(craft.hull_fraction() * 100.0)
	if not craft.config.unlimited_propellant and craft.config.propellant_capacity_kg > 0.0 \
			and craft.propellant_kg / craft.config.propellant_capacity_kg < limits[1]:
		return "propellant low"
	if craft.config.cannon != null and craft.config.cannon.magazine_rounds > 0 \
			and float(craft.cannon_rounds) / craft.config.cannon.magazine_rounds < limits[2]:
		return "ammunition low"
	return ""


## Fly towards `goal_pos` while matching `goal_vel` (world, local frame).
static func steer(craft: ShipState, goal_pos: Vector3, goal_vel: Vector3, input: ShipControlInput, max_closing: float = MAX_CLOSING_MPS) -> void:
	var closing := (goal_pos - craft.position) * POS_GAIN
	if closing.length() > max_closing:
		closing = closing.normalized() * max_closing
	var dv := goal_vel + closing - craft.velocity
	var body := craft.orientation.inverse() * dv
	var m := craft.mass_kg()
	var cfg := craft.config
	var ax := cfg.thrust_lateral_n / m
	var ay := cfg.thrust_vertical_n / m
	var az := (cfg.thrust_reverse_n if body.z > 0.0 else cfg.thrust_forward_n) / m
	input.translation = Vector3(
		clampf(body.x / maxf(ax * VEL_TAU_S, 1e-3), -1.0, 1.0),
		clampf(body.y / maxf(ay * VEL_TAU_S, 1e-3), -1.0, 1.0),
		clampf(body.z / maxf(az * VEL_TAU_S, 1e-3), -1.0, 1.0))


## Turn the nose towards a world direction (rate request for flight assist).
static func point(craft: ShipState, dir_world: Vector3, input: ShipControlInput) -> void:
	if dir_world.length_squared() < 1e-6:
		return
	var d := craft.orientation.inverse() * dir_world.normalized()
	var rates := craft.config.assist_max_rate_rad_s
	input.rotation = Vector3(
		clampf(AIM_GAIN * atan2(d.y, -d.z) / maxf(rates.x, 1e-3), -1.0, 1.0),
		clampf(AIM_GAIN * atan2(-d.x, -d.z) / maxf(rates.y, 1e-3), -1.0, 1.0),
		0.0)


## World point to aim at on `target`: the chosen subsystem if it still
## works, else the hull centre.
static func aim_point(target: ShipState, priority: int) -> Vector3:
	var body := target.config.hit_box_center
	if target.systems != null and priority > 0:
		for e in target.systems.equipment:
			if e.def.kind == PRIORITY_KINDS[priority] and not e.destroyed():
				body = e.body_position
				break
	return target.position + target.orientation * body


## Attack run on `target`: hold a standoff range, nose on the lead point,
## fire inside the gunnery cone.
static func attack(craft: ShipState, target: ShipState, standoff: float, priority: int, input: ShipControlInput, slot: int = 0) -> void:
	var away := craft.position - target.position
	if away.length() < 1.0:
		away = Vector3.UP
	if slot > 0:
		# Wingmen take their own approach: fanned out around the target.
		away = away.rotated(Vector3.UP, FORMATION_FAN_RAD * ((slot + 1) / 2) * (1.0 if slot % 2 == 1 else -1.0))
	steer(craft, target.position + away.normalized() * standoff, target.velocity, input)
	var cannon := craft.config.cannon
	if cannon == null:
		point(craft, target.position - craft.position, input)
		return
	var muzzle := craft.position + craft.orientation * craft.config.primary_muzzle()
	var rel_pos := aim_point(target, priority) - muzzle
	var rel_vel := target.velocity - craft.velocity
	var t := FireControl.intercept_time(rel_pos, rel_vel, cannon.muzzle_velocity_mps)
	var aim_dir := FireControl.lead_point(rel_pos, rel_vel, t) if t > 0.0 else rel_pos
	point(craft, aim_dir, input)
	var d := craft.orientation.inverse() * aim_dir.normalized()
	var error_deg := rad_to_deg(acos(clampf(-d.z, -1.0, 1.0)))
	input.fire = t > 0.0 and error_deg < GunneryAI.FIRE_CONE_DEG * 2.0 and rel_pos.length() < GunneryAI.MAX_RANGE_M


## One tick of a directive. `rack_point` / `rack_vel`: where the craft is
## recovered (world, local frame). `hostiles`: enemy craft, nearest first
## is chosen here.
static func command(craft: ShipState, directive: Directive, carrier: ShipState, rack_point: Vector3,
		target: ShipState, hostiles: Array[ShipState], priority: int, slot: int = 0) -> ShipControlInput:
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_translation = false
	var threat := _nearest(craft, hostiles)
	match directive:
		Directive.STRIKE:
			if target != null and target.is_active():
				attack(craft, target, STRIKE_RANGE_M, priority, input, slot)
				return input
			directive = Directive.RETURN
		Directive.INTERCEPT:
			if threat != null:
				attack(craft, threat, INTERCEPT_RANGE_M, 0, input, slot)
				return input
			directive = Directive.ESCORT
		Directive.RECON:
			if target != null and target.is_active():
				var away := craft.position - target.position
				if away.length() < 1.0:
					away = Vector3.UP
				steer(craft, target.position + away.normalized() * RECON_RANGE_M, target.velocity, input)
				point(craft, target.position - craft.position, input)
				return input
			directive = Directive.RETURN
	if directive == Directive.ESCORT:
		if carrier == null or not carrier.is_active():
			return input
		if threat != null and threat.position.distance_to(carrier.position) < ESCORT_ENGAGE_M:
			attack(craft, threat, INTERCEPT_RANGE_M, 0, input)
			return input
		var station := carrier.position + carrier.orientation * escort_offset(slot)
		steer(craft, station, carrier.velocity, input)
		point(craft, carrier.forward(), input)
		return input
	# RETURN: approach the rack, slowing as it closes.
	if carrier == null or not carrier.is_active():
		return input
	var to_rack := rack_point - craft.position
	steer(craft, rack_point, carrier.velocity, input, clampf(to_rack.length() * 0.2, 1.5, MAX_CLOSING_MPS))
	if to_rack.length() > 50.0:
		point(craft, to_rack, input)
	return input


## Escort station for formation slot `slot`: alternating sides, stepping
## back and out (body frame).
static func escort_offset(slot: int) -> Vector3:
	if slot == 0:
		return ESCORT_OFFSET
	var side := 1.0 if slot % 2 == 1 else -1.0
	var rank := float((slot + 1) / 2)
	return Vector3(ESCORT_OFFSET.x * (1.0 if side > 0.0 else -1.0) + side * FORMATION_SPACING_M * rank,
		ESCORT_OFFSET.y, ESCORT_OFFSET.z + FORMATION_SPACING_M * rank)


static func _nearest(craft: ShipState, ships: Array[ShipState]) -> ShipState:
	var best: ShipState
	for s in ships:
		if s != null and s.is_active() and (best == null or craft.position.distance_squared_to(s.position) < craft.position.distance_squared_to(best.position)):
			best = s
	return best
