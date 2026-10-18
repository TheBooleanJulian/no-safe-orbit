class_name ShipSystems
extends RefCounted
## Runtime condition of one ship built from a blueprint (spec §7): armour and
## structure per hull module, condition and power of every installed system,
## room pressure and hatches, the power network and the ship's heat.
## Penetration applies damage; the flight model flies `effective_config()`.
##
## Model (docs/ARCHITECTURE.md → Ship systems):
## - Power: each module has a distribution junction; junctions connect where
##   modules attach. A wrecked module's junction is dead: nothing in it is
##   powered and power cannot pass through it. Each connected network shares
##   its reactors' output; short networks shed loads by priority.
## - Heat: one thermal mass per ship. Generation depends on use; radiators
##   and bare hull reject ∝ (T⁴ − T_sink⁴). Hot reactors throttle, then scram;
##   above DAMAGE_TEMP_K internal systems take damage.
## - Pressure: a penetrated room vents; its intact hatches seal, destroyed
##   hatches let neighbours vent too. Crew can only pass between pressurised
##   rooms.
## - Condition: everything that persists between sorties (damage, armour,
##   breaches, hatches) round-trips through condition() / apply_condition().
## - Field repair: a powered, pressurised workshop the crew can reach patches
##   one damaged system at a time, up to FIELD_REPAIR_LIMIT of its condition.

enum Reactor { NORMAL, THROTTLED, SCRAM }

const NOMINAL_TEMP_K := 300.0
const SINK_TEMP_K := 250.0
const THROTTLE_TEMP_K := 380.0
const SCRAM_TEMP_K := 450.0
const RESTART_TEMP_K := 360.0
const DAMAGE_TEMP_K := 520.0
const THROTTLE_OUTPUT := 0.5
## Thermal mass per kg of ship (J/K/kg): how fast temperature moves.
const HEAT_CAPACITY_J_PER_K_KG := 6.5
## Over-temperature damage to internal systems (hit points per second).
const OVERHEAT_DAMAGE_PER_S := 1.0
## Structure points per kg of module structure.
const STRUCTURE_POINTS_PER_KG := 1.0 / 250.0
## Load-shedding order when a network is short (lower = kept longer).
const PRIORITY := {
	EquipmentDefinition.Kind.RCS: 1,
	EquipmentDefinition.Kind.MAIN_ENGINE: 2,
	EquipmentDefinition.Kind.CANNON: 3,
}
const ROOM_PRIORITY := 0
## Field repairs restore a damaged system to this fraction of its hit points.
const FIELD_REPAIR_LIMIT := 0.75
## Field repair time: fixed setup plus seconds per hit point restored.
const FIELD_REPAIR_SETUP_S := 10.0
const FIELD_REPAIR_S_PER_HP := 1.0
## Which damaged system the crew patch first (lower = sooner).
const FIELD_REPAIR_ORDER := {
	EquipmentDefinition.Kind.REACTOR: 0,
	EquipmentDefinition.Kind.MAIN_ENGINE: 1,
	EquipmentDefinition.Kind.RCS: 2,
	EquipmentDefinition.Kind.CANNON: 3,
	EquipmentDefinition.Kind.RADIATOR: 4,
	EquipmentDefinition.Kind.PROPELLANT_TANK: 5,
}


class EquipmentState:
	var index: int
	var id: String
	var def: EquipmentDefinition
	var module_index: int = -1
	var body_position: Vector3
	var hp: float
	var max_hp: float
	var powered: bool = true

	func destroyed() -> bool:
		return hp <= 0.0

	func working() -> bool:
		return hp > 0.0 and powered


class ModuleState:
	var armor_mm: float
	var structure: float
	var max_structure: float

	func wrecked() -> bool:
		return structure <= 0.0


class RoomState:
	var pressurized: bool = true
	var breached: bool = false
	## Its module's power network is alive and covers the room's draw.
	var powered: bool = true


## A field repair in progress: crew patching one system.
class RepairTask:
	var equipment_id: String
	var total_s: float
	var remaining_s: float
	var target_hp: float

	func progress() -> float:
		return 1.0 - remaining_s / maxf(total_s, 1e-6)


