class_name ShipStats
extends RefCounted
## Engineering numbers derived from a blueprint (spec §6 "mass, thrust, power,
## heat, storage summary"), and the ShipConfig the flight simulation uses.
## The same model drives the shipyard readout and the flown ship.
##
## Simplifications (docs/ARCHITECTURE.md):
## - Mass elements are boxes (modules, rooms, internal equipment) or points
##   (external equipment); inertia is diagonal about the centre of mass and
##   computed with full tanks.
## - RCS blocks thrust in all six directions; torque about an axis is
##   thrust × lever arm perpendicular to that axis.
## - Power and heat totals here are the design budget; the running ship
##   resolves them through its power and thermal networks (ShipSystems).

## Passive heat rejection of bare hull, per exposed cell face (kW): it
## radiates from its outer surface.
const PASSIVE_REJECTION_KW_PER_FACE := 0.65
## Armour plate density (t/m³: steel–ceramic composite). One cell face is
## 9 m², so a 40 mm plate is 1.44 t and an 80 mm plate 2.88 t.
const PLATE_DENSITY_KG_M3 := 4000.0
## Power bus conduit (cabling, breakers, trays) per cell.
const BUS_KG_PER_CELL := 200.0
## Assist turn rate = angular acceleration × this (s), clamped below.
const ASSIST_RATE_SECONDS := 1.5
const ASSIST_RATE_MIN := 0.05
const ASSIST_RATE_MAX := 0.9

## Dry mass (no propellant).
var mass_kg: float = 0.0
var propellant_capacity_kg: float = 0.0
## Centre of mass with full tanks, in grid metres.
var center_of_mass_m: Vector3 = Vector3.ZERO
## Principal moments about body X (pitch), Y (yaw), Z (roll) through the CoM,
## with full tanks.
var inertia_kgm2: Vector3 = Vector3.ZERO
var thrust_forward_n: float = 0.0
## Thrust-weighted specific impulse of the main engines and of the RCS (s).
var main_isp_s: float = 0.0
var rcs_isp_s: float = 0.0
## RCS thrust available in each direction.
var thrust_rcs_n: float = 0.0
## Main engines on other faces (ShipConfig.engine_thrust_n layout).
var engine_thrust_n: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
var rcs_count: int = 0
var torque_nm: Vector3 = Vector3.ZERO
## Torque the main engines exert about the CoM at full thrust (signed, body).
var thrust_torque_body: Vector3 = Vector3.ZERO
## |thrust_torque_body| per axis, for the misalignment warning.
var thrust_misalignment_torque_nm: Vector3 = Vector3.ZERO
var power_generation_kw: float = 0.0
var power_draw_kw: float = 0.0
var heat_generation_kw: float = 0.0
var heat_rejection_kw: float = 0.0
var crew_capacity: int = 0
var rounds_capacity: int = 0
## Point-defence rounds the magazine holds (shared by every PD mount).
var pd_rounds_capacity: int = 0
## The magazine mass point defence takes beside guns.
const PD_MAGAZINE_SHARE := 0.15
## Ammunition stowage in the magazines (kg); rounds_capacity follows from it.
var magazine_kg: float = 0.0
var cargo_m3: float = 0.0
## Hull bounds in grid metres.
var hull_bounds_m: AABB = AABB()
## Every cannon mount: equipment ids and grid-metre positions (same order).
var cannon_ids: PackedStringArray = PackedStringArray()
var cannon_positions_m: PackedVector3Array = PackedVector3Array()
var cannon_normals: PackedVector3Array = PackedVector3Array()
## Each mount's turret height off its face (m): its tier's size.
var cannon_heights: PackedFloat32Array = PackedFloat32Array()
var cannon_config: KineticCannonConfig
## Each mount's gun (same order as cannon_ids).
var cannon_configs: Array[KineticCannonConfig] = []
## Point-defence turrets.
var pd_ids: PackedStringArray = PackedStringArray()
var pd_positions_m: PackedVector3Array = PackedVector3Array()
var pd_normals: PackedVector3Array = PackedVector3Array()
var pd_gun: KineticCannonConfig
## Armour plates: total mass and count.
var plate_mass_kg: float = 0.0
var plate_count: int = 0


