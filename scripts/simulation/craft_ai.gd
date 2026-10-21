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
##
## How each role flies them (ShipConfig.craft_role):
##   fighter      STRIKE as gun runs: close to 250 m firing, break away to
##                900 m off the target's flank, come round again; INTERCEPT
##                as a pursuit with the lead.
##   interceptor  goes for inbound missiles first (within 4 km of the
##                carrier), then hostile craft; fast and light.
##   bomber       STRIKE from long range: steady runs to 1.1 km with a heavy,
##                slow-firing cannon, then breaks away; avoids dogfights.
##   recon        never fires: holds station and watches (feeds scans).
##   ew           never fires: holds station between the carrier and the
##                threat, 1.2 km out, so its jamming covers the carrier.
## Every role: never fires with a friendly ship or craft in the line of fire
## (FRIENDLY_CLEARANCE_M), keeps apart from friendly craft (SEPARATION_M)
## and clear of hulls (HULL_CLEARANCE_M) — its steering adds an avoidance
## velocity.

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
## A beam holds fire until its line passes this close to the target's
## centre at the least (m) — or within its hit box's narrower half-width.
const BEAM_AIM_MIN_M := 0.3
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
## Hold fire with a friendly this close to the line of fire (m, beyond its hull).
const FRIENDLY_CLEARANCE_M := 25.0
## Avoidance: keep this far from friendly craft, and this far outside hulls.
const SEPARATION_M := 70.0
const HULL_CLEARANCE_M := 120.0
const AVOID_GAIN := 0.5
const MAX_AVOID_MPS := 60.0
## Gun runs: run-in range by role (m), break-away distance and time.
const RUN_IN_M := {&"fighter": 250.0, &"interceptor": 200.0, &"bomber": 1100.0}
const BREAK_M := 600.0
const BREAK_S := 6.0
## Gun runs are flown slowly (m/s): every reversal costs propellant.
const RUN_CLOSING_MPS := 40.0
## Interceptors take inbound missiles first within this of the carrier.
const MISSILE_SCREEN_M := 4000.0
## EW drones hold station this far from the carrier, towards the threat.
const EW_STATION_M := 1200.0
## What the role and directive mean, in a line each (shown in game).
const ROLE_HELP := {
	&"fighter": "Fighter: gun runs on ships (in to 250 m firing, break away, come round); dogfights craft",
	&"interceptor": "Interceptor: shoots down inbound missiles first, then hostile craft; fast, light gun",
	&"bomber": "Bomber: long steady runs on ships with a heavy cannon from 1.1 km, then breaks away",
	&"recon": "Recon drone: never fires; holds 1.5 km from the target and watches",
	&"ew": "EW drone: never fires; holds 1.2 km out towards the threat so its jamming covers your ship",
	&"repair": "Repair drone: patches damaged systems outside your hulls (guns, radiators, engines, sensors) to 75 %, your ship's first; no work → escorts",
	&"salvage": "Salvage drone: strips disabled hostiles and derelicts, a system every 4 s, into spare parts; brings 30 home at a time; no work → escorts",
}
const DIRECTIVE_HELP := [
	"Intercept: engage the nearest hostile craft (interceptors: missiles first); none → screen the ship",
	"Strike: attack the target ship (the chosen subsystem)",
	"Recon: hold station from the target, nose on it, never fire",
	"Escort: fly a slot beside your ship; engage hostiles that come within 2.5 km",
	"Return: fly home to the rack and be recovered",
]
const RISK_HELP := "Risk: when to come home on its own — Conservative early (60 % hull), Aggressive late (15 %)"

## Avoidance velocity for the craft being commanded (added by steer()).
static var _avoid := Vector3.ZERO


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
	# Whatever the risk: an empty gun is no use out there.
	if craft.config.cannon != null and craft.config.cannon.magazine_rounds > 0 and craft.cannon_rounds <= 0:
		return "out of ammunition"
	return ""


## Fly towards `goal_pos` while matching `goal_vel` (world, local frame).
static func steer(craft: ShipState, goal_pos: Vector3, goal_vel: Vector3, input: ShipControlInput, max_closing: float = MAX_CLOSING_MPS) -> void:
	var closing := (goal_pos - craft.position) * POS_GAIN
	if closing.length() > max_closing:
		closing = closing.normalized() * max_closing
	var dv := goal_vel + closing + _avoid - craft.velocity
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


