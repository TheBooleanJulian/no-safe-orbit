class_name GunneryAI
extends RefCounted
## Minimal enemy gunner: turn the nose onto the fire-control lead point with
## flight assist; turrets train on the lead point and fire when they are on
## it (fixed guns: when the nose is aligned), in range. It flies the same physics,
## thrust, torque and ammunition limits as the player (spec §11: the
## controller differs, the physical rules do not). No evasion or
## manoeuvring yet — directives and tactics arrive with Milestone 6.

## Requested turn rate per radian of aim error (1/s).
const AIM_GAIN := 2.0
const FIRE_CONE_DEG := 0.35
const MAX_RANGE_M := 6000.0


static func command(shooter: ShipState, target: ShipState) -> ShipControlInput:
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_translation = false  # hold its orbit; only turn
	var cfg := shooter.config
	if cfg.cannon == null or target == null or not target.is_active():
		return input
	var muzzle := shooter.position + shooter.orientation * cfg.primary_muzzle()
	var aim := target.position + target.orientation * target.config.hit_box_center
	var rel_pos := aim - muzzle
	var rel_vel := target.velocity - shooter.velocity
	var t := FireControl.intercept_time(rel_pos, rel_vel, cfg.cannon.muzzle_velocity_mps)
	if t < 0.0:
		return input
	var inv := shooter.orientation.inverse()
	var d := inv * FireControl.lead_point(rel_pos, rel_vel, t).normalized()
	var pitch_error := atan2(d.y, -d.z)  # + = target above the nose
	var yaw_error := atan2(-d.x, -d.z)   # + = target to the left
	# Feed-forward: the line of sight itself rotates at (r × v)/|r|². Turning
	# at that rate keeps the nose on a crossing target; the proportional term
	# only corrects what is left (a P-only controller would lag ~rate/gain).
	var los_rate := inv * (rel_pos.cross(rel_vel) / maxf(rel_pos.length_squared(), 1.0))
	var rates := cfg.assist_max_rate_rad_s
	input.rotation = Vector3(
		clampf((AIM_GAIN * pitch_error + los_rate.x) / maxf(rates.x, 1e-3), -1.0, 1.0),
		clampf((AIM_GAIN * yaw_error + los_rate.y) / maxf(rates.y, 1e-3), -1.0, 1.0),
		0.0)
	input.has_aim = true
	input.aim_offset = muzzle - shooter.position + FireControl.lead_point(rel_pos, rel_vel, t)
	input.lead_target_id = target.id
	if cfg.is_turret(0):
		input.fire = rel_pos.length() < MAX_RANGE_M  # each turret fires when it is on
		return input
	var error_deg := rad_to_deg(acos(clampf(-d.z, -1.0, 1.0)))
	input.fire = error_deg < FIRE_CONE_DEG and rel_pos.length() < MAX_RANGE_M
	return input


## Fighting range the enemy tries to keep (m), and when it gives up.
const KEEP_MIN_M := 1200.0
const KEEP_MAX_M := 3500.0
const FLEE_INTACT_FRACTION := 0.35
## Holds fire this close to the reactor's throttle temperature (K).
const HOLD_FIRE_MARGIN_K := 15.0
## How hard it works round to your stern while in your bow arc (thrust fraction).
const FLANK_BIAS := 0.5


## A fighting ship's whole command: the gun laying above, plus keeping to a
## fighting range, jinking across the line of fire so rounds aimed at where
## it was miss, holding fire to cool down before the reactor throttles,
## and running when beaten (`fleeing`).
static func combat(shooter: ShipState, target: ShipState, now: float, policy: ShipPolicy = null) -> ShipControlInput:
	var sys := shooter.systems
	var keep := policy.keep_range() if policy != null else Vector2(KEEP_MIN_M, KEEP_MAX_M)
	var flank := policy.flank_bias() if policy != null else FLANK_BIAS
	if should_flee(shooter):
		_set_pips(sys, [2, 4, 0])  # everything into the engines
		return flee(shooter, target)
	# Power: guns while healthy, back to balanced when hurt.
	# Balanced in a fight: its guns fire at the rated rate, as the player's do.
	_set_pips(sys, [2, 2, 2])
	var input := command(shooter, target)
	if target == null or not target.is_active():
		return input
	var inv := shooter.orientation.inverse()
	var rel := target.position - shooter.position
	var r := rel.length()
	var los := inv * (rel / maxf(r, 1.0))
	var t := Vector3.ZERO
	if r < keep.x:
		t -= los * 0.7
	elif r > keep.y:
		t += los * 0.7
	# Jink: a slow weave across the line of sight (phase from its name, so
	# two enemies don't weave in step).
	var side := los.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.1 else Vector3.RIGHT
	var up := side.cross(los).normalized()
	var phase := float(hash(String(shooter.id)) % 100) * 0.1
	t += side * sin(now * 0.7 + phase) * 0.8 + up * sin(now * 0.45 + phase * 2.0) * 0.5
	# Flank: work round towards the target's stern, out of its bow arc.
	var stern := target.position - target.forward() * (keep.x + keep.y) * 0.5
	var to_stern := inv * (stern - shooter.position)
	var across := to_stern - los * to_stern.dot(los)
	if target.forward().dot(shooter.position - target.position) > 0.0 and across.length() > 1.0:
		t += across.normalized() * flank
	input.translation = t.clamp(-Vector3.ONE, Vector3.ONE)
	input.hold_translation = false
	if sys != null and sys.temperature_k >= ShipSystems.THROTTLE_TEMP_K - HOLD_FIRE_MARGIN_K:
		input.fire = false
	if policy != null and not policy.allows_fire(true):
		input.fire = false
	if policy != null:
		input.fire_rate = policy.trigger_rate(false)
	return input


