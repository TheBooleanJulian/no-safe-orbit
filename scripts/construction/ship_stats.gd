class_name ShipStats
extends RefCounted
## Engineering numbers derived from a blueprint (spec §6 "mass, thrust, power,
## heat, storage summary"), and the ShipConfig the flight simulation uses.
## The same model drives the shipyard readout and the flown ship.
##
## Simplifications (docs/ARCHITECTURE.md):
## - Mass elements are boxes (modules, rooms, internal equipment) or points
##   (external equipment); inertia is diagonal about the centre of mass.
## - RCS blocks thrust in all six directions; torque about an axis is
##   thrust × lever arm perpendicular to that axis.
## - Power and heat are ship-wide budgets (one shared bus); the power and
##   thermal graphs arrive in Milestone 3.
## - Only the first cannon is flown (the flight model has one weapon).

## Passive heat rejection of bare hull, per module (kW).
const PASSIVE_REJECTION_KW_PER_MODULE := 30.0
## Assist turn rate = angular acceleration × this (s), clamped below.
const ASSIST_RATE_SECONDS := 1.5
const ASSIST_RATE_MIN := 0.05
const ASSIST_RATE_MAX := 0.9

var mass_kg: float = 0.0
## Centre of mass in grid metres.
var center_of_mass_m: Vector3 = Vector3.ZERO
## Principal moments about body X (pitch), Y (yaw), Z (roll) through the CoM.
var inertia_kgm2: Vector3 = Vector3.ZERO
var thrust_forward_n: float = 0.0
## RCS thrust available in each direction.
var thrust_rcs_n: float = 0.0
var rcs_count: int = 0
var torque_nm: Vector3 = Vector3.ZERO
## Torque the main engines exert about the CoM at full thrust (magnitude per axis).
var thrust_misalignment_torque_nm: Vector3 = Vector3.ZERO
var power_generation_kw: float = 0.0
var power_draw_kw: float = 0.0
var heat_generation_kw: float = 0.0
var heat_rejection_kw: float = 0.0
var crew_capacity: int = 0
var rounds_capacity: int = 0
var cargo_m3: float = 0.0
## Hull bounds in grid metres.
var hull_bounds_m: AABB = AABB()
## Index of the cannon that the flight model uses, or -1.
var cannon_index: int = -1
var cannon_position_m: Vector3 = Vector3.ZERO
var cannon_config: KineticCannonConfig