## Turn any body axis towards a world direction (rate request for assist):
## the rotation that takes the axis onto the direction, as body rates.
static func point_axis(ship: ShipState, axis_body: Vector3, dir_world: Vector3, input: ShipControlInput) -> void:
	if dir_world.length_squared() < 1e-6:
		return
	var have := axis_body.normalized()
	var want := ship.orientation.inverse() * dir_world.normalized()
	var turn := have.cross(want)
	var angle := have.angle_to(want)
	if turn.length() < 1e-6:
		turn = have.cross(Vector3.UP if absf(have.y) < 0.9 else Vector3.RIGHT) if angle > 1.0 else Vector3.ZERO
	var rate := turn.normalized() * angle * AIM_GAIN if turn.length() > 1e-6 else Vector3.ZERO
	var rates := ship.config.assist_max_rate_rad_s
	input.rotation = Vector3(
		clampf(rate.x / maxf(rates.x, 1e-3), -1.0, 1.0),
		clampf(rate.y / maxf(rates.y, 1e-3), -1.0, 1.0),
		clampf(rate.z / maxf(rates.z, 1e-3), -1.0, 1.0))


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
## fire inside the gunnery cone (if no friendly is in the way).
static func attack(craft: ShipState, target: ShipState, standoff: float, priority: int, input: ShipControlInput, slot: int = 0,
		friends: Array[ShipState] = [], max_closing: float = MAX_CLOSING_MPS) -> void:
	var away := craft.position - target.position
	if away.length() < 1.0:
		away = Vector3.UP
	if slot > 0:
		# Wingmen take their own approach: fanned out around the target.
		away = away.rotated(Vector3.UP, FORMATION_FAN_RAD * ((slot + 1) / 2) * (1.0 if slot % 2 == 1 else -1.0))
	steer(craft, target.position + away.normalized() * standoff, target.velocity, input, max_closing)
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
	var in_reach := rel_pos.length() < GunneryAI.MAX_RANGE_M
	var on_aim := error_deg < GunneryAI.FIRE_CONE_DEG * 2.0
	if cannon.is_beam():
		# A beam has few charges and no spread: it fires only in reach and
		# with the line through the target's hit box (not near it).
		var r := target.config.hit_box_half_extents
		in_reach = rel_pos.length() < cannon.beam_range_m
		on_aim = sin(deg_to_rad(minf(error_deg, 90.0))) * rel_pos.length() < maxf(minf(r.x, r.y), BEAM_AIM_MIN_M)
		if target.systems == null:
			# Its steering mirror lays it on a craft or missile within
			# WorldSimulation.BEAM_STEER_DEG of the nose.
			on_aim = error_deg < WorldSimulation.BEAM_STEER_DEG * 0.8
		input.lead_target_id = target.id
	input.fire = t > 0.0 and on_aim and in_reach and clear_shot(craft, aim_dir, rel_pos.length(), friends, target)


