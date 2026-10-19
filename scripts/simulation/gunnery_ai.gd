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
	if cfg.is_turret(0):
		input.fire = rel_pos.length() < MAX_RANGE_M  # each turret fires when it is on
		return input
	var error_deg := rad_to_deg(acos(clampf(-d.z, -1.0, 1.0)))
	input.fire = error_deg < FIRE_CONE_DEG and rel_pos.length() < MAX_RANGE_M
	return input


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