var blueprint: ShipBlueprint
var grid: ShipGrid
var stats: ShipStats
var base_config: ShipConfig
var equipment: Array[EquipmentState] = []
var modules: Array[ModuleState] = []
var rooms: Array[RoomState] = []
var destroyed_hatches: Dictionary = {}  # hatch id -> true
var temperature_k: float = NOMINAL_TEMP_K
var reactor_state: Reactor = Reactor.NORMAL
var power_supply_kw: float = 0.0
var power_demand_kw: float = 0.0
var power_unmet_kw: float = 0.0
var heat_generation_kw: float = 0.0
var heat_rejection_kw: float = 0.0
## Recent events for the HUD, newest last.
var event_log: PackedStringArray = PackedStringArray()
## Field repair under way, or null.
var repair_task: RepairTask

var _attachments: Array[Array] = []
var _config: ShipConfig
var _rounds_seen: int = 0


static func create(bp: ShipBlueprint, p_grid: ShipGrid, p_stats: ShipStats, config: ShipConfig) -> ShipSystems:
	var s := ShipSystems.new()
	s.blueprint = bp
	s.grid = p_grid
	s.stats = p_stats
	s.base_config = config
	s._attachments = p_grid.attachments()
	for i in bp.modules.size():
		var m := ModuleState.new()
		var def := p_grid.module_def(i)
		m.armor_mm = def.armor_mm if def != null else 0.0
		m.max_structure = def.structure_mass_kg * STRUCTURE_POINTS_PER_KG if def != null else 1.0
		m.structure = m.max_structure
		s.modules.append(m)
	for r in bp.rooms:
		s.rooms.append(RoomState.new())
	for i in bp.equipment.size():
		var def := p_grid.equipment_def(i)
		if def == null:
			continue
		var e := EquipmentState.new()
		e.index = i
		e.id = bp.equipment[i].id
		e.def = def
		e.module_index = p_grid.module_at.get(bp.equipment[i].cell, -1)
		e.body_position = p_grid.equipment_position_m(i) - p_stats.center_of_mass_m
		e.max_hp = def.max_hit_points()
		e.hp = e.max_hp
		s.equipment.append(e)
	s.solve_power()
	return s


# --- Queries -----------------------------------------------------------------

func equipment_by_id(id: String) -> EquipmentState:
	for e in equipment:
		if e.id == id:
			return e
	return null


func equipment_at_cell(cell: Vector3i) -> EquipmentState:
	var i: int = grid.equipment_at.get(cell, -1)
	return equipment_by_index(i) if i >= 0 else null


func external_at(cell: Vector3i, face: StringName) -> EquipmentState:
	for e in equipment:
		if e.def.is_external() and blueprint.equipment[e.index].cell == cell and blueprint.equipment[e.index].face == face:
			return e
	return null


func equipment_by_index(index: int) -> EquipmentState:
	for e in equipment:
		if e.index == index:
			return e
	return null


## Whether cannon mount k (index into the config's muzzles) can fire.
func mount_working(k: int) -> bool:
	if k >= base_config.cannon_mount_ids.size():
		return true
	var e := equipment_by_id(base_config.cannon_mount_ids[k])
	return e != null and e.working()


func count(kind: EquipmentDefinition.Kind, working_only: bool) -> int:
	var n := 0
	for e in equipment:
		if e.def.kind == kind and (e.working() if working_only else true):
			n += 1
	return n


## Rooms the crew can reach from a pressurised command room, through
## hatches between pressurised rooms.
func reachable_rooms() -> Dictionary:
	var start := -1
	for i in blueprint.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
		if def != null and def.role == &"command" and rooms[i].pressurized:
			start = i
			break
	var seen := {}
	if start < 0:
		return seen
	seen[start] = true
	var queue := [start]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for h in blueprint.hatches:
			var ra: int = grid.room_at.get(h.a, -1)
			var rb: int = grid.room_at.get(h.b, -1)
			var other := rb if ra == i else (ra if rb == i else -1)
			if other >= 0 and not seen.has(other) and rooms[other].pressurized:
				seen[other] = true
				queue.append(other)
	return seen


## Pressurised rooms the crew can no longer reach.
func cut_off_rooms() -> PackedStringArray:
	var reach := reachable_rooms()
	var out := PackedStringArray()
	for i in rooms.size():
		if rooms[i].pressurized and not reach.has(i):
			out.append(blueprint.rooms[i].id)
	return out


func breached_count() -> int:
	return rooms.filter(func(r: RoomState) -> bool: return not r.pressurized).size()


# --- Damage --------------------------------------------------------------------

