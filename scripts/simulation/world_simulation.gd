class_name WorldSimulation
extends RefCounted
## Owns the authoritative simulation and its fixed-timestep clock.
## Frame rate never changes simulation results: `advance()` only decides how
## many fixed `step()`s to run and returns a render interpolation factor.
##
## Without a central body the local space is inertial (Milestone 1a sandbox).
## With one (`set_central_body`), everything lives in a free-falling
## LocalFrame and feels two-body gravity; see local_frame.gd.

const DEFAULT_FIXED_DT := 1.0 / 60.0
## Cap on catch-up steps per frame, so a long stall cannot snowball.
## At most this many ticks per frame: under a heavy load the fight runs a
## little slower than real time instead of the frame rate collapsing while
## the simulation chases its own tail (play-test batch 6). 3 keeps real time
## down to 20 fps.
const MAX_STEPS_PER_ADVANCE := 3
const FAST_FORWARD_STEPS := 8
const _ACCUMULATOR_EPSILON := 1e-9
## Re-centre the local frame on the anchor ship beyond this offset. Keeps
## 32-bit local positions at sub-millimetre resolution.
const REBASE_DISTANCE_M := 5000.0
## Rounds beyond FAR_RADIUS_M of the frame origin coast analytically; they
## come back to local integration inside NEAR_RADIUS_M (hysteresis).
const FAR_RADIUS_M := 80_000.0
const NEAR_RADIUS_M := 60_000.0
## Each far round is re-checked this often (s, simulated).
const FAR_CHECK_INTERVAL_S := 1.0
## Far rounds tracked at most (oldest dropped first).
const MAX_FAR_ROUNDS := 5000
## Far rounds farther than this many planet radii and receding are gone.
const ESCAPE_RADII := 30.0
## Without a planet there is no orbit to come back on: drop rounds this far out.
const INERTIAL_MAX_RANGE_M := 200_000.0
## A round cannot hit its own ship until it has flown this long (s).
const ARM_TIME_S := 1.0
## A ricochet keeps this fraction of its speed relative to the ship it hit.
const RICOCHET_KEEP := 0.55
## Turrets: a gun fires once its barrel is this close to the aim (degrees);
## it can depress this far below its face plane (sine).
const TURRET_READY_DEG := 0.3
const TURRET_ARC_MIN_DOT := -0.1
## The barrel sits this far off its hull face (m).
const TURRET_HEIGHT_M := 1.0
## Collisions: restitution, the closing speed below which nothing breaks
## (m/s), and structure points of damage per joule of impact energy.
const COLLISION_RESTITUTION := 0.2
const COLLISION_DAMAGE_MIN_MPS := 1.0
## Ramming (play-test: "more damage to both parties, more so on the lighter
## armoured / lower mass ship"): damage per joule of the collision's energy,
## how sharply toughness (mass × local armour) decides who takes it (the
## share goes as toughness^-COLLISION_SPLIT_POWER), and how far from the
## contact (m) the blow spreads through the hull.
const COLLISION_POINTS_PER_J := 3.0 / 100_000.0
const COLLISION_SPLIT_POWER := 1.5
const COLLISION_SPREAD_M := 9.0  # three cells: reaches the next module of a 2-cell block

var fixed_dt: float = DEFAULT_FIXED_DT
var tick: int = 0
var sim_time: float = 0.0
## Real time discarded because a frame needed more than MAX_STEPS_PER_ADVANCE.
var dropped_time: float = 0.0

## Central body, or null for inertial free space.
var body: OrbitalBody
var frame: LocalFrame
## Ship the local frame re-centres on (normally the player); empty = never.
var anchor_id: StringName = &""
## Rebase offset for the no-body case (the frame tracks its own otherwise).
var _inertial_rebase_offset := Vec3d.new()

var _accumulator: float = 0.0
var _ships: Dictionary = {}  # StringName -> ShipState
var _inputs: Dictionary = {}  # StringName -> ShipControlInput
var _ship_order: Array[StringName] = []  # deterministic update order
var _neutral_input := ShipControlInput.neutral()
var _rounds: Array[ProjectileState] = []
var _far_rounds: Array[ProjectileState] = []
var _far_cursor: int = 0
## Rounds that went through a ship this tick and fly on beyond it.
var _continuing: Array[ProjectileState] = []
var _next_round_id: int = 1
var _hit_events: Array[HitEvent] = []
## Gangways and boardings (spec §9), in creation order.
var links: Array[DockingLink] = []
## Grappling arms holding on to another ship.
var grapples: Array[Grapple] = []
## Missiles in flight (also in the ship table, so rounds and point defence
## can hit them).
var missiles: Array[ShipState] = []
var _next_missile_id := 1
## Warhead bursts since the last take_bursts(): {ship_id, point_body, radius, kind}.
var _bursts: Array[Dictionary] = []
## How far a guided missile leads (zero-effort-miss navigation constant).
const NAV_GAIN := 3.0
## Countermeasures (Milestone 11).
## Flares in flight: {id, side, owner, position, velocity, age, life, signature}.
var decoys: Array[Dictionary] = []
var _next_decoy_id := 1
## Decoys each missile has already weighed (missile id -> {decoy id: true}).
var _seen_decoys: Dictionary = {}
## A flare leaves its tube at this speed (m/s), fanned around the launcher's face.
const DECOY_EJECT_MPS := 35.0
const DECOY_CYCLE_S := 1.5
## Jamming does nothing inside BURN_THROUGH_M and is at full effect beyond
## JAM_FULL_M (the noise drowns the echo only at range).
const BURN_THROUGH_M := 3000.0
const JAM_FULL_M := 6000.0
## Chance a fully jammed missile loses lock, per second of flight.
const JAM_LOCK_LOSS_PER_S := 0.1
## An EW drone's noise covers ships of its side within this.
const EW_ESCORT_M := 3000.0
const LOST_SELF_DESTRUCT_S := 3.0
var boardings: Array[BoardingAction] = []
## Air wings (autonomous craft): updated at the start of every tick.
var wings: Array[AirWing] = []
var _link_events: PackedStringArray = PackedStringArray()
## Deterministic spread for turret dispersion.
var _rng := RandomNumberGenerator.new()
## Collision pairs in contact last tick ("a|b"), so one impact reports once.
var _contacts := {}


func _init(p_fixed_dt: float = DEFAULT_FIXED_DT) -> void:
	assert(p_fixed_dt > 0.0)
	fixed_dt = p_fixed_dt
	_rng.seed = 20261019


## Puts the engagement in orbit: the local frame origin starts at this PCI
## state. Ships added afterwards are placed relative to it.
func set_central_body(p_body: OrbitalBody, origin_position: Vec3d, origin_velocity: Vec3d) -> void:
	var problems := p_body.validate()
	assert(problems.is_empty(), "Invalid OrbitalBody: %s" % ", ".join(problems))
	body = p_body
	frame = LocalFrame.create(p_body, origin_position, origin_velocity)


func add_ship(state: ShipState) -> void:
	assert(not _ships.has(state.id), "Duplicate ship id: %s" % state.id)
	var problems := state.config.validate()
	assert(problems.is_empty(), "Invalid ShipConfig for %s: %s" % [state.id, ", ".join(problems)])
	_ships[state.id] = state
	_ship_order.append(state.id)
	_ship_order.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


## Take a ship out of the simulation (salvaged wrecks). Its rounds fly on;
## its gangways are released.
func remove_ship(id: StringName) -> void:
	for link in links:
		if link.attacker_id == id or link.target_id == id:
			link.release()
	for g in grapples:
		if g.attacker_id == id or g.target_id == id:
			g.release()
	missiles = missiles.filter(func(x: ShipState) -> bool: return x.id != id)
	boardings = boardings.filter(func(b: BoardingAction) -> bool: return b.link.attacker_id != id and b.link.target_id != id)
	_ships.erase(id)
	_inputs.erase(id)
	_ship_order.erase(id)


## Keep a beaten ship in the world as a derelict under `new_id`, with its
## craft (re-keyed under the same prefix, so a new ship can take the old
## id): gangways and grapples on it let go, boardings end, its wing stops
## flying, missiles it fired or that chase it keep their owner and quarry
## under the new ids. Returns the wreck (null if `id` isn't there).
func retire_ship(id: StringName, new_id: StringName) -> ShipState:
	var ship := get_ship(id)
	if ship == null:
		return null
	for link in links:
		if link.attacker_id == id or link.target_id == id:
			link.release()
	for g in grapples:
		if g.attacker_id == id or g.target_id == id:
			g.release()
	boardings = boardings.filter(func(b: BoardingAction) -> bool: return b.link.attacker_id != id and b.link.target_id != id)
	var prefix := String(id) + "_"
	var renames := {id: new_id}
	for sid in _ship_order:
		if String(sid).begins_with(prefix):
			renames[sid] = StringName(String(new_id) + "_" + String(sid).substr(prefix.length()))
	for old: StringName in renames:
		var s: ShipState = _ships[old]
		_ships.erase(old)
		_inputs.erase(old)
		_ship_order.erase(old)
		s.id = renames[old]
		s.derelict = s.missile == null
		_ships[s.id] = s
		_ship_order.append(s.id)
	_ship_order.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for m in missiles:
		m.missile_owner = renames.get(m.missile_owner, m.missile_owner)
		m.missile_target = renames.get(m.missile_target, m.missile_target)
	for w in wings.duplicate():
		if w.carrier_id == id:
			w.carrier_id = new_id
			for c in w.crafts:
				c.id = renames.get(c.id, c.id)
			wings.erase(w)
	return ship


## The extending or sealed gangway involving ship `id`, or null.
func link_for(id: StringName) -> DockingLink:
	for link in links:
		if link.active() and (link.attacker_id == id or link.target_id == id):
			return link
	return null