## Mass of one plate (kg) of `mm` over `area_factor` cell faces.
static func plate_mass(mm: float, area_factor: float = 1.0) -> float:
	return mm / 1000.0 * ShipGrid.CELL_SIZE_M * ShipGrid.CELL_SIZE_M * area_factor * PLATE_DENSITY_KG_M3


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
		s.heat_rejection_kw += PASSIVE_REJECTION_KW_PER_FACE * grid.exterior_face_count(i)
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
		s.magazine_kg += def.ammo_kg_per_cell * cells
		# Hold space is what internal equipment (tanks…) leaves free.
		var free := 0
		for cell in ShipGrid.room_cells(r):
			if not grid.equipment_at.has(cell):
				free += 1
		s.cargo_m3 += def.cargo_m3_per_cell * free
	for key: String in bp.armor:
		var cf := ShipBlueprint.parse_plate_key(key)
		var cell: Vector3i = cf[0]
		var face: StringName = cf[1]
		var kg := plate_mass(float(bp.armor[key]), grid.plate_area_factor(cell, face))
		var n := Vector3(ShipGrid.FACE_NORMALS.get(face, Vector3i.ZERO))
		elements.append({"mass": kg, "center": ShipGrid.cell_center_m(cell) + n * c * 0.5, "size": Vector3.ZERO})
		s.plate_mass_kg += kg
		s.plate_count += 1
	for key: String in bp.bus:
		var bus_cell := ShipBlueprint.parse_cell_key(key)
		elements.append({"mass": BUS_KG_PER_CELL, "center": ShipGrid.cell_center_m(bus_cell), "size": Vector3.ZERO})
	var engines: Array[Vector3] = []
	var engine_thrust: Array[float] = []
	var rcs: Array[Vector3] = []
	var main_flow := 0.0  # Σ F/Isp, for the thrust-weighted Isp
	var rcs_flow := 0.0
	var propellant: Array[Dictionary] = []
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null:
			continue
		var pos := grid.equipment_position_m(i)
		var size_m := Vector3.ZERO
		if not def.is_external():
			var fp := grid.equipment_footprint(i)
			size_m = Vector3(fp.x, 1, fp.y) * c
		elements.append({"mass": def.mass_kg, "center": pos, "size": size_m})
		_add_power(s, def.power_kw)
		s.heat_generation_kw += def.heat_kw
		s.heat_rejection_kw += def.heat_rejection_kw
		match def.kind:
			EquipmentDefinition.Kind.MAIN_ENGINE:
				if bp.equipment[i].face == &"aft":
					s.thrust_forward_n += def.thrust_n
					main_flow += def.thrust_n / def.isp_s
					engines.append(pos)
					engine_thrust.append(def.thrust_n)
				else:
					s.engine_thrust_n[engine_slot(bp.equipment[i].face)] += def.thrust_n
			EquipmentDefinition.Kind.RCS:
				s.thrust_rcs_n += def.thrust_n
				rcs_flow += def.thrust_n / def.isp_s
				s.rcs_count += 1
				rcs.append(pos)
			EquipmentDefinition.Kind.POINT_DEFENCE:
				s.pd_ids.append(bp.equipment[i].id)
				s.pd_positions_m.append(pos)
				s.pd_normals.append(Vector3(ShipGrid.FACE_NORMALS.get(bp.equipment[i].face, Vector3i.UP)))
				s.pd_gun = def.cannon
			EquipmentDefinition.Kind.CANNON:
				s.cannon_ids.append(bp.equipment[i].id)
				s.cannon_positions_m.append(pos)
				s.cannon_normals.append(Vector3(ShipGrid.FACE_NORMALS.get(bp.equipment[i].face, Vector3i(0, 0, -1))))
				s.cannon_heights.append(WorldSimulation.TURRET_HEIGHT_M * def.size_cells)
				s.cannon_configs.append(def.cannon)
				if s.cannon_config == null:
					s.cannon_config = def.cannon
			EquipmentDefinition.Kind.PROPELLANT_TANK:
				s.propellant_capacity_kg += def.propellant_capacity_kg
				propellant.append({"mass": def.propellant_capacity_kg, "center": pos, "size": size_m})
	# Point defence draws from the magazine too (play-test batch 9: "PD
	# draws ammo from magazine (and therefore expandable)"): PD_MAGAZINE_SHARE
	# of its mass when there are guns besides, all of it when there aren't.
	var pd_kg := 0.0
	if s.pd_gun != null and s.magazine_kg > 0.0:
		pd_kg = s.magazine_kg * (PD_MAGAZINE_SHARE if not s.cannon_configs.is_empty() else 1.0)
		s.pd_rounds_capacity = floori(pd_kg / s.pd_gun.round_mass_kg + 1e-6)
	s.rounds_capacity += rounds_from_mass(s.magazine_kg - pd_kg, s.cannon_configs)
	if CoolantLoop.routed(bp):
		# Only radiators piped to a reactor reject heat.
		var cooled := CoolantLoop.cooled_radiators(bp, grid)
		for i in bp.equipment.size():
			var rdef := grid.equipment_def(i)
			if rdef != null and rdef.kind == EquipmentDefinition.Kind.RADIATOR and not cooled.has(i):
				s.heat_rejection_kw -= rdef.heat_rejection_kw
	s.main_isp_s = s.thrust_forward_n / main_flow if main_flow > 0.0 else 0.0
	s.rcs_isp_s = s.thrust_rcs_n / rcs_flow if rcs_flow > 0.0 else 0.0

	for e in elements:
		s.mass_kg += e.mass
	if s.mass_kg <= 0.0:
		return s
	# Centre of mass and inertia with full tanks.
	elements.append_array(propellant)
	var wet := s.mass_kg + s.propellant_capacity_kg
	var weighted := Vector3.ZERO
	for e in elements:
		weighted += (e.center as Vector3) * (e.mass as float)
	s.center_of_mass_m = weighted / wet
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
	for k in engines.size():
		s.thrust_torque_body += (engines[k] - s.center_of_mass_m).cross(Vector3(0, 0, -engine_thrust[k]))
	s.thrust_misalignment_torque_nm = s.thrust_torque_body.abs()
	_room_factors(s, bp, grid)
	s.hull_bounds_m = grid.hull_bounds_m()
	return s