## Returns true if this destroyed the equipment.
func damage_equipment(e: EquipmentState, amount: float) -> bool:
	if e.destroyed():
		return false
	e.hp = maxf(e.hp - amount, 0.0)
	if e.destroyed():
		_note("%s %s destroyed" % [e.def.display_name, e.id])
		solve_power()
		return true
	return false


## Returns true if this wrecked the module.
func damage_module(index: int, amount: float) -> bool:
	var m := modules[index]
	if m.wrecked():
		return false
	m.structure = maxf(m.structure - amount, 0.0)
	if m.wrecked():
		_note("Module %s wrecked — its power junction is dead" % blueprint.modules[index].id)
		solve_power()
		return true
	return false


## Opens a room to space; vents neighbours through destroyed hatches.
func breach_room(index: int) -> bool:
	var r := rooms[index]
	if r.breached:
		return false
	r.breached = true
	update_pressure()
	return true


func destroy_hatch(id: String) -> void:
	if not destroyed_hatches.has(id):
		destroyed_hatches[id] = true
		update_pressure()


## Vacuum spreads from breached rooms through destroyed hatches; intact
## hatches seal.
func update_pressure() -> void:
	var vacuum := {}
	var queue := []
	for i in rooms.size():
		if rooms[i].breached:
			vacuum[i] = true
			queue.append(i)
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for h in blueprint.hatches:
			if not destroyed_hatches.has(h.id):
				continue
			var ra: int = grid.room_at.get(h.a, -1)
			var rb: int = grid.room_at.get(h.b, -1)
			var other := rb if ra == i else (ra if rb == i else -1)
			if other >= 0 and not vacuum.has(other):
				vacuum[other] = true
				queue.append(other)
	for i in rooms.size():
		var was := rooms[i].pressurized
		rooms[i].pressurized = not vacuum.has(i)
		if was and not rooms[i].pressurized:
			_note("%s %s depressurised" % [_room_name(i), blueprint.rooms[i].id])


# --- Power ---------------------------------------------------------------------

## Recompute which loads are powered on each junction network.
func solve_power() -> void:
	var n := modules.size()
	var component := []
	component.resize(n)
	component.fill(-1)
	var networks := 0
	for start in n:
		if component[start] >= 0 or modules[start].wrecked():
			continue
		component[start] = networks
		var queue := [start]
		while not queue.is_empty():
			var i: int = queue.pop_front()
			for j in _attachments[i]:
				if component[j] < 0 and not modules[j].wrecked():
					component[j] = networks
					queue.append(j)
		networks += 1
	var supply := []
	supply.resize(networks)
	supply.fill(0.0)
	var loads := []  # [network, priority, kw, EquipmentState or null]
	for e in equipment:
		var net: int = component[e.module_index] if e.module_index >= 0 else -1
		if e.def.power_kw >= 0.0:
			e.powered = net >= 0 and not e.destroyed()
			if e.def.kind == EquipmentDefinition.Kind.REACTOR and e.powered:
				supply[net] += e.def.power_kw * reactor_output()
			continue
		if net < 0 or e.destroyed():
			e.powered = false
			continue
		loads.append([net, PRIORITY.get(e.def.kind, 4), -e.def.power_kw, e])
	for i in blueprint.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
		var cells := ShipGrid.room_cells(blueprint.rooms[i])
		var mi: int = grid.module_at.get(cells[0], -1)
		var net: int = component[mi] if mi >= 0 else -1
		rooms[i].powered = net >= 0
		if def == null or def.power_kw_per_cell >= 0.0:
			continue
		if net >= 0:
			loads.append([net, ROOM_PRIORITY, -def.power_kw_per_cell * cells.size(), null, i])
	loads.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	var remaining: Array = supply.duplicate()
	power_supply_kw = 0.0
	for s in supply:
		power_supply_kw += s
	power_demand_kw = 0.0
	power_unmet_kw = 0.0
	for load in loads:
		var net: int = load[0]
		var kw: float = load[2]
		power_demand_kw += kw
		var ok: bool = remaining[net] >= kw - 1e-6
		if ok:
			remaining[net] -= kw
		else:
			power_unmet_kw += kw
		if load[3] != null:
			(load[3] as EquipmentState).powered = ok
		else:
			rooms[load[4]].powered = ok
	_config = null