## Gun runs on a ship: run in to the role's range firing, then break away
## off the target's flank for BREAK_S or BREAK_M, then come round again.
## State in craft.ai_state.
static func gun_run(craft: ShipState, target: ShipState, priority: int, input: ShipControlInput, slot: int,
		friends: Array[ShipState], dt: float) -> void:
	var st := craft.ai_state
	var run_in: float = RUN_IN_M.get(craft.config.craft_role, 250.0)
	var to_t := target.position - craft.position
	st.t = float(st.get("t", 0.0)) + dt
	if str(st.get("phase", "run")) == "run":
		attack(craft, target, run_in, priority, input, slot, friends, RUN_CLOSING_MPS)
		if to_t.length() <= run_in * 1.2:
			var side := to_t.cross(Vector3.UP if absf(to_t.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
			st.phase = "break"
			st.t = 0.0
			st.dir = side * (1.0 if slot % 2 == 0 else -1.0)
		return
	var break_point := target.position + (st.dir as Vector3) * BREAK_M - to_t.normalized() * 200.0
	steer(craft, break_point, target.velocity, input, RUN_CLOSING_MPS)
	point(craft, break_point - craft.position, input)
	input.fire = false
	if float(st.t) > BREAK_S or craft.position.distance_to(target.position) > BREAK_M * 0.9:
		st.phase = "run"


## No friendly ship or craft within FRIENDLY_CLEARANCE_M of the line of
## fire out to `range_m`.
static func clear_shot(craft: ShipState, aim_dir: Vector3, range_m: float, friends: Array[ShipState],
		target: ShipState = null) -> bool:
	if aim_dir.length_squared() < 1e-9:
		return true
	var dir := aim_dir.normalized()
	for f in friends:
		if f == craft or f == target or not f.is_active():
			continue
		var rel := f.position - craft.position
		var along := rel.dot(dir)
		if along <= 0.0 or along > range_m + 50.0:
			continue
		if (rel - dir * along).length() < f.config.hit_box_half_extents.length() + FRIENDLY_CLEARANCE_M:
			return false
	return true


## Velocity to add to keep apart from friendly craft and clear of hulls
## (friendly or not); `skip`: a ship it may approach (the carrier, landing).
const AVOID_EVERY := 4
## Within this of its rack on the way home a craft stops keeping apart.
const FINAL_APPROACH_M := 150.0


static func avoidance(craft: ShipState, friends: Array[ShipState], others: Array[ShipState], skip: ShipState = null) -> Vector3:
	var push := Vector3.ZERO
	for list: Array[ShipState] in [friends, others]:
		for s: ShipState in list:
			if s == craft or s == skip or s == null or not s.is_active():
				continue
			var rel := craft.position - s.position
			var d := rel.length()
			var hull := s.config.hit_box_half_extents.length()
			var margin := hull + (HULL_CLEARANCE_M if s.systems != null else SEPARATION_M)
			if s.systems == null and list == others:
				continue  # hostile craft: dogfights get close on purpose
			if d < margin and d > 1e-3:
				push += rel / d * (margin - d) * AVOID_GAIN
	return push.limit_length(MAX_AVOID_MPS)


## One tick of a directive. `rack_point` / `rack_vel`: where the craft is
## recovered (world, local frame). `hostiles`: enemy craft, nearest first
## is chosen here.
## `friends`: ships and craft of its side (never in the line of fire; craft
## kept apart). `missiles`: hostile missiles in flight (interceptors).
static func command(craft: ShipState, directive: Directive, carrier: ShipState, rack_point: Vector3,
		target: ShipState, hostiles: Array[ShipState], priority: int, slot: int = 0,
		friends: Array[ShipState] = [], missiles: Array[ShipState] = [], dt: float = 1.0 / 60.0) -> ShipControlInput:
	var others: Array[ShipState] = []
	if target != null:
		others.append(target)
	# Avoidance changes slowly: worked out every AVOID_EVERY ticks per craft
	# (staggered), kept in between (play-test batch 6: many fighters).
	var n := int(craft.ai_state.get("avoid_n", absi(hash(craft.id)) % AVOID_EVERY))
	if n <= 0:
		craft.ai_state["avoid"] = avoidance(craft, friends, others, carrier if directive == Directive.RETURN else null)
		n = AVOID_EVERY
	craft.ai_state["avoid_n"] = n - 1
	_avoid = craft.ai_state.get("avoid", Vector3.ZERO)
	# On final approach the rack wins: keeping 70 m from a wingman landing at
	# the next rack would hold both off for ever.
	if directive == Directive.RETURN and craft.position.distance_to(rack_point) < FINAL_APPROACH_M:
		_avoid = Vector3.ZERO
	var input := _command(craft, directive, carrier, rack_point, target, hostiles, priority, slot, friends, missiles, dt)
	_avoid = Vector3.ZERO
	return input


static func _command(craft: ShipState, directive: Directive, carrier: ShipState, rack_point: Vector3,
		target: ShipState, hostiles: Array[ShipState], priority: int, slot: int,
		friends: Array[ShipState], missiles: Array[ShipState], dt: float) -> ShipControlInput:
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_translation = false
	var role := craft.config.craft_role
	var threat := _nearest(craft, hostiles)
	# Interceptors take inbound missiles first.
	if role == &"interceptor" and directive in [Directive.INTERCEPT, Directive.ESCORT] and carrier != null:
		var best: ShipState = null
		for m in missiles:
			if m.is_active() and m.position.distance_to(carrier.position) < MISSILE_SCREEN_M \
					and (best == null or m.position.distance_to(carrier.position) < best.position.distance_to(carrier.position)):
				best = m
		if best != null:
			attack(craft, best, 150.0, 0, input, slot, friends)
			return input
	# EW drones hold a jamming station; recon and EW never fire.
	if role == &"ew" and directive != Directive.RETURN and carrier != null and carrier.is_active():
		var foe: ShipState = target if target != null and target.is_active() else threat
		var toward := (foe.position - carrier.position).normalized() if foe != null else carrier.forward()
		steer(craft, carrier.position + toward * EW_STATION_M + carrier.orientation * escort_offset(slot) * 0.2, carrier.velocity, input)
		point(craft, toward, input)
		return input
	match directive:
		Directive.STRIKE:
			if target != null and target.is_active():
				if role == &"recon":
					directive = Directive.RECON
				else:
					gun_run(craft, target, priority, input, slot, friends, dt)
					return input
			else:
				directive = Directive.RETURN
		Directive.INTERCEPT:
			if threat != null and role != &"bomber" and role != &"recon":
				attack(craft, threat, INTERCEPT_RANGE_M, 0, input, slot, friends)
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
		if threat != null and threat.position.distance_to(carrier.position) < ESCORT_ENGAGE_M and role != &"recon":
			attack(craft, threat, INTERCEPT_RANGE_M, 0, input, slot, friends)
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