## Bigger rooms are better (play-test batch 9: "incentivise room cells to
## go beyond 1×1"): every cell beyond a room's first adds to what it does,
## with diminishing returns (size_gain) — engine rooms main thrust and
## reactor rooms reactor output, up to ROOM_SIZE_GAIN more (about +11 % for
## a frigate's, +24 % for a destroyer's); a hangar's free deck (cells no bay
## stands on) a faster turnaround of its craft, up to HANGAR_DECK_GAIN more.
## (Bridges, workshops and life support already scale: ShipSystems.room_bonus.)
const ROOM_SIZE_GAIN := 0.25
const ROOM_SIZE_SCALE := 12.0
const HANGAR_DECK_GAIN := 1.0
const HANGAR_DECK_SCALE := 8.0


## 1 + gain · (1 − e^(−cells / scale)): the first extra cells count most.
static func size_gain(extra_cells: int, gain: float, scale: float) -> float:
	return 1.0 + gain * (1.0 - exp(-maxf(extra_cells, 0) / scale))
var engine_room_factor: float = 1.0
var reactor_room_factor: float = 1.0
var hangar_factor: float = 1.0


static func _room_factors(s: ShipStats, bp: ShipBlueprint, grid: ShipGrid) -> void:
	var extra := {}
	var deck := 0
	for r in bp.rooms:
		var cells := r.rect.size.x * r.rect.size.y
		extra[r.def_id] = int(extra.get(r.def_id, 0)) + cells - 1
		var def: RoomDefinition = grid.catalog.rooms.get(r.def_id)
		if def != null and def.role == &"hangar":
			for cell in ShipGrid.room_cells(r):
				if not grid.equipment_at.has(cell):
					deck += 1
	s.engine_room_factor = size_gain(int(extra.get(&"engine_room", 0)), ROOM_SIZE_GAIN, ROOM_SIZE_SCALE)
	s.reactor_room_factor = size_gain(int(extra.get(&"reactor_room", 0)), ROOM_SIZE_GAIN, ROOM_SIZE_SCALE)
	s.hangar_factor = size_gain(deck, HANGAR_DECK_GAIN, HANGAR_DECK_SCALE)
	s.thrust_forward_n *= s.engine_room_factor
	for k in s.engine_thrust_n.size():
		s.engine_thrust_n[k] *= s.engine_room_factor
	s.thrust_torque_body *= s.engine_room_factor
	s.thrust_misalignment_torque_nm = s.thrust_torque_body.abs()
	s.power_generation_kw *= s.reactor_room_factor


static func _add_power(s: ShipStats, kw: float) -> void:
	if kw >= 0.0:
		s.power_generation_kw += kw
	else:
		s.power_draw_kw -= kw


func wet_mass_kg() -> float:
	return mass_kg + propellant_capacity_kg