func reactor_output() -> float:
	match reactor_state:
		Reactor.THROTTLED:
			return THROTTLE_OUTPUT
		Reactor.SCRAM:
			return 0.0
	return 1.0


# --- Heat ------------------------------------------------------------------------

## Advance heat and reactor state by dt, from what the ship did this tick.
## Returns true if anything changed that alters the flight config.
func tick(ship: ShipState, dt: float) -> bool:
	var cfg := ship.config
	var main_fraction := ShipDynamics.main_thrust_fraction(cfg, ship.last_thrust_body)
	var t := ship.last_thrust_body
	var rcs_fraction := 0.0
	if cfg.thrust_lateral_n > 0.0:
		rcs_fraction = clampf((absf(t.x) + absf(t.y) + maxf(t.z, 0.0)) / (3.0 * cfg.thrust_lateral_n), 0.0, 1.0)
	var shots := ship.rounds_fired - _rounds_seen
	_rounds_seen = ship.rounds_fired
	var load_fraction := clampf((power_demand_kw - power_unmet_kw) / maxf(power_supply_kw, 1.0), 0.0, 1.0)
	var gen := 0.0
	for i in blueprint.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
		if def != null:
			gen += def.heat_kw_per_cell * blueprint.rooms[i].rect.size.x * blueprint.rooms[i].rect.size.y
	var rejection := 0.0
	for m in modules:
		if not m.wrecked():
			rejection += ShipStats.PASSIVE_REJECTION_KW_PER_MODULE
	for e in equipment:
		if e.destroyed():
			continue
		match e.def.kind:
			EquipmentDefinition.Kind.REACTOR:
				gen += e.def.heat_kw * load_fraction * reactor_output()
			EquipmentDefinition.Kind.MAIN_ENGINE:
				gen += e.def.heat_kw * main_fraction if e.powered else 0.0
			EquipmentDefinition.Kind.RCS:
				gen += e.def.heat_kw * rcs_fraction if e.powered else 0.0
			EquipmentDefinition.Kind.RADIATOR:
				rejection += e.def.heat_rejection_kw
	if shots > 0 and cfg.cannon != null:
		var per_shot_kj := 0.0
		for e in equipment:
			if e.def.kind == EquipmentDefinition.Kind.CANNON:
				per_shot_kj = e.def.heat_kw * cfg.cannon.fire_interval_s()
				break
		gen += shots * per_shot_kj / dt
	var t4 := pow(temperature_k, 4.0)
	var scale := maxf(t4 - pow(SINK_TEMP_K, 4.0), 0.0) / (pow(NOMINAL_TEMP_K, 4.0) - pow(SINK_TEMP_K, 4.0))
	heat_generation_kw = gen
	heat_rejection_kw = rejection * scale
	temperature_k += (heat_generation_kw - heat_rejection_kw) * 1000.0 * dt / (HEAT_CAPACITY_J_PER_K_KG * ship.mass_kg())
	var changed := _update_reactor_state()
	if temperature_k >= DAMAGE_TEMP_K:
		for e in equipment:
			if not e.def.is_external() and damage_equipment(e, OVERHEAT_DAMAGE_PER_S * dt):
				changed = true
	if repair_task != null and _advance_repair(dt):
		changed = true
	return changed or _config == null


func _update_reactor_state() -> bool:
	var next := reactor_state
	if temperature_k >= SCRAM_TEMP_K:
		next = Reactor.SCRAM
	elif temperature_k >= THROTTLE_TEMP_K and reactor_state == Reactor.NORMAL:
		next = Reactor.THROTTLED
	elif temperature_k < RESTART_TEMP_K:
		next = Reactor.NORMAL
	if next == reactor_state:
		return false
	reactor_state = next
	_note(["Reactor back to normal output", "Reactor THROTTLED — overheating", "Reactor SCRAM — overheated"][next])
	solve_power()
	return true


# --- Flight ------------------------------------------------------------------------