static func compute(bp: ShipBlueprint, grid: ShipGrid) -> ShipStats:
	var s := ShipStats.new()
	var elements: Array[Dictionary] = []  # {mass, center, size}
	var c := ShipGrid.CELL_SIZE_M
	for i in bp.modules.size():
		var def := grid.module_def(i)
		if def == null:
			continue
		var size_m := Vector3(grid.module_size(i)) * c
		elements.append({"mass": def.structure_mass_kg, "center": Vector3(bp.modules[i].position) * c + size_m * 0.5, "size": size_m})
		s.heat_rejection_kw += PASSIVE_REJECTION_KW_PER_MODULE
	for r in bp.rooms:
		var def: RoomDefinition = grid.catalog.rooms.get(r.def_id)
		if def == null:
			continue
		var cells := r.rect.size.x * r.rect.size.y
		var size_m := Vector3(r.rect.size.x, 1, r.rect.size.y) * c
		var corner := Vector3(r.rect.position.x, r.deck, r.rect.position.y) * c
		elements.append({"mass": def.mass_per_cell_kg * cells, "center": corner + size_m * 0.5, "size": size_m})
		_add_power(s, def.power_kw_per_cell * cells)
		s.heat_generation_kw += def.heat_kw_per_cell * cells
		s.crew_capacity += def.crew_capacity_per_cell * cells
		s.rounds_capacity += def.rounds_per_cell * cells
		s.cargo_m3 += def.cargo_m3_per_cell * cells
	var engines: Array[Vector3] = []
	var rcs: Array[Vector3] = []
	var engine_thrust: Array[float] = []
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null:
			continue
		var pos := grid.equipment_position_m(i)
		var size_m := Vector3(def.footprint_cells.x, 1, def.footprint_cells.y) * c if not def.is_external() else Vector3.ZERO
		elements.append({"mass": def.mass_kg, "center": pos, "size": size_m})
		_add_power(s, def.power_kw)
		s.heat_generation_kw += def.heat_kw
		s.heat_rejection_kw += def.heat_rejection_kw
		match def.kind:
			EquipmentDefinition.Kind.MAIN_ENGINE:
				if bp.equipment[i].face == &"aft":
					s.thrust_forward_n += def.thrust_n
					engines.append(pos)
					engine_thrust.append(def.thrust_n)
			EquipmentDefinition.Kind.RCS:
				s.thrust_rcs_n += def.thrust_n
				s.rcs_count += 1
				rcs.append(pos)
			EquipmentDefinition.Kind.CANNON:
				if s.cannon_index < 0:
					s.cannon_index = i
					s.cannon_position_m = pos
					s.cannon_config = def.cannon

	for e in elements:
		s.mass_kg += e.mass
	if s.mass_kg <= 0.0:
		return s
	var weighted := Vector3.ZERO
	for e in elements:
		weighted += (e.center as Vector3) * (e.mass as float)
	s.center_of_mass_m = weighted / s.mass_kg

	for e in elements:
		var r: Vector3 = (e.center as Vector3) - s.center_of_mass_m
		var m: float = e.mass
		var d: Vector3 = e.size
		# Point mass about the CoM (parallel axis) + the element's own box.
		s.inertia_kgm2 += m * Vector3(r.y * r.y + r.z * r.z, r.x * r.x + r.z * r.z, r.x * r.x + r.y * r.y)
		s.inertia_kgm2 += m / 12.0 * Vector3(d.y * d.y + d.z * d.z, d.x * d.x + d.z * d.z, d.x * d.x + d.y * d.y)

	var per_block := s.thrust_rcs_n / maxf(s.rcs_count, 1)
	for p in rcs:
		var r := p - s.center_of_mass_m
		s.torque_nm += per_block * Vector3(Vector2(r.y, r.z).length(), Vector2(r.x, r.z).length(), Vector2(r.x, r.y).length())
	# Engines push along −Z at their mount points: torque = r × F.
	var engine_torque := Vector3.ZERO
	for k in engines.size():
		engine_torque += (engines[k] - s.center_of_mass_m).cross(Vector3(0, 0, -engine_thrust[k]))
	s.thrust_misalignment_torque_nm = engine_torque.abs()
	s.hull_bounds_m = grid.hull_bounds_m()
	return s


static func _add_power(s: ShipStats, kw: float) -> void:
	if kw >= 0.0:
		s.power_generation_kw += kw
	else:
		s.power_draw_kw -= kw


## Flight tuning for this design. Only meaningful when validation has no errors.
func to_ship_config(display_name: String) -> ShipConfig:
	var cfg := ShipConfig.new()
	cfg.display_name = display_name
	cfg.mass_kg = mass_kg
	cfg.inertia_kgm2 = inertia_kgm2
	cfg.thrust_forward_n = thrust_forward_n
	cfg.thrust_reverse_n = thrust_rcs_n
	cfg.thrust_lateral_n = thrust_rcs_n
	cfg.thrust_vertical_n = thrust_rcs_n
	cfg.max_torque_nm = torque_nm
	var rates := Vector3.ZERO
	for axis in 3:
		if torque_nm[axis] > 0.0:
			rates[axis] = clampf(torque_nm[axis] / inertia_kgm2[axis] * ASSIST_RATE_SECONDS, ASSIST_RATE_MIN, ASSIST_RATE_MAX)
	cfg.assist_max_rate_rad_s = rates
	cfg.hit_box_center = hull_bounds_m.get_center() - center_of_mass_m
	cfg.hit_box_half_extents = hull_bounds_m.size * 0.5
	if cannon_config != null:
		var gun: KineticCannonConfig = cannon_config.duplicate()
		gun.magazine_rounds = rounds_capacity
		cfg.cannon = gun
		cfg.cannon_muzzle_body = cannon_position_m - center_of_mass_m
	return cfg


## Body-frame position (relative to the CoM) of a grid-metre point.
func to_body(grid_m: Vector3) -> Vector3:
	return grid_m - center_of_mass_m