## Δv of a full load on the main engines (rocket equation), m/s.
func delta_v_m_s() -> float:
	if main_isp_s <= 0.0 or mass_kg <= 0.0:
		return 0.0
	return main_isp_s * ShipDynamics.G0 * log(wet_mass_kg() / mass_kg)


## Flight tuning for this design. Only meaningful when validation has no errors.
func to_ship_config(display_name: String) -> ShipConfig:
	var cfg := ShipConfig.new()
	cfg.display_name = display_name
	cfg.mass_kg = mass_kg
	cfg.unlimited_propellant = false
	cfg.propellant_capacity_kg = propellant_capacity_kg
	cfg.main_isp_s = main_isp_s if main_isp_s > 0.0 else 1.0
	cfg.rcs_isp_s = rcs_isp_s if rcs_isp_s > 0.0 else 1.0
	cfg.inertia_kgm2 = inertia_kgm2
	cfg.thrust_forward_n = thrust_forward_n
	cfg.thrust_reverse_n = thrust_rcs_n
	cfg.thrust_lateral_n = thrust_rcs_n
	cfg.thrust_vertical_n = thrust_rcs_n
	cfg.engine_thrust_n = engine_thrust_n.duplicate()
	cfg.max_torque_nm = torque_nm
	cfg.thrust_torque_body = thrust_torque_body
	var rates := Vector3.ZERO
	for axis in 3:
		if torque_nm[axis] > 0.0:
			rates[axis] = clampf(torque_nm[axis] / inertia_kgm2[axis] * ASSIST_RATE_SECONDS, ASSIST_RATE_MIN, ASSIST_RATE_MAX)
	cfg.assist_max_rate_rad_s = rates
	cfg.hit_box_center = hull_bounds_m.get_center() - center_of_mass_m
	cfg.hit_box_half_extents = hull_bounds_m.size * 0.5
	if cannon_config != null:
		# One magazine feeds every mount; each mount keeps its own gun.
		var copies := {}
		for g in cannon_configs:
			if not copies.has(g):
				var copy: KineticCannonConfig = g.duplicate()
				copy.magazine_rounds = rounds_capacity
				copies[g] = copy
		cfg.cannon = copies[cannon_config]
		var per_mount: Array[KineticCannonConfig] = []
		for g in cannon_configs:
			per_mount.append(copies[g])
		cfg.mount_cannons = per_mount
		var muzzles := PackedVector3Array()
		for p in cannon_positions_m:
			muzzles.append(p - center_of_mass_m)
		cfg.cannon_muzzles_body = muzzles
		cfg.cannon_mount_ids = cannon_ids
		cfg.cannon_mount_normals_body = cannon_normals
		cfg.cannon_turret_heights = cannon_heights
	else:
		cfg.cannon_muzzles_body = PackedVector3Array()
	if pd_gun != null:
		cfg.pd_gun = pd_gun
		cfg.pd_magazine_rounds = pd_rounds_capacity
		var mounts := PackedVector3Array()
		for p in pd_positions_m:
			mounts.append(p - center_of_mass_m)
		cfg.pd_mounts_body = mounts
		cfg.pd_normals_body = pd_normals
		cfg.pd_mount_ids = pd_ids
	return cfg


## ShipConfig.engine_thrust_n slot for an engine on `face`: it pushes the
## ship away from the face (opposite its normal).
static func engine_slot(face: StringName) -> int:
	var push: Vector3i = -ShipGrid.FACE_NORMALS.get(face, Vector3i(0, 0, 1))
	for axis in 3:
		if push[axis] != 0:
			return axis * 2 + (0 if push[axis] > 0 else 1)
	return 4


## Rounds `kg` of stowage holds for these mounts: shared by mount count,
## each calibre's share divided by its round mass.
static func rounds_from_mass(kg: float, guns: Array[KineticCannonConfig]) -> int:
	if guns.is_empty() or kg <= 0.0:
		return 0
	var total := 0
	var shares := magazine_shares(guns)
	for g: KineticCannonConfig in shares:
		total += floori(kg * float(shares[g]) / g.round_mass_kg + 1e-6)
	return total


## Each gun type's share of the stowage mass, by mount count.
static func magazine_shares(guns: Array[KineticCannonConfig]) -> Dictionary:
	var out := {}
	for g in guns:
		out[g] = float(out.get(g, 0.0)) + 1.0 / guns.size()
	return out


## Body-frame position (relative to the CoM) of a grid-metre point.
func to_body(grid_m: Vector3) -> Vector3:
	return grid_m - center_of_mass_m