## The design's flight config, reduced to what still works and is powered.
func effective_config() -> ShipConfig:
	if _config != null:
		return _config
	var cfg: ShipConfig = base_config.duplicate()
	var forward := 0.0
	var engine_torque := Vector3.ZERO
	var rcs: Array[EquipmentState] = []
	for e in equipment:
		if not e.working():
			continue
		match e.def.kind:
			EquipmentDefinition.Kind.MAIN_ENGINE:
				if blueprint.equipment[e.index].face == &"aft":
					forward += e.def.thrust_n
					engine_torque += e.body_position.cross(Vector3(0, 0, -e.def.thrust_n))
			EquipmentDefinition.Kind.RCS:
				rcs.append(e)
	var rcs_thrust := 0.0
	var torque := Vector3.ZERO
	for e in rcs:
		var r := e.body_position
		rcs_thrust += e.def.thrust_n
		torque += e.def.thrust_n * Vector3(Vector2(r.y, r.z).length(), Vector2(r.x, r.z).length(), Vector2(r.x, r.y).length())
	cfg.thrust_forward_n = forward
	cfg.thrust_torque_body = engine_torque
	cfg.thrust_reverse_n = rcs_thrust
	cfg.thrust_lateral_n = rcs_thrust
	cfg.thrust_vertical_n = rcs_thrust
	cfg.max_torque_nm = torque
	for axis in 3:
		if torque[axis] <= 0.0:
			cfg.assist_max_rate_rad_s[axis] = 0.0
	_config = cfg
	return cfg


## One-line state for HUD panels.
func status_line() -> String:
	return "%d/%d eng  %d/%d RCS  %d/%d gun  %d breach" % [
		count(EquipmentDefinition.Kind.MAIN_ENGINE, true), count(EquipmentDefinition.Kind.MAIN_ENGINE, false),
		count(EquipmentDefinition.Kind.RCS, true), count(EquipmentDefinition.Kind.RCS, false),
		count(EquipmentDefinition.Kind.CANNON, true), count(EquipmentDefinition.Kind.CANNON, false),
		breached_count()]


func _room_name(i: int) -> String:
	var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
	return def.display_name if def != null else String(blueprint.rooms[i].def_id)


func _note(text: String) -> void:
	event_log.append(text)
	if event_log.size() > 20:
		event_log.remove_at(0)


# --- Mission state -------------------------------------------------------------

## Why the ship can no longer fight ("" while it still can): every gun is
## out, the power is gone, or nobody can reach a pressurised command room.
func disabled_reason() -> String:
	if power_supply_kw <= 0.0:
		return "no power"
	if reachable_rooms().is_empty():
		return "command room lost"
	if count(EquipmentDefinition.Kind.CANNON, false) > 0 and count(EquipmentDefinition.Kind.CANNON, true) == 0:
		return "all guns out"
	return ""


func is_disabled() -> bool:
	return disabled_reason() != ""


## Fraction of the installed systems' hit points that survive (salvage value).
func intact_fraction() -> float:
	var hp := 0.0
	var max_hp := 0.0
	for e in equipment:
		hp += e.hp
		max_hp += e.max_hp
	return hp / max_hp if max_hp > 0.0 else 0.0


# --- Persistent condition -----------------------------------------------------

## Everything that persists between sorties, keyed by stable blueprint ids.
## Only parts that differ from new are listed. Fractions, not absolutes, so a
## rebalanced definition keeps the same relative wear.
func condition() -> Dictionary:
	var eq := {}
	for e in equipment:
		if e.hp < e.max_hp:
			eq[e.id] = e.hp / e.max_hp
	var mods := {}
	for i in modules.size():
		var m := modules[i]
		var def := grid.module_def(i)
		var armor := m.armor_mm / def.armor_mm if def != null and def.armor_mm > 0.0 else 1.0
		var structure := m.structure / m.max_structure
		if armor < 1.0 or structure < 1.0:
			mods[blueprint.modules[i].id] = {"armor": armor, "structure": structure}
	var breached := []
	for i in rooms.size():
		if rooms[i].breached:
			breached.append(blueprint.rooms[i].id)
	var hatches := destroyed_hatches.keys()
	hatches.sort()
	return {"equipment": eq, "modules": mods, "breached": breached, "hatches": hatches}


## Restore a saved condition. Ids the blueprint no longer has are ignored;
## parts the condition does not list are new.
func apply_condition(c: Dictionary) -> void:
	var eq: Dictionary = c.get("equipment", {})
	for e in equipment:
		e.hp = clampf(float(eq[e.id]), 0.0, 1.0) * e.max_hp if eq.has(e.id) else e.max_hp
	var mods: Dictionary = c.get("modules", {})
	for i in modules.size():
		var def := grid.module_def(i)
		var entry: Dictionary = mods.get(blueprint.modules[i].id, {})
		if def != null:
			modules[i].armor_mm = clampf(float(entry.get("armor", 1.0)), 0.0, 1.0) * def.armor_mm
		modules[i].structure = clampf(float(entry.get("structure", 1.0)), 0.0, 1.0) * modules[i].max_structure
	var breached: Array = c.get("breached", [])
	for i in rooms.size():
		rooms[i].breached = breached.has(blueprint.rooms[i].id)
	destroyed_hatches.clear()
	for h in c.get("hatches", []):
		if blueprint.find(str(h)) != null:
			destroyed_hatches[str(h)] = true
	update_pressure()
	solve_power()