## Whom an enemy ship shoots at, among `candidates` (the player's ship, its
## craft, an escorted courier): never a derelict or anything out of the
## fight; with focus fire, the team's chosen prey while it's a candidate;
## otherwise the nearest.
static func choose_prey(shooter: ShipState, candidates: Array[ShipState], team_prey: ShipState, policy: ShipPolicy) -> ShipState:
	var live: Array[ShipState] = []
	for s in candidates:
		if s != null and s.is_active() and not s.derelict:
			live.append(s)
	if live.is_empty():
		return null
	if (policy == null or policy.focus_fire) and team_prey != null and live.has(team_prey):
		return team_prey
	var best := live[0]
	for s in live:
		if s.position.distance_squared_to(shooter.position) < best.position.distance_squared_to(shooter.position):
			best = s
	return best


## Set power pips [SYS, ENG, WEP] (only when they change).
static func _set_pips(sys: ShipSystems, want: Array) -> void:
	if sys == null or (sys.pips[0] == want[0] and sys.pips[1] == want[1] and sys.pips[2] == want[2]):
		return
	sys.pips.assign(want)
	sys.invalidate()


## Beaten but still able to run: most of its systems are gone.
static func should_flee(ship: ShipState) -> bool:
	var sys := ship.systems
	return sys != null and not sys.is_disabled() and sys.intact_fraction() < FLEE_INTACT_FRACTION \
		and ship.config.thrust_forward_n > 0.0 and ship.propellant_kg > 0.0


## Nose away from the threat and burn.
static func flee(ship: ShipState, threat: ShipState) -> ShipControlInput:
	var input := ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, true)
	input.hold_translation = false
	if threat != null:
		CraftAI.point(ship, ship.position - threat.position, input)
	return input


## Port gap a boarding approach closes to (m): inside the gangway's reach.
const DOCK_STANDOFF_M := 12.0


## Close in to board a beaten ship: our best collar turned square to its
## best port, held DOCK_STANDOFF_M off it at its velocity.
## `found` = an already-computed Docking.best(ship, target), if the caller has one.
static func dock_approach(ship: ShipState, target: ShipState, found: Dictionary = {}) -> ShipControlInput:
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_translation = false
	if found.is_empty():
		found = Docking.best(ship, target)
	if found.is_empty():
		return input
	var pa: Docking.Port = found.a_port
	var pb: Docking.Port = found.b_port
	CraftAI.point_axis(ship, pa.normal_body, -pb.world_normal(target), input)
	var goal_port := pb.world_position(target) + pb.world_normal(target) * DOCK_STANDOFF_M
	var gap := goal_port.distance_to(pa.world_position(ship))
	CraftAI.steer(ship, ship.position + (goal_port - pa.world_position(ship)), target.velocity, input, clampf(gap * 0.12, 0.3, 40.0))
	return input


## Whether `ship` would board `prey` now: the prey is beaten (disabled, not
## already taken), and we have a working collar and fit boarders.
static func wants_to_board(ship: ShipState, prey: ShipState) -> bool:
	if ship.systems == null or prey.systems == null or ship.systems.is_disabled() or ship.systems.captured:
		return false
	if not prey.systems.is_disabled() or prey.systems.captured or Docking.collars(ship.systems).is_empty():
		return false
	return ship.systems.crew != null and ship.systems.crew.members.any(func(m: CrewRoster.Member) -> bool:
		return m.available() and (m.role == CrewRoster.Role.SECURITY or m.role == CrewRoster.Role.GENERAL))


## A ship grappled by a gangway it didn't ask for thrusts straight away from
## the other ship to tear free (it can if it has the thrust and a crew in
## command; see DockingLink.MAX_HOLD_FORCE_N).
static func break_contact(ship: ShipState, other: ShipState) -> ShipControlInput:
	var away := ship.orientation.inverse() * (ship.position - other.position).normalized()
	var input := ShipControlInput.create(away / maxf(absf(away.x), maxf(absf(away.y), absf(away.z))), Vector3.ZERO, true)
	input.hold_translation = false
	return input


## Whether `ship` can still try to break contact.
static func can_break_contact(ship: ShipState) -> bool:
	var sys := ship.systems
	if sys == null:
		return true
	return not sys.captured and sys.power_supply_kw > 0.0 and sys.has_command() \
		and maxf(ship.config.thrust_lateral_n, ship.config.thrust_forward_n) > 0.0