## Fire from `shooter_id`'s next ready launcher (of `warhead`, -1 any) at
## `target_id`: one missile, or a saturation pod's swarm. "" on success, or
## why not.
## `launcher_id`: fire that launcher only ("" = the first ready of `warhead`).
func launch_missile(shooter_id: StringName, target_id: StringName, warhead: int = -1, launcher_id: String = "") -> String:
	var s := get_ship(shooter_id)
	var target := get_ship(target_id)
	if s == null or s.systems == null or not s.is_active():
		return "no launcher"
	if target == null or not target.is_active():
		return "no target"
	var e := s.systems.ready_launcher(warhead) if launcher_id == "" else s.systems.launcher_if_ready(launcher_id)
	if e == null:
		for x in s.systems.equipment:
			if x.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER:
				return "launchers empty, cycling or offline"
		return "no missile launcher fitted"
	var cfg := e.def.missile
	var normal := Vector3(ShipGrid.FACE_NORMALS.get(s.systems.blueprint.equipment[e.index].face, Vector3i.UP))
	var out := s.orientation * normal
	var n := mini(maxi(e.def.missile_salvo, 1), s.systems.missiles_left(e))
	for k in n:
		# A swarm leaves fanned out a little, so it doesn't fly as one.
		var dir := out
		var offset := Vector3.ZERO
		if n > 1:
			var side := out.cross(Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT).normalized()
			var up := side.cross(out)
			var a := TAU * k / n
			dir = (out + (side * cos(a) + up * sin(a)) * 0.25).normalized()
			offset = (side * cos(a) + up * sin(a)) * 1.5
		var m := ShipState.create(StringName("%s_msl%d" % [shooter_id, _next_missile_id]), cfg.display_name, cfg.to_ship_config(),
			s.position + s.orientation * e.body_position + out * 4.0 + offset, s.velocity + dir * 15.0,
			Quaternion(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK)))
		_next_missile_id += 1
		m.missile = cfg
		m.missile_owner = shooter_id
		m.missile_target = target_id
		m.side = s.side
		add_ship(m)
		missiles.append(m)
	s.systems.missiles_used[e.id] = int(s.systems.missiles_used.get(e.id, 0)) + n
	s.systems.launcher_cooldown[e.id] = ShipSystems.LAUNCHER_CYCLE_S
	_link_events.append("%s launched at %s (%s)" % ["%d × %s" % [n, cfg.display_name] if n > 1 else cfg.display_name, target.display_name, e.id])
	return ""