# --- Field repair --------------------------------------------------------------

## Index of a workshop room that is powered, pressurised and reachable, or -1.
func working_workshop() -> int:
	var reach := reachable_rooms()
	for i in blueprint.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
		if def != null and def.role == &"workshop" and reach.has(i) and rooms[i].powered:
			return i
	return -1


## The crew can get to this system: an internal one through its room, an
## external one on EVA from a reachable room in the module it is mounted on.
func can_reach(e: EquipmentState) -> bool:
	var reach := reachable_rooms()
	var cell: Vector3i = blueprint.equipment[e.index].cell
	if not e.def.is_external():
		return reach.has(grid.room_at.get(cell, -1))
	for r in reach:
		var cells := ShipGrid.room_cells(blueprint.rooms[r])
		if grid.module_at.get(cells[0], -2) == e.module_index:
			return true
	return false


## What blocks a field repair right now ("" = one can start).
func field_repair_block_reason() -> String:
	if repair_task != null:
		return "a repair is already under way"
	var has_workshop := false
	for r in blueprint.rooms:
		var def: RoomDefinition = grid.catalog.rooms.get(r.def_id)
		has_workshop = has_workshop or (def != null and def.role == &"workshop")
	if not has_workshop:
		return "no workshop aboard"
	if working_workshop() < 0:
		return "workshop unpowered, depressurised or cut off"
	if field_repair_target() == null:
		return "nothing the crew can patch (destroyed parts need the yard)"
	return ""


## Next damaged (not destroyed) system the crew can reach and patch: by
## FIELD_REPAIR_ORDER, then the most damaged.
func field_repair_target() -> EquipmentState:
	var best: EquipmentState
	for e in equipment:
		if e.destroyed() or e.hp >= FIELD_REPAIR_LIMIT * e.max_hp - 1e-6 or not can_reach(e):
			continue
		if best == null or _repair_rank(e) < _repair_rank(best):
			best = e
	return best


func _repair_rank(e: EquipmentState) -> float:
	return FIELD_REPAIR_ORDER.get(e.def.kind, 9) + e.hp / e.max_hp


## Hit points a field repair of `e` restores.
func field_repair_hp(e: EquipmentState) -> float:
	return maxf(FIELD_REPAIR_LIMIT * e.max_hp - e.hp, 0.0)


## Start patching the next system; returns it (null if blocked).
func start_field_repair() -> EquipmentState:
	if field_repair_block_reason() != "":
		return null
	var e := field_repair_target()
	repair_task = RepairTask.new()
	repair_task.equipment_id = e.id
	repair_task.target_hp = FIELD_REPAIR_LIMIT * e.max_hp
	repair_task.total_s = FIELD_REPAIR_SETUP_S + FIELD_REPAIR_S_PER_HP * field_repair_hp(e)
	repair_task.remaining_s = repair_task.total_s
	_note("Damage control: patching %s %s (%.0f s)" % [e.def.display_name, e.id, repair_task.total_s])
	return e


## Returns true when the task finished (the flight config changes).
func _advance_repair(dt: float) -> bool:
	var e := equipment_by_id(repair_task.equipment_id)
	var why := ""
	if e == null or e.destroyed():
		why = "the part was destroyed"
	elif working_workshop() < 0:
		why = "the workshop is down"
	elif not can_reach(e):
		why = "the crew lost access"
	if why != "":
		_note("Repair of %s interrupted: %s" % [repair_task.equipment_id, why])
		repair_task = null
		return false
	repair_task.remaining_s -= dt
	if repair_task.remaining_s > 0.0:
		return false
	e.hp = maxf(e.hp, repair_task.target_hp)
	_note("%s %s patched to %.0f%%" % [e.def.display_name, e.id, 100.0 * e.hp / e.max_hp])
	repair_task = null
	solve_power()
	return true
