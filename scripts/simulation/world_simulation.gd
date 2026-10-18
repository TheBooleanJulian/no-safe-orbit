class_name WorldSimulation
extends RefCounted
## Owns the authoritative simulation and its fixed-timestep clock.
## Frame rate never changes simulation results: `advance()` only decides how
## many fixed `step()`s to run and returns a render interpolation factor.

const DEFAULT_FIXED_DT := 1.0 / 60.0
## Cap on catch-up steps per frame, so a long stall cannot snowball.
const MAX_STEPS_PER_ADVANCE := 8
const _ACCUMULATOR_EPSILON := 1e-9

var fixed_dt: float = DEFAULT_FIXED_DT
var tick: int = 0
var sim_time: float = 0.0
## Real time discarded because a frame needed more than MAX_STEPS_PER_ADVANCE.
var dropped_time: float = 0.0

var _accumulator: float = 0.0
var _ships: Dictionary = {}  # StringName -> ShipState
var _inputs: Dictionary = {}  # StringName -> ShipControlInput
var _ship_order: Array[StringName] = []  # deterministic update order
var _neutral_input := ShipControlInput.neutral()


func _init(p_fixed_dt: float = DEFAULT_FIXED_DT) -> void:
	assert(p_fixed_dt > 0.0)
	fixed_dt = p_fixed_dt


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


## Run exactly one fixed tick.
func step() -> void:
	for id in _ship_order:
		var ship: ShipState = _ships[id]
		ship.snapshot_previous()
		var input: ShipControlInput = _inputs.get(id, _neutral_input)
		ShipDynamics.step(ship, input, fixed_dt)
	tick += 1
	sim_time = tick * fixed_dt


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