## Fire every ready decoy launcher of `ship_id` once: decoy_salvo flares
## each, fanned out from the launcher's face. "" or why not.
func launch_decoys(ship_id: StringName) -> String:
	var s := get_ship(ship_id)
	if s == null or s.systems == null or not s.is_active():
		return "no launcher"
	var ready := s.systems.ready_decoy_launchers()
	if ready.is_empty():
		for e in s.systems.equipment:
			if e.def.kind == EquipmentDefinition.Kind.DECOY_LAUNCHER:
				return "flares empty, cycling or offline"
		return "no flare launcher fitted"
	var fired := 0
	for e in ready:
		var normal := Vector3(ShipGrid.FACE_NORMALS.get(s.systems.blueprint.equipment[e.index].face, Vector3i.UP))
		var out := s.orientation * normal
		var side := out.cross(Vector3.UP if absf(out.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := side.cross(out)
		var n := mini(e.def.decoy_salvo, s.systems.decoys_left(e))
		for k in n:
			var a := TAU * k / maxf(n, 1)
			var dir := (out + (side * cos(a) + up * sin(a)) * 0.7).normalized()
			decoys.append({"id": _next_decoy_id, "side": s.side, "owner": ship_id,
				"position": s.position + s.orientation * e.body_position + out * 3.0,
				"velocity": s.velocity + dir * DECOY_EJECT_MPS, "age": 0.0, "life": e.def.decoy_life_s,
				"signature": e.def.decoy_signature})
			_next_decoy_id += 1
		s.systems.missiles_used[e.id] = int(s.systems.missiles_used.get(e.id, 0)) + n
		s.systems.launcher_cooldown[e.id] = DECOY_CYCLE_S
		fired += n
	_link_events.append("%s: %d flares" % [s.display_name, fired])
	return ""


## A flare's signature now: bright at first, burning down to nothing.
static func decoy_signature(d: Dictionary) -> float:
	return float(d.signature) * sqrt(clampf(1.0 - float(d.age) / float(d.life), 0.0, 1.0))


## A ship as a seeker sees it (~1 for a frigate at rest): bigger hulls are
## brighter, and burning engines much more so.
static func signature_of(ship: ShipState) -> float:
	var size := pow(maxf(ship.config.mass_kg, 1.0) / 400_000.0, 1.0 / 3.0)
	var burn := 0.0
	if ship.config.thrust_forward_n > 0.0:
		burn = clampf(ship.last_thrust_body.length() / ship.config.thrust_forward_n, 0.0, 1.0)
	return size * (1.0 + 1.5 * burn)


## Jamming protecting `ship`: its own jammers plus EW craft of its side
## within EW_ESCORT_M.
func jamming_of(ship: ShipState) -> float:
	if ship == null:
		return 0.0
	var j := ship.systems.jamming_strength() if ship.systems != null else 0.0
	for wing in wings:
		for c in wing.flying():
			var craft := get_ship(c.id)
			if craft != null and craft.is_active() and craft.side == ship.side and craft.config.jam_strength > 0.0 \
					and craft.position.distance_to(ship.position) <= EW_ESCORT_M:
				j += craft.config.jam_strength
	return j


## How much of `jamming` gets through at `range_m` past `resist` (0–1):
## nothing inside burn-through, full beyond JAM_FULL_M.
static func jam_effect(jamming: float, resist: float, range_m: float) -> float:
	var ramp := clampf((range_m - BURN_THROUGH_M) / (JAM_FULL_M - BURN_THROUGH_M), 0.0, 1.0)
	return clampf(jamming * (1.0 - clampf(resist, 0.0, 1.0)) * ramp, 0.0, 1.0)


func _decoy(id: int) -> Dictionary:
	for d in decoys:
		if int(d.id) == id:
			return d
	return {}


## Seekers: each missile weighs each enemy flare once, when it first sees
## it inside its cone and no further than 1.5 × its target (seeded by the
## pair, so the same engagement always goes the same way); a seduced missile
## chases the flare. A burned-out flare leaves it to find the target again
## inside its cone, or lost. Jamming may break the lock outright.
func _update_seekers() -> void:
	for m in missiles:
		if not m.is_active() or m.missile_lost:
			continue
		var target := get_ship(m.missile_target)
		if target == null or not target.is_active():
			continue
		var cfg := m.missile
		if m.missile_decoy >= 0:
			var chased := _decoy(m.missile_decoy)
			if chased.is_empty() or decoy_signature(chased) <= 0.05:
				m.missile_decoy = -1
				var to_t := target.position - m.position
				if rad_to_deg((m.orientation * Vector3.FORWARD).angle_to(to_t)) > cfg.seeker_cone_deg:
					_lose_lock(m, "lost its flare")
			continue
		var to_target := target.position - m.position
		var seen: Dictionary = _seen_decoys.get(m.id, {})
		for d in decoys:
			if d.side == m.side or seen.has(d.id):
				continue
			var to_d: Vector3 = (d.position as Vector3) - m.position
			if to_d.length() > to_target.length() * 1.5 or rad_to_deg(to_d.angle_to(to_target)) > cfg.seeker_cone_deg:
				continue
			seen[d.id] = true
			var p := seduction_chance(decoy_signature(d), signature_of(target), cfg.seeker_discrimination)
			if _roll("%s|%d" % [m.id, int(d.id)]) < p:
				m.missile_decoy = int(d.id)
				_link_events.append("%s decoyed by a flare" % cfg.display_name)
				break
		_seen_decoys[m.id] = seen
		# Jamming: once a second of flight, a chance to lose the lock.
		var second := int(m.missile_age)
		if m.missile_decoy < 0 and second != int(m.missile_age - fixed_dt):
			var eff := jam_effect(jamming_of(target), cfg.jam_resist, to_target.length())
			if eff > 0.0 and _roll("%s|jam|%d" % [m.id, second]) < eff * JAM_LOCK_LOSS_PER_S:
				_lose_lock(m, "jammed")


func _lose_lock(m: ShipState, why: String) -> void:
	m.missile_lost = true
	m.missile_lost_at = sim_time
	_link_events.append("%s %s" % [m.missile.display_name, why])


## Chance a seeker chases a flare of `decoy_sig` instead of a ship of
## `ship_sig`: the flare's share of the light, the ship's weighted by how
## well the seeker tells them apart.
static func seduction_chance(decoy_sig: float, ship_sig: float, discrimination: float) -> float:
	return decoy_sig / maxf(decoy_sig + ship_sig * discrimination, 1e-6)


## A repeatable roll in [0, 1) for `key`.
static func _roll(key: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng.randf()


## Flares drift and burn out.
func _step_decoys() -> void:
	var alive: Array[Dictionary] = []
	for d in decoys:
		d.age = float(d.age) + fixed_dt
		d.position = (d.position as Vector3) + (d.velocity as Vector3) * fixed_dt
		if float(d.age) < float(d.life):
			alive.append(d)
	decoys = alive


## Missiles in flight after `id` ([] if none).
func missiles_at(id: StringName) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for m in missiles:
		if m.missile_target == id and m.is_active():
			out.append(m)
	return out


## Warhead bursts since the last call.
func take_bursts() -> Array[Dictionary]:
	var out := _bursts
	_bursts = []
	return out


## Guidance: zero-effort-miss proportional navigation within the missile's
## acceleration, the nose swung at its turn rate; full thrust while it has
## propellant. A lost target leaves it coasting.
func _guide_missiles() -> void:
	for m in missiles:
		if not m.is_active():
			continue
		var input := ShipControlInput.create(Vector3(0, 0, -1), Vector3.ZERO, false)
		input.hold_translation = false
		var target := get_ship(m.missile_target)
		if target == null or not target.is_active() or m.missile_age < 0.3 or m.missile_lost:
			_inputs[m.id] = input if m.missile_age < 0.3 else ShipControlInput.neutral()
			continue
		var aim_pos := target.position
		var aim_vel := target.velocity
		if m.missile_decoy >= 0:
			var chased := _decoy(m.missile_decoy)
			if not chased.is_empty():
				aim_pos = chased.position
				aim_vel = chased.velocity
		var r := aim_pos - m.position
		var v := aim_vel - m.velocity
		var closing := maxf(-r.dot(v) / maxf(r.length(), 1.0), 1.0)
		var t_go := clampf(r.length() / closing, 0.2, 60.0)
		var zem := r + v * t_go
		var accel := m.missile.accel_mps2
		var a_cmd := zem * (NAV_GAIN / (t_go * t_go))
		if a_cmd.length() > accel:
			a_cmd = a_cmd.normalized() * accel
		# Spend what is left on closing in.
		a_cmd += r.normalized() * sqrt(maxf(accel * accel - a_cmd.length_squared(), 0.0))
		var want := a_cmd.normalized()
		var nose := m.orientation * Vector3.FORWARD
		var turn := minf(nose.angle_to(want), deg_to_rad(m.missile.turn_rate_deg_s) * fixed_dt)
		var axis := nose.cross(want)
		if axis.length() > 1e-6 and turn > 0.0:
			m.orientation = (Quaternion(axis.normalized(), turn) * m.orientation).normalized()
		m.angular_velocity = Vector3.ZERO
		_inputs[m.id] = input


## Fuses, shoot-downs and self-destruct, after the ships have moved.
func _step_missiles() -> void:
	var gone: Array[StringName] = []
	for m in missiles:
		m.missile_age += fixed_dt
		if not m.is_active():
			_link_events.append("%s shot down" % m.display_name)
			_burst_in_space(m, true)
			gone.append(m.id)
			continue
		if m.missile_age > m.missile.lifetime_s:
			_link_events.append("%s self-destructed (out of time)" % m.display_name)
			_burst_in_space(m, true)
			gone.append(m.id)
			continue
		if m.missile_lost and sim_time - m.missile_lost_at >= LOST_SELF_DESTRUCT_S:
			_link_events.append("%s self-destructed (no lock)" % m.display_name)
			_burst_in_space(m, true)
			gone.append(m.id)
			continue
		if m.missile_decoy >= 0 and m.missile_age >= m.missile.arm_s:
			var chased := _decoy(m.missile_decoy)
			if not chased.is_empty() and m.position.distance_to(chased.position) <= maxf(m.missile.fuse_radius_m * 3.0, 15.0):
				_link_events.append("%s burst on a flare" % m.display_name)
				_burst_in_space(m, false)
				gone.append(m.id)
				continue
		var target := get_ship(m.missile_target)
		if target == null or not target.is_active() or m.missile_age < m.missile.arm_s or m.missile_decoy >= 0 or m.missile_lost:
			continue
		var fuse := _fuse_point(m, target)
		if fuse.is_finite():
			m.position = fuse
			_detonate(m, target)
			gone.append(m.id)
	for id in gone:
		missiles = missiles.filter(func(x: ShipState) -> bool: return x.id != id)
		_seen_decoys.erase(id)
		remove_ship(id)


## A missile breaking up away from any hull (shot down, self-destruct): a
## burst for the views, carried by the nearest of its target and its
## launcher so it rides with the fight.
func _burst_in_space(m: ShipState, broken: bool) -> void:
	var anchor: ShipState
	for id in [m.missile_target, m.missile_owner]:
		var s := get_ship(id)
		if s != null and (anchor == null or s.position.distance_to(m.position) < anchor.position.distance_to(m.position)):
			anchor = s
	if anchor == null:
		return
	_bursts.append({"ship_id": anchor.id, "point_body": anchor.orientation.inverse() * (m.position - anchor.position),
		"radius": clampf(m.mass_kg() / 100.0, 1.5, 6.0), "kind": m.missile.warhead, "shot_down": broken})


## Where the missile first came within its fuse radius of `target` this
## tick, swept along its path relative to the target (a fast missile moves
## further than the fuse radius in a tick), or Vector3.INF if it didn't.
func _fuse_point(m: ShipState, target: ShipState) -> Vector3:
	var start := target.position + (m.prev_position - target.prev_position)
	var steps := clampi(ceili(start.distance_to(m.position) / maxf(m.missile.fuse_radius_m * 0.5, 0.5)), 1, 200)
	for k in steps + 1:
		var p := start.lerp(m.position, float(k) / steps)
		if Grapple.gap_to(target, p) <= m.missile.fuse_radius_m:
			return p
	return Vector3.INF


func _detonate(m: ShipState, target: ShipState) -> void:
	var cfg := m.missile
	var inv := target.orientation.inverse()
	match cfg.warhead:
		MissileConfig.Warhead.ANTI_SHIP:
			var rel_v := m.velocity - target.velocity
			var dir := rel_v.normalized() if rel_v.length() > 1.0 else (target.position - m.position).normalized()
			if target.systems == null:
				target.status = ShipState.Status.DESTROYED
				target.status_time = sim_time
				_link_events.append("%s destroyed %s" % [cfg.display_name, target.display_name])
				return
			# The penetrator follows the line of flight into the hull.
			var a := inv * (m.position - dir * 20.0 - target.position)
			var b := inv * (m.position + dir * 60.0 - target.position)
			var t := Penetration.first_hull_entry(target.systems, a, b)
			var point_body := a.lerp(b, t) if t >= 0.0 else inv * (m.position - target.position)
			var ev := HitEvent.new()
			ev.tick = tick
			ev.shooter_id = m.missile_owner
			ev.target_id = target.id
			ev.point_body = point_body
			ev.relative_speed = rel_v.length()
			ev.energy_j = 0.5 * m.mass_kg() * rel_v.length_squared()
			ev.missile = true
			ev.report = Penetration.apply(target.systems, point_body, inv * dir, cfg.penetration_mm)
			_apply_damage(target, ev.report)
			target.systems.blast_at(point_body, cfg.blast_radius_m, cfg.blast_structure_fraction, cfg.blast_hp, "%s hit — warhead detonated" % cfg.display_name)
			_apply_impulse(target, point_body, rel_v * m.mass_kg())
			target.config = target.systems.effective_config()
			_hit_events.append(ev)
			target.hits_taken += 1
			_bursts.append({"ship_id": target.id, "point_body": point_body, "radius": cfg.blast_radius_m, "kind": cfg.warhead})
			_link_events.append("%s hit %s" % [cfg.display_name, target.display_name])
		_:
			var reach := cfg.effect_radius_m * (3.0 if cfg.warhead == MissileConfig.Warhead.EMP else 4.0)
			for id in _ship_order:
				var s: ShipState = _ships[id]
				if s == m or not s.is_active():
					continue
				var d := s.position.distance_to(m.position)
				if d > reach:
					continue
				var exposure := pow(cfg.effect_radius_m / maxf(d, 20.0), 2.0)
				if s.systems == null:
					# Craft and missiles: fried or burned out close in.
					if exposure > 1.0:
						s.status = ShipState.Status.DESTROYED
						s.status_time = sim_time
					continue
				var lines := s.systems.emp(exposure) if cfg.warhead == MissileConfig.Warhead.EMP \
					else s.systems.nuclear(exposure, s.orientation.inverse() * (m.position - s.position))
				s.config = s.systems.effective_config()
				if not lines.is_empty():
					_link_events.append("%s: %s" % [s.display_name, "; ".join(lines)])
			_bursts.append({"ship_id": target.id, "point_body": inv * (m.position - target.position),
				"radius": cfg.effect_radius_m * (0.4 if cfg.warhead == MissileConfig.Warhead.NUCLEAR else 0.5), "kind": cfg.warhead})
			_link_events.append("%s detonated %.0f m from %s" % [cfg.display_name, Grapple.gap_to(target, m.position), target.display_name])


## The arm `id` is holding with (or is held by), or null.
func grapple_for(id: StringName) -> Grapple:
	for g in grapples:
		if g.holding() and (g.attacker_id == id or g.target_id == id):
			return g
	return null


## Grab `target_id` with `attacker_id`'s arm. "" on success, else why not.
func grab(attacker_id: StringName, target_id: StringName) -> String:
	if grapple_for(attacker_id) != null:
		return "the arm is already holding on"
	var a := get_ship(attacker_id)
	var why := Grapple.block_reason(a, get_ship(target_id))
	if why != "":
		return why
	grapples.append(Grapple.grab(a, get_ship(target_id)))
	_link_events.append("Grappling arm: hold on %s" % get_ship(target_id).display_name)
	return ""


## The boarding over `link`, or null.
func boarding_for(link: DockingLink) -> BoardingAction:
	for b in boardings:
		if b.link == link:
			return b
	return null


## Try to extend a gangway from `attacker_id` to `target_id`. Returns
## Docking.best()'s result plus "link" when it started; check
## result.assessment.problems otherwise ({} = no docking collar).
func dock(attacker_id: StringName, target_id: StringName) -> Dictionary:
	var a := get_ship(attacker_id)
	var b := get_ship(target_id)
	if a == null or b == null or link_for(attacker_id) != null:
		return {}
	var found := Docking.best(a, b)
	if found.is_empty() or not found.assessment.ok:
		return found
	var link := DockingLink.create(a, found.a_port, b, found.b_port)
	links.append(link)
	found["link"] = link
	_link_events.append("Gangway extending to %s (%s, %.0f s)" % [b.display_name,
		"collar %s" % found.b_port.equipment_id if found.b_port.kind == &"collar" else "cutting the hull", link.required_s])
	return found


## Send a boarding party over a sealed gangway (null if it can't go).
func start_boarding(link: DockingLink, max_team: int = BoardingAction.MAX_TEAM) -> BoardingAction:
	if link == null or not link.sealed() or boarding_for(link) != null:
		return null
	var a := get_ship(link.attacker_id)
	var b := get_ship(link.target_id)
	var action := BoardingAction.start(link, a.systems, b.systems, max_team)
	if action != null:
		boardings.append(action)
	return action


## Gangway and boarding messages since the last call.
func take_link_events() -> PackedStringArray:
	var out := _link_events
	_link_events = PackedStringArray()
	return out


func has_ship(id: StringName) -> bool:
	return _ships.has(id)


func get_ship(id: StringName) -> ShipState:
	return _ships.get(id) as ShipState


func ship_ids() -> Array[StringName]:
	return _ship_order.duplicate()


func set_input(id: StringName, input: ShipControlInput) -> void:
	_inputs[id] = input


## Rounds near the engagement (integrated and hit-tested every tick).
func projectiles() -> Array[ProjectileState]:
	return _rounds


## Rounds coasting on far orbits.
func far_projectiles() -> Array[ProjectileState]:
	return _far_rounds


func round_count() -> int:
	return _rounds.size() + _far_rounds.size()


## Hit events since the last call (each event is returned once).
func take_hit_events() -> Array[HitEvent]:
	var events := _hit_events
	_hit_events = []
	return events


## Time spent per phase of step() (ms, summed since the last
## take_phase_ms()), for the profiling tools.
var _phase_ms := {}
var _phase_t0 := 0


func _phase(name: String) -> void:
	var now := Time.get_ticks_usec()
	_phase_ms[name] = float(_phase_ms.get(name, 0.0)) + (now - _phase_t0) / 1000.0
	_phase_t0 = now


func take_phase_ms() -> Dictionary:
	var out := _phase_ms
	_phase_ms = {}
	return out


## Run exactly one fixed tick.
func step() -> void:
	_phase_t0 = Time.get_ticks_usec()
	if frame != null:
		frame.step(fixed_dt)
	var spawned: Array[ProjectileState] = []
	for wing in wings:
		wing.update(self, fixed_dt)
	_phase("wings")
	_update_seekers()
	_guide_missiles()
	_phase("guidance")
	_collect_pd_rounds()
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		ship.snapshot_previous()
		if not ship.is_active():
			continue
		var input: ShipControlInput = _neutral_input if ship.derelict else _inputs.get(id, _neutral_input)
		if ship.systems != null and not ship.systems.has_command() and not input.flight_assist and not ship.derelict:
			# Ship AI in control: it always flies with assist.
			input = ShipControlInput.create(input.translation, input.rotation, true)
			input.fire = _inputs.get(id, _neutral_input).fire
			input.fire_rate = _inputs.get(id, _neutral_input).fire_rate
		_resolve_hold(input)
		ShipDynamics.step(ship, input, fixed_dt, frame)
		_update_cannon(ship, input, spawned)
		_phase("ships")
		_update_point_defence(ship, spawned)
		_phase("point_defence")
		if ship.systems != null and ship.systems.tick(ship, fixed_dt):
			ship.config = ship.systems.effective_config()
		_phase("systems")
	for p in _pending_beams:
		_fire_beam(p[0], p[1], p[2], p[3], p[4])
	_pending_beams.clear()
	_step_missiles()
	_step_decoys()
	_phase("missiles")
	_step_collisions()
	_phase("collisions")
	_step_links()
	tick += 1
	sim_time = tick * fixed_dt
	_step_rounds()
	_phase("rounds")
	if frame != null:
		_step_far_rounds()
	_rounds.append_array(spawned)  # fired at end of tick; first move next tick
	_check_entry_interface()
	_rebase_if_needed()
	_phase("other")


## Feed real elapsed time; runs whole fixed steps and returns the
## interpolation factor in [0, 1) between the last two states.
func advance(frame_delta: float) -> float:
	_accumulator += maxf(frame_delta, 0.0)
	var steps := 0
	# A deliberate fast-forward (Engine.time_scale > 1, the smoke tests) keeps
	# the old cap: more ticks a frame and Main's per-frame logic (docking,
	# boarding) would steer too coarsely.
	var cap := MAX_STEPS_PER_ADVANCE if Engine.time_scale <= 1.0 else FAST_FORWARD_STEPS
	while _accumulator + _ACCUMULATOR_EPSILON >= fixed_dt and steps < cap:
		step()
		_accumulator -= fixed_dt
		steps += 1
	if _accumulator + _ACCUMULATOR_EPSILON >= fixed_dt:
		dropped_time += _accumulator
		_accumulator = 0.0
	_accumulator = maxf(_accumulator, 0.0)
	return clampf(_accumulator / fixed_dt, 0.0, 1.0)


# --- Orbital queries (require a central body) -------------------------------

func pci_position(local: Vector3) -> Vec3d:
	return frame.pci_position(local)


func pci_velocity(local_velocity: Vector3) -> Vec3d:
	return frame.pci_velocity(local_velocity)


func orbit_of(ship: ShipState) -> OrbitElements:
	if frame == null:
		return null
	return OrbitElements.from_state(body.mu_m3_s2, pci_position(ship.position), pci_velocity(ship.velocity))


func altitude_of(ship: ShipState) -> float:
	return frame.altitude(ship.position) if frame != null else NAN


## Local position mapped to a coordinate that is continuous across rebases.
func continuous_position(local: Vector3) -> Vec3d:
	var offset := frame.rebase_offset if frame != null else _inertial_rebase_offset
	return offset.plus_v3(local)


# --- Internals ---------------------------------------------------------------

func _resolve_hold(input: ShipControlInput) -> void:
	if input.hold_target_id == &"":
		return
	var target := get_ship(input.hold_target_id)
	if target != null and target.is_active():
		input.hold_velocity = target.velocity
	else:
		input.hold_translation = false  # reference gone: coast


## Primary weapons are locked while a gangway is attached (firing at point
## blank would tear it away). Craft and automatic defences are not.
func weapons_locked(id: StringName) -> bool:
	return link_for(id) != null


func _update_cannon(ship: ShipState, input: ShipControlInput, spawned: Array[ProjectileState]) -> void:
	if ship.config.cannon == null:
		return
	var cfg := ship.config
	var muzzles := cfg.cannon_muzzles_body
	var locked := weapons_locked(ship.id)
	var inv := ship.orientation.inverse()
	for k in muzzles.size():
		var cannon := cfg.mount_cannon(k)
		ship.cannon_cooldowns[k] = maxf(ship.cannon_cooldowns[k] - fixed_dt, 0.0)
		var status := _train_turret(ship, input, k, inv)
		if ship.systems != null and not ship.systems.mount_working(k):
			status = ShipState.Turret.OFFLINE  # destroyed or unpowered mount
		elif locked:
			status = ShipState.Turret.LOCKED
		ship.turret_status[k] = status
		if status != ShipState.Turret.READY or not input.fire or ship.cannon_cooldowns[k] > 1e-9:
			continue
		if cannon.is_beam() and input.lead_target_id != &"":
			var aim := get_ship(input.lead_target_id)
			if aim != null and aim.position.distance_squared_to(ship.position) > cannon.beam_range_m * cannon.beam_range_m:
				continue  # fire control holds a beam until its target is in reach
		# A ship's beam fires on power; everything else (a craft's beam too)
		# needs rounds / charges.
		var on_power := cannon.is_beam() and ship.systems != null
		if not on_power and ship.rounds_for(cannon) <= 0:
			continue
		var dir_body := ship.turret_dirs[k]
		var muzzle_body := muzzles[k]
		if cfg.is_turret(k):
			muzzle_body += cfg.cannon_mount_normals_body[k] * TURRET_HEIGHT_M
			var spread := deg_to_rad(cannon.dispersion_deg) + cfg.cannon_extra_dispersion_rad
			if spread > 0.0:
				dir_body = _scatter(dir_body, spread)
		var dir := ship.orientation * dir_body
		if cannon.is_beam():
			_pending_beams.append([ship, cannon, muzzle_body, dir_body, input.lead_target_id])
			if not on_power:
				ship.spend_round(cannon)
			ship.beam_pulses += 1
			ship.cannon_cooldowns[k] += cannon.fire_interval_s() / clampf(input.fire_rate, 0.1, 1.0)
			continue
		var shot := ProjectileState.new()
		shot.id = _next_round_id
		_next_round_id += 1
		shot.shooter_id = ship.id
		shot.weapon = cannon
		if ship.systems == null and ship.config.hull_hp > 0.0 and ship.missile == null:
			shot.iff_side = ship.side
		shot.position = ship.position + ship.orientation * muzzle_body
		shot.prev_position = shot.position
		shot.velocity = ship.velocity + dir * cannon.muzzle_velocity_mps
		spawned.append(shot)
		# Recoil conserves momentum and angular momentum: the ship gets −p at
		# the muzzle, so a muzzle off the centre of mass also kicks its spin.
		var p_body := dir_body * (cannon.muzzle_velocity_mps * cannon.round_mass_kg)
		ship.velocity -= dir * (cannon.muzzle_velocity_mps * cannon.round_mass_kg / ship.mass_kg())
		ship.angular_velocity -= muzzle_body.cross(p_body) / ship.inertia_kgm2()
		ship.recoil_impulse += cannon.muzzle_velocity_mps * cannon.round_mass_kg
		ship.spend_round(cannon)
		ship.rounds_fired += 1
		ship.cannon_cooldowns[k] += cannon.fire_interval_s() / clampf(input.fire_rate, 0.1, 1.0)


## Beam pulses fired since the views last took them: {shooter_id,
## from_body (muzzle, shooter's body frame), target_id (&"" = it reached
## full reach), to_body (where it struck, target's body frame; else its end
## relative to the muzzle, world axes), color}.
var _beams: Array[Dictionary] = []
## Pulses fired this tick, resolved once every ship has moved: [ship, gun,
## muzzle (body), direction (body), fire-control target].
var _pending_beams: Array = []
## A beam's steering mirror lays it on a small target (a craft or missile)
## within this cone of the barrel (°): a fixed gun pointed by the whole
## craft lags a fast missile by metres, the mirror does not.
const BEAM_STEER_DEG := 2.0
## Beam pulses that struck something (all ships), for tests and stats.
var beam_hits: int = 0


func take_beams() -> Array[Dictionary]:
	var out := _beams
	_beams = []
	return out


## One beam pulse (play-test batch 6): no round — the first hull on the
## line out to the beam's reach takes it at once, with the penetration its
## range leaves (KineticCannonConfig.beam_penetration_at). It is resolved
## after every ship has moved, against where they all were at the start of
## the tick — what fire control aimed at — so a light, fast target is where
## the beam was laid (a mid-tick test would see half the ships moved).
## Nothing to push: light carries no momentum worth the name. Same
## friend-or-foe rules as a round: never the shooter or its own missiles; a
## craft's IFF spares its side.
func _fire_beam(ship: ShipState, cannon: KineticCannonConfig, muzzle_body: Vector3, dir_body: Vector3, aim_id: StringName) -> void:
	var from := ship.prev_position + ship.prev_orientation * muzzle_body
	var aim := get_ship(aim_id) if aim_id != &"" else null
	if aim != null and aim.systems == null:
		var want := ship.prev_orientation.inverse() * (aim.prev_position + aim.prev_orientation * aim.config.hit_box_center - from)
		if want.length() > 1.0 and rad_to_deg(dir_body.angle_to(want)) <= BEAM_STEER_DEG:
			dir_body = want.normalized()
	var dir := ship.prev_orientation * dir_body
	var seg := dir * cannon.beam_range_m
	var iff := ship.side if ship.systems == null and ship.config.hull_hp > 0.0 and ship.missile == null else &""
	var best_t := INF
	var best: ShipState = null
	for id in _ship_order:
		var other: ShipState = _ships[id]
		if other == ship or not other.is_active() or other.missile_owner == ship.id:
			continue
		if iff != &"" and other.side == iff and other.missile == null:
			continue
		var p0 := from - other.prev_position
		var u := clampf(-p0.dot(seg) / seg.length_squared(), 0.0, 1.0)
		var reach := other.config.hit_box_center.length() + other.config.hit_box_half_extents.length()
		if (p0 + seg * u).length_squared() > reach * reach:
			continue
		var inv := other.prev_orientation.inverse()
		var a := inv * p0
		var b := inv * (p0 + seg)
		var t := HitTest.segment_box(a, b, other.config.hit_box_center, other.config.hit_box_half_extents)
		if t >= 0.0 and other.systems != null:
			# The hull cells from where it enters the box: the grid walk is
			# short (ShipGrid.traverse), a beam kilometres long.
			var t_hull := Penetration.first_hull_entry(other.systems, a.lerp(b, t), b)
			t = t + t_hull * (1.0 - t) if t_hull >= 0.0 else -1.0
		if t >= 0.0 and t < best_t:
			best_t = t
			best = other
	var pulse := {"shooter_id": ship.id, "from_body": muzzle_body, "target_id": &"", "to_body": seg, "color": cannon.beam_color}
	_beams.append(pulse)
	if best == null:
		return
	var inv_q := best.prev_orientation.inverse()
	var range_m := best_t * cannon.beam_range_m
	var pen := cannon.beam_penetration_at(range_m)
	var ev := HitEvent.new()
	ev.tick = tick
	ev.round_id = _next_round_id
	_next_round_id += 1
	ev.shooter_id = ship.id
	ev.target_id = best.id
	ev.point_body = inv_q * (from + seg * best_t - best.prev_position)
	ev.beam = true
	pulse.target_id = best.id
	pulse.to_body = ev.point_body
	if best.systems != null:
		ev.report = Penetration.apply(best.systems, ev.point_body, inv_q * dir, pen)
		ev.report.lines[0] = "Beam pulse arrives with %.0f mm penetration (%.1f km)" % [pen, range_m / 1000.0]
		ev.report.ricochet = false  # a beam is stopped by a plate, it does not bounce
		_apply_damage(best, ev.report)
	elif best.config.hull_hp > 0.0:
		best.hull_damage += pen
		if best.hull_damage >= best.config.hull_hp:
			best.status = ShipState.Status.DESTROYED
			best.status_time = sim_time
			GameLog.info("sim", "%s destroyed at T+%.2f s" % [best.display_name, sim_time])
	_hit_events.append(ev)
	best.hits_taken += 1
	beam_hits += 1


## Point-defence range (m) and how close to the lead a barrel must be (deg).
## The engagement range when a ship has no policy (m), and how close a
## mount must be on its lead to fire (°).
const PD_RANGE_M := 2000.0
const PD_READY_DEG := 1.5
## A flak round bursting this close to the round it was fired at destroys
## it (m). Point defence can only track big, slow slugs — at least
## PD_ROUND_MIN_KG and closing slower than PD_ROUND_MAX_CLOSING_MPS (the
## heavy cannon's 4 kg rounds): autocannon rounds are too small to track,
## railgun slugs too fast.
const PD_FLAK_RADIUS_M := 2.6  # √3 × the old 1.5 m: a third as many flak rounds, three times the mass (batch 6)
const PD_ROUND_MIN_KG := 2.0
const PD_ROUND_MAX_CLOSING_MPS := 1500.0
## A hostile round is a threat if it will pass within the ship's hit box
## reach plus this margin (m) inside this horizon (s).
const PD_THREAT_MARGIN_M := 10.0
const PD_THREAT_HORIZON_S := 6.0
## Rounds destroyed by point-defence flak (all ships), for tests and stats.
var rounds_intercepted: int = 0
static var _default_policy: ShipPolicy


func _policy_of(ship: ShipState) -> ShipPolicy:
	if ship.policy != null:
		return ship.policy
	if _default_policy == null:
		_default_policy = ShipPolicy.preset("Defensive")
	return _default_policy


## Is `other` (a craft or missile) fair game for `ship`'s point defence?
## Never its own craft or missiles, nor its own side's, nor a derelict.
func _hostile_to(ship: ShipState, other: ShipState) -> bool:
	if other.derelict or _is_craft_of(other.id, ship.id) or other.missile_owner == ship.id or _is_craft_of(other.missile_owner, ship.id):
		return false
	return ship.side == &"" or other.side == &"" or ship.side != other.side


## Is a round a threat `ship`'s point defence can engage: a big, slow slug,
## not its own side's, not flak, on a course to pass within its hit box
## reach soon?
func _round_threatens(ship: ShipState, shot: ProjectileState) -> bool:
	# Cheapest checks first: most rounds are too small (autocannon, flak).
	if shot.mass_kg() < PD_ROUND_MIN_KG or shot.pd_target_round >= 0:
		return false
	if (shot.velocity - ship.velocity).length_squared() > PD_ROUND_MAX_CLOSING_MPS * PD_ROUND_MAX_CLOSING_MPS \
			or shot.shooter_id == ship.id or _is_craft_of(shot.shooter_id, ship.id):
		return false
	var shooter := get_ship(shot.shooter_id)
	if shooter != null and ship.side != &"" and shooter.side == ship.side:
		return false
	var ca := RelativeMotion.closest_approach(ship.position, ship.velocity, shot.position, shot.velocity)
	return ca.time > 0.0 and ca.time < PD_THREAT_HORIZON_S \
		and ca.miss < ship.config.hit_box_half_extents.length() + PD_THREAT_MARGIN_M


## Rounds point defence could track at all (heavy enough, not flak),
## gathered once per tick: with thousands of light rounds about, scanning
## them all for every PD ship was most of the tick (play-test batch 6).
var _pd_rounds: Array[ProjectileState] = []
## Missiles and craft (what PD shoots besides rounds), gathered once per tick.
var _pd_air: Array[ShipState] = []
## Candidates just beyond PD range are kept (they close within the tick).
const PD_CANDIDATE_SLACK_M := 300.0


var _pd_collected_tick := -1


func _collect_pd_rounds() -> void:
	_pd_collected_tick = tick
	_pd_air.clear()
	for id in _ship_order:
		var s: ShipState = _ships[id]
		if s.is_active() and s.systems == null and s.config.hull_hp > 0.0:
			_pd_air.append(s)
	_pd_rounds.clear()
	for shot in _rounds:
		if shot.pd_target_round < 0 and shot.weapon != null and shot.weapon.round_mass_kg >= PD_ROUND_MIN_KG:
			_pd_rounds.append(shot)


## What `ship`'s point defence could engage now — hostile missiles, craft
## and rounds on a collision course — as {kind, rank, pos, vel, id, round,
## d}, in the policy's order, nearest first within a kind.
func pd_candidates(ship: ShipState) -> Array[Dictionary]:
	var policy := _policy_of(ship)
	var out: Array[Dictionary] = []
	if _pd_collected_tick != tick:
		_collect_pd_rounds()  # called between ticks (HUD, tests)
	var reach2 := (policy.pd_range_m + PD_CANDIDATE_SLACK_M) * (policy.pd_range_m + PD_CANDIDATE_SLACK_M)
	for other in _pd_air:
		# Cheapest first: most are out of reach (play-test batch 6).
		if other == ship or other.position.distance_squared_to(ship.position) > reach2 or not _hostile_to(ship, other):
			continue
		var kind := &"missile" if other.missile != null else &"craft"
		out.append({"kind": kind, "rank": policy.pd_rank(kind), "pos": other.position, "vel": other.velocity,
			"id": String(other.id), "round": -1, "d": other.position.distance_to(ship.position)})
	if policy.pd_rank(&"round") >= 0:
		for shot in _pd_rounds:
			if _round_threatens(ship, shot):
				out.append({"kind": &"round", "rank": policy.pd_rank(&"round"), "pos": shot.position, "vel": shot.velocity,
					"id": "round:%d" % shot.id, "round": shot.id, "d": shot.position.distance_to(ship.position)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.rank) < int(b.rank) or (int(a.rank) == int(b.rank) and float(a.d) < float(b.d)))
	return out


## Point defence: each working PD turret takes the first candidate its
## policy allows (order, range, ammunition reserve) that is in its arc,
## trains on its lead and fires on its own — gangway or not (automatic
## defences). Flak fired at a round remembers it (`pd_target_round`).
func _update_point_defence(ship: ShipState, spawned: Array[ProjectileState]) -> void:
	var cfg := ship.config
	if cfg.pd_gun == null or ship.systems == null or ship.derelict:
		return
	var policy := _policy_of(ship)
	var gun := cfg.pd_gun
	var inv := ship.orientation.inverse()
	var candidates: Array[Dictionary] = []
	if policy.pd_enabled:
		candidates = pd_candidates(ship)
	for k in cfg.pd_mounts_body.size():
		ship.pd_cooldowns[k] = maxf(ship.pd_cooldowns[k] - fixed_dt, 0.0)
		ship.pd_targets[k] = ""
		var e := ship.systems.equipment_by_id(cfg.pd_mount_ids[k])
		if e == null or not e.working() or ship.pd_rounds <= 0:
			continue
		var n := cfg.pd_normals_body[k]
		var muzzle := cfg.pd_mounts_body[k] + n * 0.6
		var muzzle_world := ship.position + ship.orientation * muzzle
		var chosen := {}
		var want := Vector3.ZERO
		for c in candidates:
			if not policy.pd_allows(c.kind, ship.pd_rounds, ship.pd_rounds_capacity) \
					or (c.pos as Vector3).distance_to(muzzle_world) > policy.pd_range_m:
				continue
			var rel: Vector3 = c.pos - muzzle_world
			var rel_v: Vector3 = c.vel - ship.velocity
			var t := FireControl.intercept_time(rel, rel_v, gun.muzzle_velocity_mps)
			if t < 0.0:
				continue
			want = (inv * FireControl.lead_point(rel, rel_v, t)).normalized()
			if want.dot(n) < TURRET_ARC_MIN_DOT:
				continue  # under its face: another mount's job
			chosen = c
			break
		if chosen.is_empty():
			ship.pd_dirs[k] = _rotate_toward(ship.pd_dirs[k], n, deg_to_rad(gun.traverse_deg_s) * fixed_dt)
			continue
		ship.pd_targets[k] = str(chosen.id)
		var dir := _rotate_toward(ship.pd_dirs[k], want, deg_to_rad(gun.traverse_deg_s) * fixed_dt)
		ship.pd_dirs[k] = dir
		if ship.pd_cooldowns[k] > 1e-9 or rad_to_deg(dir.angle_to(want)) > PD_READY_DEG or _hull_in_the_way(ship, muzzle, dir):
			continue
		var shot := ProjectileState.new()
		shot.id = _next_round_id
		_next_round_id += 1
		shot.shooter_id = ship.id
		shot.weapon = gun
		shot.position = muzzle_world
		shot.prev_position = shot.position
		shot.velocity = ship.velocity + ship.orientation * _scatter(dir, deg_to_rad(gun.dispersion_deg)) * gun.muzzle_velocity_mps
		shot.pd_target_round = int(chosen.round)
		spawned.append(shot)
		ship.pd_rounds -= 1
		ship.pd_cooldowns[k] += gun.fire_interval_s()


## Trains mount k towards the aim point (turrets) and says whether it can
## fire. Fixed guns always point along the nose.
func _train_turret(ship: ShipState, input: ShipControlInput, k: int, inv: Quaternion) -> int:
	var cfg := ship.config
	if not cfg.is_turret(k):
		ship.turret_dirs[k] = Vector3.FORWARD
		return ShipState.Turret.READY
	var n := cfg.cannon_mount_normals_body[k]
	var muzzle := cfg.cannon_muzzles_body[k] + n * TURRET_HEIGHT_M
	var gun := cfg.mount_cannon(k)
	var want := Vector3.FORWARD
	if input.has_aim:
		var aim := input.aim_offset + _lead_correction(ship, input, k)
		var rel := inv * aim - muzzle
		if rel.length() > 1.0:
			want = rel.normalized()
	var status := ShipState.Turret.READY
	if want.dot(n) < TURRET_ARC_MIN_DOT:
		want = _clamp_to_arc(want, n)
		status = ShipState.Turret.OUT_OF_ARC
	var dir := _rotate_toward(ship.turret_dirs[k], want, deg_to_rad(gun.traverse_deg_s) * fixed_dt)
	ship.turret_dirs[k] = dir
	if ship.systems != null and ship.blocked_cached(k, dir, func() -> bool: return _hull_in_the_way(ship, muzzle, dir)):
		return ShipState.Turret.BLOCKED
	if status == ShipState.Turret.READY and rad_to_deg(dir.angle_to(want)) > TURRET_READY_DEG:
		status = ShipState.Turret.SLEWING
	return status


## With a fire-control lock and a gun slower or faster than the primary:
## its own lead on the locked ship minus the primary's (world, m).
func _lead_correction(ship: ShipState, input: ShipControlInput, k: int) -> Vector3:
	var cfg := ship.config
	var gun := cfg.mount_cannon(k)
	if input.lead_target_id == &"" or gun == cfg.cannon or is_equal_approx(gun.muzzle_velocity_mps, cfg.cannon.muzzle_velocity_mps):
		return Vector3.ZERO
	var target := get_ship(input.lead_target_id)
	if target == null or not target.is_active():
		return Vector3.ZERO
	var leads := []
	for g in [cfg.cannon, gun]:
		var muzzle := ship.position + ship.orientation * cfg.cannon_muzzles_body[0 if g == cfg.cannon else k]
		var rel := target.position + target.orientation * target.config.hit_box_center - muzzle
		var rel_v := target.velocity - ship.velocity
		var t := FireControl.intercept_time(rel, rel_v, (g as KineticCannonConfig).muzzle_velocity_mps)
		if t < 0.0:
			return Vector3.ZERO
		leads.append(muzzle + FireControl.lead_point(rel, rel_v, t))
	return (leads[1] as Vector3) - (leads[0] as Vector3)


## Whether a round leaving `muzzle` (body) along `dir` would enter its own hull.
static func _hull_in_the_way(ship: ShipState, muzzle: Vector3, dir: Vector3) -> bool:
	var reach := ship.systems.grid.cell_bounds().size.length() * ShipGrid.CELL_SIZE_M + 6.0
	var start := muzzle + dir * 0.5
	return Penetration.first_hull_entry(ship.systems, start, start + dir * reach) >= 0.0


static func _clamp_to_arc(want: Vector3, n: Vector3) -> Vector3:
	var flat := want - n * want.dot(n)
	if flat.length() < 1e-6:
		flat = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
	return (flat.normalized() * sqrt(1.0 - TURRET_ARC_MIN_DOT * TURRET_ARC_MIN_DOT) + n * TURRET_ARC_MIN_DOT).normalized()


## `from` turned towards `to` by at most `max_angle` radians.
static func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle <= max_angle or angle < 1e-6:
		return to
	var axis := from.cross(to)
	if axis.length() < 1e-6:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_angle).normalized()


## A direction scattered by a normally distributed angle (σ = `sigma` rad).
func _scatter(dir: Vector3, sigma: float) -> Vector3:
	var perp := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	perp = perp.rotated(dir, _rng.randf() * TAU)
	return dir.rotated(perp, _rng.randfn(0.0, sigma)).normalized()


# --- Collisions --------------------------------------------------------------

## Ships (and craft) that touch push apart and are damaged by the impact:
## the impact energy ½·μ·v² (μ the reduced mass, v the closing speed) is
## shared so the lighter, less armoured side takes more of it. Ships joined
## by a gangway and craft near their own carrier don't collide.
func _step_collisions() -> void:
	var now := {}
	# Only ships with hulls (systems) collide with anything: pair each with
	# every later body and every earlier body without systems (each pair once).
	for i in _ship_order.size():
		var a: ShipState = _ships[_ship_order[i]]
		if not a.is_active() or a.systems == null or a.missile != null:
			continue
		for j in _ship_order.size():
			if j == i:
				continue
			var b: ShipState = _ships[_ship_order[j]]
			if not b.is_active() or b.missile != null or (b.systems != null and j < i):
				continue
			var ra := a.config.hit_box_half_extents.length()
			var rb := b.config.hit_box_half_extents.length()
			var ca := a.position + a.orientation * a.config.hit_box_center
			var cb := b.position + b.orientation * b.config.hit_box_center
			if ca.distance_squared_to(cb) > (ra + rb) * (ra + rb):
				continue
			if _is_craft_of(a.id, b.id) or _is_craft_of(b.id, a.id) or _linked(a.id, b.id):
				continue
			var contact := _contact_point(a, b)
			if contact.is_empty():
				continue
			var key := "%s|%s" % [a.id, b.id]
			now[key] = true
			_resolve_collision(a, b, contact.point, not _contacts.has(key))
	_contacts = now


## Craft ids are "<carrier id>_<rack id>" (AirWing).
static func _is_craft_of(craft_id: StringName, carrier_id: StringName) -> bool:
	return String(craft_id).begins_with(String(carrier_id) + "_")


func _linked(a: StringName, b: StringName) -> bool:
	for link in links:
		if link.active() and ((link.attacker_id == a and link.target_id == b) or (link.attacker_id == b and link.target_id == a)):
			return true
	for g in grapples:
		if g.holding() and ((g.attacker_id == a and g.target_id == b) or (g.attacker_id == b and g.target_id == a)):
			return true
	return false


## World point where the two hulls overlap, or {} if they don't. Ships with
## a blueprint test real hull cells; craft are their hit box.
func _contact_point(a: ShipState, b: ShipState) -> Dictionary:
	# Test the points of the smaller (or cell-less) one against the other.
	var probe := a
	var solid := b
	if b.systems == null or (a.systems != null and a.config.hit_box_half_extents.length() < b.config.hit_box_half_extents.length()):
		probe = b
		solid = a
	if solid.systems == null:
		var swap := probe
		probe = solid
		solid = swap
	var points := _probe_points(probe)
	var inv := solid.orientation.inverse()
	var com := solid.systems.stats.center_of_mass_m
	var sum := Vector3.ZERO
	var count := 0
	var grid := solid.systems.grid
	for p in points:
		var body := inv * (p - solid.position)
		var g := (body + com) / ShipGrid.CELL_SIZE_M
		var cell := Vector3i(g.floor())
		if not grid.is_hull(cell):
			continue
		# A wedge is solid only below its slope.
		var mi: int = grid.module_at[cell]
		if grid.is_wedge(mi) and not grid.wedge_contains(mi, g):
			continue
		sum += p
		count += 1
	if count == 0:
		return {}
	return {"point": sum / count}


## World points standing for a ship's volume: hull cell centres, or the
## centre and box corners of a craft.
static func _probe_points(ship: ShipState) -> PackedVector3Array:
	var out := PackedVector3Array()
	if ship.systems != null:
		var grid := ship.systems.grid
		var com := ship.systems.stats.center_of_mass_m
		for cell: Vector3i in grid.module_at:
			var p := ShipGrid.cell_center_m(cell)
			var mi: int = grid.module_at[cell]
			if grid.is_wedge(mi):
				# The middle of the solid part, below the slope.
				p -= grid.wedge_normal(mi) * ShipGrid.CELL_SIZE_M * 0.2
			out.append(ship.position + ship.orientation * (p - com))
		return out
	var c := ship.config.hit_box_center
	var h := ship.config.hit_box_half_extents
	out.append(ship.position + ship.orientation * c)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(ship.position + ship.orientation * (c + Vector3(sx * h.x, sy * h.y, sz * h.z)))
	return out


func _resolve_collision(a: ShipState, b: ShipState, point: Vector3, first: bool) -> void:
	var n := a.position - b.position
	n = n.normalized() if n.length() > 1e-6 else Vector3.UP
	var closing := -(a.velocity - b.velocity).dot(n)
	var ma := a.mass_kg()
	var mb := b.mass_kg()
	# Push apart a little every tick they overlap, by inverse mass.
	var push := 0.05
	a.position += n * push * mb / (ma + mb)
	b.position -= n * push * ma / (ma + mb)
	if closing <= 0.0:
		return  # already separating
	var j := (1.0 + COLLISION_RESTITUTION) * closing / (1.0 / ma + 1.0 / mb)
	_apply_impulse(a, a.orientation.inverse() * (point - a.position), n * j)
	_apply_impulse(b, b.orientation.inverse() * (point - b.position), -n * j)
	if closing < COLLISION_DAMAGE_MIN_MPS:
		return
	var energy := 0.5 * (ma * mb / (ma + mb)) * closing * closing
	# Toughness = mass × local armour: the weaker side takes the larger
	# share, sharply (a fighter ramming a frigate is mostly the fighter).
	var ta := pow(ma * (_armor_at(a, point) + 10.0), COLLISION_SPLIT_POWER)
	var tb := pow(mb * (_armor_at(b, point) + 10.0), COLLISION_SPLIT_POWER)
	var lines := PackedStringArray()
	lines.append_array(_collision_damage(a, point, energy * tb / (ta + tb)))
	lines.append_array(_collision_damage(b, point, energy * ta / (ta + tb)))
	if first:
		_link_events.append("COLLISION — %s and %s at %.1f m/s%s" % [a.display_name, b.display_name, closing,
			(": " + "; ".join(lines)) if not lines.is_empty() else ""])


## Outer armour (mm) of the hull module nearest a world point (0 for craft).
static func _armor_at(ship: ShipState, point: Vector3) -> float:
	if ship.systems == null:
		return 0.0
	var m := _module_near(ship, point)
	return ship.systems.modules[m].armor_mm if m >= 0 else 0.0


static func _module_near(ship: ShipState, point: Vector3) -> int:
	var com := ship.systems.stats.center_of_mass_m
	var body := ship.orientation.inverse() * (point - ship.position) + com
	var best := -1
	var best_d := INF
	for cell: Vector3i in ship.systems.grid.module_at:
		var d := ShipGrid.cell_center_m(cell).distance_squared_to(body)
		if d < best_d:
			best_d = d
			best = ship.systems.grid.module_at[cell]
	return best


## Impact energy (J) taken by one ship: structure of the module there, and
## the external systems mounted within a cell of it; a craft's hull.
func _collision_damage(ship: ShipState, point: Vector3, energy_j: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var points := energy_j * COLLISION_POINTS_PER_J
	if points <= 0.0:
		return lines
	if ship.systems == null:
		if ship.config.hull_hp > 0.0:
			ship.hull_damage += points
			if ship.hull_damage >= ship.config.hull_hp:
				ship.status = ShipState.Status.DESTROYED
				ship.status_time = sim_time
				lines.append("%s destroyed" % ship.display_name)
		return lines
	var sys := ship.systems
	var m := _module_near(ship, point)
	if m >= 0 and sys.damage_module(m, points * 0.6):
		lines.append("%s: module %s wrecked" % [ship.display_name, sys.blueprint.modules[m].id])
	# The blow spreads: neighbouring modules share the rest, more the closer.
	var body := ship.orientation.inverse() * (point - ship.position)
	var com := sys.stats.center_of_mass_m
	var near := {}
	var weight := 0.0
	for cell: Vector3i in sys.grid.module_at:
		var mi: int = sys.grid.module_at[cell]
		if mi == m:
			continue
		var d := (ShipGrid.cell_center_m(cell) - com).distance_to(body)
		if d < COLLISION_SPREAD_M:
			var w := 1.0 - d / COLLISION_SPREAD_M
			near[mi] = maxf(float(near.get(mi, 0.0)), w)
	for mi: int in near:
		weight += float(near[mi])
	for mi: int in near:
		if sys.damage_module(mi, points * 0.4 * float(near[mi]) / maxf(weight, 1e-6)):
			lines.append("%s: module %s wrecked" % [ship.display_name, sys.blueprint.modules[mi].id])
	for e in sys.equipment:
		if e.def.is_external() and not e.destroyed() and e.body_position.distance_to(body) < ShipGrid.CELL_SIZE_M * 2.0:
			if sys.damage_equipment(e, points * 0.6):
				lines.append("%s: %s %s destroyed" % [ship.display_name, e.def.display_name, e.id])
	sys.invalidate()
	ship.config = sys.effective_config()
	return lines


## Rounds never expire. Near the engagement they are integrated like ships;
## far away they coast analytically (see _step_far_rounds).
## Rounds broadphase: every active ship in each grid cell its reach
## overlaps — hit box, plus how far it and the fastest round move in a tick —
## rebuilt once per tick; a round tests only the ships in its segment's
## midpoint cell instead of every ship (rounds × ships was the tick's cost).
const BROAD_CELL_M := 256.0
var _broad: Dictionary = {}  # Vector3i -> Array[ShipState]
const _NO_SHIPS: Array[ShipState] = []


func _broad_cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / BROAD_CELL_M), floori(p.y / BROAD_CELL_M), floori(p.z / BROAD_CELL_M))


func _build_broadphase(round_step_m: float) -> void:
	_broad.clear()
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		if not ship.is_active():
			continue
		var center := (ship.position + ship.prev_position) * 0.5
		var r := ship.config.hit_box_center.length() + ship.config.hit_box_half_extents.length() \
			+ ship.position.distance_to(ship.prev_position) + round_step_m + 1.0
		var lo := _broad_cell(center - Vector3.ONE * r)
		var hi := _broad_cell(center + Vector3.ONE * r)
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var key := Vector3i(x, y, z)
					if not _broad.has(key):
						var list: Array[ShipState] = []
						_broad[key] = list
					(_broad[key] as Array[ShipState]).append(ship)


## Sleeping rounds (play-test batch 6: thousands of fighter rounds): a round
## that can't reach any ship for a while only coasts — no hit test, no tidal
## term — for up to MAX_SLEEP_TICKS. How long: its distance to the nearest
## ship's reach, less SLEEP_MARGIN_M (room for a ship or missile to speed
## up), over its speed plus that ship's. On waking the tidal term over the
## sleep is applied (trapezoid: exact for a linearly changing pull).
const MAX_SLEEP_TICKS := 60
const SLEEP_MARGIN_M := 150.0
var _sleep_ships: Array = []  # [position, reach, speed] of each active ship
var _sleep_center := Vector3.ZERO
var _sleep_radius := 0.0
var _sleep_speed := 0.0
## Profiling: rounds asleep / awake in the last tick.
var rounds_asleep := 0
var rounds_awake := 0


func _collect_sleep_ships() -> void:
	_sleep_ships.clear()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	_sleep_speed = 0.0
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		if not ship.is_active():
			continue
		var reach := ship.config.hit_box_center.length() + ship.config.hit_box_half_extents.length()
		var speed := ship.velocity.length()
		_sleep_ships.append([ship.position, reach, speed])
		lo = lo.min(ship.position - Vector3.ONE * reach)
		hi = hi.max(ship.position + Vector3.ONE * reach)
		_sleep_speed = maxf(_sleep_speed, speed)
	_sleep_center = (lo + hi) * 0.5 if not _sleep_ships.is_empty() else Vector3.ZERO
	_sleep_radius = (hi - lo).length() * 0.5 if not _sleep_ships.is_empty() else 0.0


## Ticks `shot` can sleep (0 = it must be tested). A round in a broadphase
## cell with ships in it is right by one: it stays awake, and isn't
## re-measured for RECHECK_TICKS (measuring it against every ship each tick
## was most of the rounds' cost).
const RECHECK_TICKS := 4


func _safe_ticks(shot: ProjectileState) -> int:
	if _sleep_ships.is_empty():
		return MAX_SLEEP_TICKS
	if shot.recheck_in > 0:
		shot.recheck_in -= 1
		return 0
	if _broad.has(_broad_cell(shot.position)):
		shot.recheck_in = RECHECK_TICKS
		return 0
	var sp := shot.velocity.length()
	# The whole fight at once first: most misses are well clear of it.
	var gap := shot.position.distance_to(_sleep_center) - _sleep_radius - SLEEP_MARGIN_M
	if gap / (sp + _sleep_speed + 1.0) >= MAX_SLEEP_TICKS * fixed_dt:
		return MAX_SLEEP_TICKS
	var best := INF
	for s: Array in _sleep_ships:
		var d := shot.position.distance_to(s[0]) - float(s[1]) - SLEEP_MARGIN_M
		if d <= 0.0:
			shot.recheck_in = RECHECK_TICKS
			return 0
		best = minf(best, d / (sp + float(s[2]) + 1.0))
	return clampi(floori(best / fixed_dt), 0, MAX_SLEEP_TICKS)


## The fastest round awake (or waking) last tick, and any fired since (m/s):
## the broadphase's reach without a pass over every round.
var _awake_speed := 0.0
## Never assume less than the fastest gun's muzzle velocity (4 km/s) plus a
## fast ship: rounds also arrive by firing, returning from far, and tests.
const ROUND_SPEED_FLOOR_MPS := 4500.0


func _step_rounds() -> void:
	var half_dt := fixed_dt * 0.5
	if _rounds.is_empty():
		_broad.clear()
		_awake_speed = 0.0
		return  # nothing to move or test (and no broadphase to build)
	var fastest := maxf(_awake_speed, ROUND_SPEED_FLOOR_MPS)
	_awake_speed = 0.0
	_build_broadphase(fastest * fixed_dt * 1.05 + 1.0)
	_collect_sleep_ships()
	var entry_r2 := 0.0
	if frame != null:
		entry_r2 = body.entry_radius_m() * body.entry_radius_m()
	var survivors: Array[ProjectileState] = []
	rounds_asleep = 0
	rounds_awake = 0
	for shot in _rounds:
		shot.prev_position = shot.position
		if shot.sleep_ticks > 0:
			rounds_asleep += 1
			# Asleep: coast in a straight line; settle the pull on waking.
			shot.position += shot.velocity * fixed_dt
			shot.sleep_t += fixed_dt
			shot.age_s += fixed_dt
			shot.sleep_ticks -= 1
			if shot.sleep_ticks == 0:
				_awake_speed = maxf(_awake_speed, shot.velocity.length())
			if shot.sleep_ticks == 0 and frame != null:
				var t := shot.sleep_t
				var a1 := frame.tidal_acceleration(shot.position, false)
				shot.position += (shot.sleep_a0 / 3.0 + a1 / 6.0) * t * t
				shot.velocity += (shot.sleep_a0 + a1) * 0.5 * t
				shot.tidal_rebase = -1  # moved since a1: work it out afresh
			survivors.append(shot)
			continue
		rounds_awake += 1
		if frame != null:
			# The pull at this tick's start is last tick's end (same origin,
			# same place) unless the frame was rebased since.
			var a_start := shot.tidal_end if shot.tidal_rebase == frame.rebase_count \
				else frame.tidal_acceleration(shot.position, true)
			shot.velocity += a_start * half_dt
			shot.position += shot.velocity * fixed_dt
			shot.tidal_end = frame.tidal_acceleration(shot.position, false)
			shot.tidal_rebase = frame.rebase_count
			shot.velocity += shot.tidal_end * half_dt
		else:
			shot.position += shot.velocity * fixed_dt
		shot.age_s += fixed_dt
		if _resolve_round_hits(shot):
			continue  # consumed (an overpenetrating round re-spawns beyond the ship)
		if frame != null:
			var p := frame.origin_position
			var rx := p.x + shot.position.x
			var ry := p.y + shot.position.y
			var rz := p.z + shot.position.z
			if rx * rx + ry * ry + rz * rz < entry_r2:
				continue  # entered the atmosphere
			if shot.position.length() > FAR_RADIUS_M:
				_to_far(shot)
				continue
		elif shot.position.length() > INERTIAL_MAX_RANGE_M:
			continue  # no orbit to come back on: gone for good
		shot.sleep_ticks = _safe_ticks(shot) if shot.pd_target_round < 0 else 0
		if shot.sleep_ticks == 0:
			_awake_speed = maxf(_awake_speed, shot.velocity.length())
		if shot.sleep_ticks > 0:
			shot.sleep_t = 0.0
			shot.sleep_a0 = frame.tidal_acceleration(shot.position, false) if frame != null else Vector3.ZERO
		survivors.append(shot)
	_rounds = survivors
	_intercept_rounds()
	for s in _continuing:
		_awake_speed = maxf(_awake_speed, s.velocity.length())
	_rounds.append_array(_continuing)
	_continuing.clear()


## Flak: a point-defence round that came within PD_FLAK_RADIUS_M of the
## round it was fired at during this tick (straight-line relative motion
## over the tick) destroys it, and is spent.
func _intercept_rounds() -> void:
	var by_id := {}
	var flak: Array[ProjectileState] = []
	for s in _rounds:
		if s.pd_target_round >= 0:
			flak.append(s)
	if flak.is_empty():
		return
	for s in _rounds:
		by_id[s.id] = s
	var dead := {}
	for f in flak:
		var t: ProjectileState = by_id.get(f.pd_target_round)
		if t == null or dead.has(t.id) or dead.has(f.id):
			continue
		var d0 := f.prev_position - t.prev_position
		var dd := (f.position - t.position) - d0
		var u := clampf(-d0.dot(dd) / maxf(dd.length_squared(), 1e-9), 0.0, 1.0)
		if (d0 + dd * u).length() <= PD_FLAK_RADIUS_M:
			dead[t.id] = true
			dead[f.id] = true
			rounds_intercepted += 1
	if not dead.is_empty():
		_rounds = _rounds.filter(func(s: ProjectileState) -> bool: return not dead.has(s.id))


## Far rounds: each is re-checked once per simulated second (spread over the
## ticks), propagated exactly, and brought back near when its orbit returns
## it to the engagement. Re-entry happens at the predicted time.
func _step_far_rounds() -> void:
	if _far_rounds.is_empty():
		return
	var per_tick := maxi(1, ceili(_far_rounds.size() * fixed_dt / FAR_CHECK_INTERVAL_S))
	var removed := {}
	for i in mini(per_tick, _far_rounds.size()):
		_far_cursor = (_far_cursor + 1) % _far_rounds.size()
		var shot := _far_rounds[_far_cursor]
		if sim_time >= shot.reentry_time:
			removed[shot] = true
			continue
		var state := OrbitElements.propagate(body.mu_m3_s2, shot.far_position, shot.far_velocity, sim_time - shot.far_epoch)
		var rel := state[0].minus(frame.origin_position)
		if rel.length() < NEAR_RADIUS_M:
			shot.far = false
			shot.position = rel.to_vector3()
			shot.prev_position = shot.position
			shot.velocity = state[1].minus(frame.origin_velocity).to_vector3()
			_rounds.append(shot)
			removed[shot] = true
		elif state[0].length() > body.radius_m * ESCAPE_RADII and state[0].dot(state[1]) > 0.0:
			removed[shot] = true  # left on an escape trajectory
	if not removed.is_empty():
		_far_rounds = _far_rounds.filter(func(s: ProjectileState) -> bool: return not removed.has(s))
		_far_cursor = 0
	while _far_rounds.size() > MAX_FAR_ROUNDS:
		_far_rounds.pop_front()  # oldest first; documented cap


func _to_far(shot: ProjectileState) -> void:
	shot.far = true
	shot.far_position = frame.pci_position(shot.position)
	shot.far_velocity = frame.pci_velocity(shot.velocity)
	shot.far_epoch = sim_time
	var orbit := OrbitElements.from_state(body.mu_m3_s2, shot.far_position, shot.far_velocity)
	var t := orbit.time_to_radius_descending(body.entry_radius_m())
	shot.reentry_time = sim_time + t if not is_nan(t) else INF
	_far_rounds.append(shot)


## Finds the earliest ship this shot touched during the tick and resolves the
## hit: damage, momentum transfer, and — if it went right through — a slower
## round continuing beyond the ship. Returns true if the shot was consumed.
func _resolve_round_hits(shot: ProjectileState) -> bool:
	var best_t := INF
	var best_ship: ShipState = null
	var nearby: Array[ShipState] = _broad.get(_broad_cell((shot.prev_position + shot.position) * 0.5), _NO_SHIPS)
	for ship in nearby:
		if ship.id == shot.shooter_id and shot.age_s < ARM_TIME_S:
			continue  # leaving its own muzzle
		if ship.missile_owner == shot.shooter_id:
			continue  # its own side's missile
		if not ship.is_active():
			continue
		if shot.iff_side != &"" and ship.side == shot.iff_side and ship.missile == null:
			continue  # a craft's round: its IFF interlock spares its own side
		# Bounding sphere first (a few flops): most ships in the cell are
		# nowhere near this round's path this tick.
		var p0 := shot.prev_position - ship.prev_position
		var seg := (shot.position - ship.position) - p0
		var u := clampf(-p0.dot(seg) / maxf(seg.length_squared(), 1e-9), 0.0, 1.0)
		var reach := ship.config.hit_box_center.length() + ship.config.hit_box_half_extents.length()
		if (p0 + seg * u).length_squared() > reach * reach:
			continue
		var t := HitTest.round_vs_ship(shot.prev_position, shot.position, ship)
		if t >= 0.0 and ship.systems != null:
			# Narrow phase: the real hull cells, not just the bounding box.
			var inv := ship.orientation.inverse()
			t = Penetration.first_hull_entry(ship.systems,
				inv * (shot.prev_position - ship.prev_position), inv * (shot.position - ship.position))
		if t >= 0.0 and t < best_t:
			best_t = t
			best_ship = ship
	if best_ship == null:
		return false
	var ev := HitEvent.new()
	ev.tick = tick
	ev.round_id = shot.id
	ev.shooter_id = shot.shooter_id
	ev.target_id = best_ship.id
	var inv_q := best_ship.orientation.inverse()
	var rel_start := shot.prev_position - best_ship.prev_position
	var rel_end := shot.position - best_ship.position
	ev.point_body = inv_q * rel_start.lerp(rel_end, best_t)
	var rel_v := shot.velocity - best_ship.velocity
	ev.relative_speed = rel_v.length()
	ev.energy_j = 0.5 * shot.mass_kg() * ev.relative_speed * ev.relative_speed
	var absorbed := 1.0
	if best_ship.systems != null and shot.weapon != null:
		var dir_body := inv_q * rel_v
		ev.report = Penetration.apply(best_ship.systems, ev.point_body, dir_body, shot.weapon.penetration_at(ev.relative_speed))
		_apply_damage(best_ship, ev.report)
		if ev.report.exit_pen_mm > 0.0 and ev.report.entry_pen_mm > 0.0:
			# Through and out: it keeps the speed its leftover penetration implies.
			var keep := pow(ev.report.exit_pen_mm / ev.report.entry_pen_mm, 1.0 / KineticCannonConfig.PENETRATION_SPEED_EXPONENT)
			absorbed = 1.0 - keep
			var out := ProjectileState.new()
			out.id = _next_round_id
			_next_round_id += 1
			out.shooter_id = shot.shooter_id
			out.weapon = shot.weapon
			out.age_s = shot.age_s
			out.position = best_ship.position + best_ship.orientation * ev.report.exit_point_body + rel_v.normalized() * 1.0
			out.prev_position = out.position
			out.velocity = best_ship.velocity + rel_v * keep
			_continuing.append(out)
		elif ev.report.ricochet:
			# Deflected: mirrored about the plate, slower, off the surface.
			var n := best_ship.orientation * ev.report.ricochet_normal_body
			var bounced := (rel_v - 2.0 * rel_v.dot(n) * n) * RICOCHET_KEEP
			var out := ProjectileState.new()
			out.id = _next_round_id
			_next_round_id += 1
			out.shooter_id = shot.shooter_id
			out.weapon = shot.weapon
			out.age_s = shot.age_s
			out.ricochet = true
			out.position = best_ship.position + best_ship.orientation * ev.point_body + n * 1.0
			out.prev_position = out.position
			out.velocity = best_ship.velocity + bounced
			_continuing.append(out)
			# The plate took the change of momentum.
			absorbed = 0.0
			_apply_impulse(best_ship, ev.point_body, (rel_v - bounced) * shot.mass_kg())
	elif best_ship.systems == null and best_ship.config.hull_hp > 0.0 and shot.weapon != null:
		# A craft: its hull absorbs the round's penetration as damage.
		best_ship.hull_damage += shot.weapon.penetration_at(ev.relative_speed)
		if best_ship.hull_damage >= best_ship.config.hull_hp:
			best_ship.status = ShipState.Status.DESTROYED
			best_ship.status_time = sim_time
			GameLog.info("sim", "%s destroyed at T+%.2f s" % [best_ship.display_name, sim_time])
	# Momentum the ship absorbed, applied at the impact point: it is pushed and spun.
	_apply_impulse(best_ship, ev.point_body, rel_v * (shot.mass_kg() * absorbed))
	_hit_events.append(ev)
	best_ship.hits_taken += 1
	return true


## Linear and angular impulse (world-frame J, applied at a body-frame point).
func _apply_impulse(ship: ShipState, point_body: Vector3, impulse_world: Vector3) -> void:
	if impulse_world == Vector3.ZERO:
		return
	ship.velocity += impulse_world / ship.mass_kg()
	var j_body := ship.orientation.inverse() * impulse_world
	ship.angular_velocity += point_body.cross(j_body) / ship.inertia_kgm2()


func _step_links() -> void:
	for link in links:
		var msg := link.step(get_ship(link.attacker_id), get_ship(link.target_id), fixed_dt)
		if msg != "":
			_link_events.append(msg)
	for g in grapples:
		var line := g.step(get_ship(g.attacker_id), get_ship(g.target_id), fixed_dt)
		if line != "":
			_link_events.append(line)
	grapples = grapples.filter(func(g: Grapple) -> bool: return g.holding())
	for b in boardings:
		if b.finished():
			continue
		var before := b.log_count
		b.step(fixed_dt)
		var fresh := mini(b.log_count - before, b.log.size())
		if fresh > 0:
			_link_events.append_array(b.log.slice(b.log.size() - fresh))
		for id in [b.link.attacker_id, b.link.target_id]:
			var ship := get_ship(id)
			if ship != null and ship.systems != null:
				ship.config = ship.systems.effective_config()


## Consequences of a damage report that live outside ShipSystems.
func _apply_damage(ship: ShipState, report: DamageReport) -> void:
	if report.propellant_lost_kg > 0.0 and ship.config.propellant_capacity_kg > 0.0:
		# Tanks drain evenly: a lost tank takes its share of what is left.
		var share := minf(report.propellant_lost_kg / ship.config.propellant_capacity_kg, 1.0)
		var lost := ship.propellant_kg * share
		ship.propellant_kg -= lost
		report.add("%.1f t of propellant lost" % (lost / 1000.0))
	ship.config = ship.systems.effective_config()


func _check_entry_interface() -> void:
	if frame == null:
		return
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		if ship.is_active() and frame.altitude(ship.position) < body.entry_interface_altitude_m:
			ship.status = ShipState.Status.ENTERED_ATMOSPHERE
			ship.status_time = sim_time
			GameLog.info("sim", "%s crossed the %s entry interface at T+%.2f s" % [ship.display_name, body.display_name, sim_time])


func _rebase_if_needed() -> void:
	var anchor := get_ship(anchor_id) if anchor_id != &"" else null
	if anchor == null or anchor.position.length() < REBASE_DISTANCE_M:
		return
	var shift := anchor.position
	if frame != null:
		frame.rebase(shift)
	else:
		_inertial_rebase_offset = _inertial_rebase_offset.plus_v3(shift)
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		ship.position -= shift
		ship.prev_position -= shift
	for shot in _rounds:
		shot.position -= shift
		shot.prev_position -= shift
	for d in decoys:
		d.position = (d.position as Vector3) - shift
