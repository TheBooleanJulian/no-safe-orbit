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


func has_ship(id: StringName) -> bool:
	return _ships.has(id)


func get_ship(id: StringName) -> ShipState:
	return _ships.get(id) as ShipState


func ship_ids() -> Array[StringName]:
	return _ship_order.duplicate()


func set_input(id: StringName, input: ShipControlInput) -> void:
	_inputs[id] = input


func projectiles() -> Array[ProjectileState]:
	return _rounds


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
		shot.position = ship.position + ship.orientation * muzzles[k]
		shot.prev_position = shot.position
		shot.velocity = ship.velocity + nose * cannon.muzzle_velocity_mps
		shot.lifetime_s = cannon.round_lifetime_s
		spawned.append(shot)
		# Recoil conserves momentum: m_ship·Δv = m_round·v_muzzle.
		ship.velocity -= nose * (cannon.muzzle_velocity_mps * cannon.round_mass_kg / ship.mass_kg())
		ship.cannon_rounds -= 1
		ship.rounds_fired += 1
		ship.cannon_cooldowns[k] += cannon.fire_interval_s()


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
			continue
		if shot.age_s >= shot.lifetime_s:
			continue
		if frame != null:
			var p := frame.origin_position
			var rx := p.x + shot.position.x
			var ry := p.y + shot.position.y
			var rz := p.z + shot.position.z
			if rx * rx + ry * ry + rz * rz < entry_r2:
				continue  # entered the atmosphere
		survivors.append(shot)
	_rounds = survivors


## Finds the earliest ship this shot touched during the tick; records the hit.
func _resolve_round_hits(shot: ProjectileState) -> bool:
	var best_t := INF
	var best_ship: ShipState = null
	for id in _ship_order:
		if id == shot.shooter_id:
			continue
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
	var rel_start := shot.prev_position - best_ship.prev_position
	var rel_end := shot.position - best_ship.position
	ev.point_body = best_ship.orientation.inverse() * rel_start.lerp(rel_end, best_t)
	ev.relative_speed = (shot.velocity - best_ship.velocity).length()
	var shooter := get_ship(shot.shooter_id)
	var cannon: KineticCannonConfig = shooter.config.cannon if shooter != null else null
	var mass := cannon.round_mass_kg if cannon != null else 0.0
	ev.energy_j = 0.5 * mass * ev.relative_speed * ev.relative_speed
	if best_ship.systems != null and cannon != null:
		var dir_body := best_ship.orientation.inverse() * (shot.velocity - best_ship.velocity)
		ev.report = Penetration.apply(best_ship.systems, ev.point_body, dir_body, cannon.penetration_at(ev.relative_speed))
		_apply_damage(best_ship, ev.report)
	_hit_events.append(ev)
	best_ship.hits_taken += 1
	return true


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
