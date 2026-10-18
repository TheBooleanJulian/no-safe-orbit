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
const MAX_STEPS_PER_ADVANCE := 8
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


func _init(p_fixed_dt: float = DEFAULT_FIXED_DT) -> void:
	assert(p_fixed_dt > 0.0)
	fixed_dt = p_fixed_dt


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


## Take a ship out of the simulation (salvaged wrecks). Its rounds fly on.
func remove_ship(id: StringName) -> void:
	_ships.erase(id)
	_inputs.erase(id)
	_ship_order.erase(id)


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


## Run exactly one fixed tick.
func step() -> void:
	if frame != null:
		frame.step(fixed_dt)
	var spawned: Array[ProjectileState] = []
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		ship.snapshot_previous()
		if not ship.is_active():
			continue
		var input: ShipControlInput = _inputs.get(id, _neutral_input)
		_resolve_hold(input)
		ShipDynamics.step(ship, input, fixed_dt, frame)
		_update_cannon(ship, input, spawned)
		if ship.systems != null and ship.systems.tick(ship, fixed_dt):
			ship.config = ship.systems.effective_config()
	tick += 1
	sim_time = tick * fixed_dt
	_step_rounds()
	if frame != null:
		_step_far_rounds()
	_rounds.append_array(spawned)  # fired at end of tick; first move next tick
	_check_entry_interface()
	_rebase_if_needed()


## Feed real elapsed time; runs whole fixed steps and returns the
## interpolation factor in [0, 1) between the last two states.
func advance(frame_delta: float) -> float:
	_accumulator += maxf(frame_delta, 0.0)
	var steps := 0
	while _accumulator + _ACCUMULATOR_EPSILON >= fixed_dt and steps < MAX_STEPS_PER_ADVANCE:
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


func _update_cannon(ship: ShipState, input: ShipControlInput, spawned: Array[ProjectileState]) -> void:
	var cannon := ship.config.cannon
	if cannon == null:
		return
	var muzzles := ship.config.cannon_muzzles_body
	for k in muzzles.size():
		ship.cannon_cooldowns[k] = maxf(ship.cannon_cooldowns[k] - fixed_dt, 0.0)
		if not input.fire or ship.cannon_cooldowns[k] > 1e-9 or ship.cannon_rounds <= 0:
			continue
		if ship.systems != null and not ship.systems.mount_working(k):
			continue  # destroyed or unpowered mount
		var nose := ship.forward()
		var shot := ProjectileState.new()
		shot.id = _next_round_id
		_next_round_id += 1
		shot.shooter_id = ship.id
		shot.weapon = cannon
		shot.position = ship.position + ship.orientation * muzzles[k]
		shot.prev_position = shot.position
		shot.velocity = ship.velocity + nose * cannon.muzzle_velocity_mps
		spawned.append(shot)
		# Recoil conserves momentum and angular momentum: the ship gets −p at
		# the muzzle, so a muzzle off the centre of mass also kicks its spin.
		var p_body := Vector3(0, 0, -cannon.muzzle_velocity_mps * cannon.round_mass_kg)
		ship.velocity -= nose * (cannon.muzzle_velocity_mps * cannon.round_mass_kg / ship.mass_kg())
		ship.angular_velocity -= muzzles[k].cross(p_body) / ship.inertia_kgm2()
		ship.recoil_impulse += cannon.muzzle_velocity_mps * cannon.round_mass_kg
		ship.cannon_rounds -= 1
		ship.rounds_fired += 1
		ship.cannon_cooldowns[k] += cannon.fire_interval_s()


## Rounds never expire. Near the engagement they are integrated like ships;
## far away they coast analytically (see _step_far_rounds).
func _step_rounds() -> void:
	var half_dt := fixed_dt * 0.5
	var entry_r2 := 0.0
	if frame != null:
		entry_r2 = body.entry_radius_m() * body.entry_radius_m()
	var survivors: Array[ProjectileState] = []
	for shot in _rounds:
		shot.prev_position = shot.position
		if frame != null:
			shot.velocity += frame.tidal_acceleration(shot.position, true) * half_dt
			shot.position += shot.velocity * fixed_dt
			shot.velocity += frame.tidal_acceleration(shot.position, false) * half_dt
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
		survivors.append(shot)
	_rounds = survivors
	_rounds.append_array(_continuing)
	_continuing.clear()


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
	for id in _ship_order:
		if id == shot.shooter_id and shot.age_s < ARM_TIME_S:
			continue  # leaving its own muzzle
		var ship: ShipState = _ships[id]
		if not ship.is_active():
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
