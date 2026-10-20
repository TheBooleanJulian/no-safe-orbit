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
##   A fit damage-control or engineering crew member must walk there first.
## - Crew (CrewRoster): people in a room that vents are killed or wounded.
##   No fit command crew on a pressurised bridge: the ship AI flies it, with
##   limited mobility (thrust and turn rates × SHIP_AI_FACTOR, assist always
##   on); it keeps the guns working at half the rate of fire and with extra
##   spread. No fit weapons crew able to reach a magazine halves the guns'
##   rate of fire (autoloaders only).
## - Power distribution (pips, 6 in total, 0–4 per channel, 2 each to start):
##   SYS = attitude control (RCS torque, turn rates) and repair speed,
##   ENG = translation thrust, WEP = rate of fire. A channel's factor is
##   0.5 + 0.25 × pips: 0 pips = 50 %, 2 = 100 %, 4 = 150 %. Zero-sum: the
##   reactor's output is what it is; diverting moves it between channels.
## - Crew orders: a fit general crew member can be sent to cover a role
##   (bridge, guns, engineering, damage control); they walk to that role's
##   station and take it over on arrival.
## - A reactor at 0 % breaches containment and explodes: modules, systems and
##   rooms within REACTOR_BLAST_RADIUS_M take damage falling off with
##   distance (a second reactor caught in it explodes too).

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
	EquipmentDefinition.Kind.POINT_DEFENCE: 3,
}
const ROOM_PRIORITY := 0
## Field repairs restore a damaged system to this fraction of its hit points.
const FIELD_REPAIR_LIMIT := 0.75
## Field repair time: fixed setup plus seconds per hit point restored.
const FIELD_REPAIR_SETUP_S := 10.0
const FIELD_REPAIR_S_PER_HP := 1.0
## Which damaged system the crew patch first (lower = sooner).
enum Channel { SYS, ENG, WEP }
const CHANNEL_NAMES := ["SYS", "ENG", "WEP"]
const PIPS_TOTAL := 6
const PIPS_MAX := 4
## Station room roles for each crew role a general can be sent to cover.
const ROLE_STATIONS := {
	CrewRoster.Role.COMMAND: [&"command"],
	CrewRoster.Role.ENGINEERING: [&"engineering"],
	CrewRoster.Role.DAMAGE_CONTROL: [&"workshop", &"access"],
	CrewRoster.Role.WEAPONS: [&"magazine", &"command"],
}
## Crew reach external systems on EVA from rooms this close (cells).
const EVA_REACH_CELLS := 2
## A medic treats one wounded crew member in this long (s), with a working
## life support room (the medbay; bigger is faster, see room_bonus) — twice
## as long without one.
const MEDICAL_TREATMENT_S := 25.0
## Room size pays: each cell of a working room past the first adds this to
## what it does (workshop: repairs and hull sealing; life support: the
## medbay; bridge: scans), up to ROOM_BONUS_MAX.
const ROOM_BONUS_PER_CELL := 0.25
const ROOM_BONUS_MAX := 2.0
## Damage control seals a breached room's hull in this long (with a working
## workshop; ÷ its room bonus); life support then refills it with air.
const HULL_SEAL_S := 30.0
## Fire: a hit system can catch fire (FIRE_START_CHANCE). It only burns with
## air — in a vented room it smoulders (up to SMOULDER_S) and flares up if
## the room is re-pressurised. Burning: the room's systems take
## FIRE_HP_PER_S, its crew may be hurt, the ship takes FIRE_HEAT_KW. Every
## room has FOAM_CHARGES of automatic foam (powered rooms), fired
## FOAM_DELAY_S after a fire takes hold; recharged at the yard. Without foam,
## damage control put it out by hand in CREW_FIGHT_S.
const FIRE_START_CHANCE := 0.3
const SMOULDER_S := 90.0
const FIRE_HP_PER_S := 1.5
const FIRE_HEAT_KW := 60.0
const FIRE_WOUND_CHANCE_PER_S := 0.04
const FOAM_CHARGES := 2
const FOAM_DELAY_S := 3.0
const CREW_FIGHT_S := 20.0
## EMP: an exposed system at exposure 1 is reset for EMP_RESET_S (internal
## ones see half, hardening takes its share off), never longer than
## EMP_MAX_S; under 2 s it rides it out.
const EMP_RESET_S := 20.0
const EMP_MAX_S := 90.0
const EMP_INTERNAL_FACTOR := 0.5
## Nuclear: dose = exposure ÷ (1 + armour facing the burst / 60 mm). Crew
## are wounded above 0.4, killed above 1.5 (rising chance); the ship takes
## NUKE_HEAT_K per unit of dose (capped); above exposure 3 the hull facing
## the burst is ablated.
const NUKE_HEAT_K := 120.0
const NUKE_HEAT_MAX_K := 400.0
## A launcher's tube cycle between launches (s): a salvo empties a rack in
## seconds.
const LAUNCHER_CYCLE_S := 0.4
## Without a working sensor mast: eyeballs and backup optics (m).
const VISUAL_RANGE_M := 3000.0
## Ship AI flying without a bridge crew: fraction of thrust and turn rate.
const SHIP_AI_FACTOR := 0.5
## The ship AI still lays the guns, at this fraction of the rate of fire and
## with this much extra spread (degrees, standard deviation).
const SHIP_AI_GUN_RATE_FACTOR := 0.5
const SHIP_AI_DISPERSION_DEG := 0.4
const REACTOR_BLAST_RADIUS_M := 15.0
## Structure destroyed at the blast centre, as a multiple of each module's
## own structure (falling off with distance), and system hit points.
const REACTOR_BLAST_STRUCTURE_FRACTION := 1.2
const REACTOR_BLAST_HP := 90.0
## Rooms whose centre is within this fraction of the radius are breached.
const REACTOR_BLAST_BREACH_FRACTION := 0.6
const NO_GUN_CREW_RATE_FACTOR := 0.5
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
	## Seconds until an EMP-reset system is back online (0 = working).
	var disrupted_s: float = 0.0

	func destroyed() -> bool:
		return hp <= 0.0

	func working() -> bool:
		return hp > 0.0 and powered and disrupted_s <= 0.0


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
	## Crew member doing it, and the part of total_s spent getting there.
	var member_id: String
	var travel_s: float
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
## General quarters: the crew are in spacesuits (Main sets it while a
## hostile is about) — they move through vented rooms and survive a room
## venting around them.
var suited: bool = false
## Docking.hull_ports(), cached: they depend on the blueprint only.
var hull_port_cache: Array = []
var hull_port_cached: bool = false
## Seconds damage control has spent sealing each breached room.
var _seal_s: Dictionary = {}
## Earth Shipyard upgrades (TechTree id -> level); player ships only.
var tech: Dictionary = {}
## Fires by room index: seconds burning (with air) and smouldering.
var fires: Dictionary = {}
## Foam charges used per room (index).
var foam_used: Dictionary = {}
## Missiles fired per launcher (equipment id), and launcher reload timers.
var missiles_used: Dictionary = {}
var launcher_cooldown: Dictionary = {}
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
var crew: CrewRoster
## Taken by a boarding party: it surrenders and stops fighting.
var captured: bool = false
## Reactor explosions not yet shown: {pos_body, radius, lines}.
var explosions: Array[Dictionary] = []
## Power distribution pips per Channel.
var pips: Array[int] = [2, 2, 2]
## Player's pick for the next field repair ("" = default order).
var preferred_repair_id: String = ""
## Crew walking to take over a role: member id -> {role, room, left_s}.
var crew_orders: Dictionary = {}
## Loads the crew switched off to reroute power (equipment id -> true).
var switched_off: Dictionary = {}
## Compartments sealed off by order (room index -> true): nobody passes
## through them; whoever is inside stays.
var isolated_rooms: Dictionary = {}
## Armour plates as they are now (worn by hits): plate key -> mm.
var plates: Dictionary = {}
## Power conduit cells cut by hits (cell key -> true).
var bus_cut: Dictionary = {}
## Coolant pipe cells cut by hits (cell key -> true), and the radiators still
## on a reactor's loop (null = recompute).
var coolant_cut: Dictionary = {}
var _cooled: Variant = null
## Seeded per design: chance-based damage (conduit cuts) repeats exactly.
var damage_rng := RandomNumberGenerator.new()
## Bus networks by cell (cell key -> network), from the last power solve;
## empty when the design has no routed bus.
var bus_network: Dictionary = {}

var _attachments: Array[Array] = []
var _treatment_s := 0.0
## Exposed faces per module (passive cooling).
var _module_faces: PackedInt32Array = PackedInt32Array()
var _config: ShipConfig
var _rounds_seen: int = 0


static func create(bp: ShipBlueprint, p_grid: ShipGrid, p_stats: ShipStats, config: ShipConfig) -> ShipSystems:
	var s := ShipSystems.new()
	s.blueprint = bp
	s.grid = p_grid
	s.stats = p_stats
	s.base_config = config
	s.damage_rng.seed = hash(bp.name) + bp.modules.size()
	s._attachments = p_grid.attachments()
	for i in bp.modules.size():
		s._module_faces.append(p_grid.exterior_face_count(i) if p_grid.module_def(i) != null else 0)
	for i in bp.modules.size():
		var m := ModuleState.new()
		var def := p_grid.module_def(i)
		m.armor_mm = def.armor_mm if def != null else 0.0
		m.max_structure = def.structure_mass_kg * STRUCTURE_POINTS_PER_KG if def != null else 1.0
		m.structure = m.max_structure
		s.modules.append(m)
	for r in bp.rooms:
		s.rooms.append(RoomState.new())
	for key in bp.armor:
		s.plates[key] = float(bp.armor[key])
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
	s.crew = CrewRoster.default_for(bp, p_grid, p_stats)
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
		if e.def.is_external() and blueprint.equipment[e.index].face == face and grid.external_cells(e.index).has(cell):
			return e
	return null


## Where an internal craft bay's craft leave and come back: the outside of
## the nearest open face of its room (the underside first), as [position,
## outward normal] in the body frame. External racks use their own face.
func launch_door(e: EquipmentState) -> Array:
	var pe := blueprint.equipment[e.index]
	if e.def.is_external():
		return [e.body_position, Vector3(ShipGrid.FACE_NORMALS[pe.face])]
	var cells: Array = grid.equipment_cells(e.index)
	var r: int = grid.room_at.get(pe.cell, -1)
	if r >= 0:
		for c in ShipGrid.room_cells(blueprint.rooms[r]):
			if not cells.has(c):
				cells.append(c)
	var com := stats.center_of_mass_m
	for face: StringName in [&"ventral", &"port", &"starboard", &"dorsal", &"aft", &"fore"]:
		for c: Vector3i in cells:
			if grid.is_exterior_face(c, face) and not grid.slope_faces(c).has(face):
				var n := Vector3(ShipGrid.FACE_NORMALS[face])
				return [ShipGrid.cell_center_m(c) + n * ShipGrid.CELL_SIZE_M * 0.5 - com, n]
	return [e.body_position, Vector3.DOWN]


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
			if other >= 0 and not seen.has(other) and (suited or rooms[other].pressurized):
				seen[other] = true
				queue.append(other)
		for other: int in grid.open_rooms.get(i, []):
			if not seen.has(other) and (suited or rooms[other].pressurized):
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
	_state_changed()
	if e.destroyed():
		return false
	e.hp = maxf(e.hp - amount, 0.0)
	if amount >= 5.0 and not e.def.is_external():
		var room: int = grid.room_at.get(blueprint.equipment[e.index].cell, -1)
		if room >= 0 and not fires.has(room) and damage_rng.randf() < FIRE_START_CHANCE:
			fires[room] = {"burn_s": 0.0, "smoulder_s": 0.0}
			_note("FIRE in %s %s (%s %s hit)" % [_room_name(room), blueprint.rooms[room].id, e.def.display_name, e.id])
	if e.destroyed():
		_note("%s %s destroyed" % [e.def.display_name, e.id])
		solve_power()
		if e.def.kind == EquipmentDefinition.Kind.REACTOR:
			_explode(e)
		return true
	return false


## Reactor containment failure: blast damage falling off linearly with
## distance from the reactor.
func _explode(src: EquipmentState) -> void:
	var blast := {"pos_body": src.body_position, "radius": REACTOR_BLAST_RADIUS_M,
		"lines": PackedStringArray(["%s %s CONTAINMENT FAILURE — explosion" % [src.def.display_name, src.id]])}
	explosions.append(blast)
	_note(blast.lines[0])
	var c := ShipGrid.CELL_SIZE_M
	var com := stats.center_of_mass_m
	for i in modules.size():
		var center := Vector3(blueprint.modules[i].position) * c + Vector3(grid.module_size(i)) * c * 0.5 - com
		var k := _blast_falloff(center, src.body_position)
		if k > 0.0 and damage_module(i, modules[i].max_structure * REACTOR_BLAST_STRUCTURE_FRACTION * k):
			blast.lines.append("Module %s wrecked by the blast" % blueprint.modules[i].id)
	for i in rooms.size():
		var cells := ShipGrid.room_cells(blueprint.rooms[i])
		var center := Vector3.ZERO
		for cell in cells:
			center += ShipGrid.cell_center_m(cell)
		center = center / cells.size() - com
		if center.distance_to(src.body_position) < REACTOR_BLAST_RADIUS_M * REACTOR_BLAST_BREACH_FRACTION and breach_room(i):
			blast.lines.append("%s %s breached by the blast" % [_room_name(i), blueprint.rooms[i].id])
	for e in equipment:
		if e == src or e.destroyed():
			continue
		var k := _blast_falloff(e.body_position, src.body_position)
		if k > 0.0 and damage_equipment(e, REACTOR_BLAST_HP * k):
			blast.lines.append("%s %s destroyed by the blast" % [e.def.display_name, e.id])


func _blast_falloff(p: Vector3, center: Vector3) -> float:
	return clampf(1.0 - p.distance_to(center) / REACTOR_BLAST_RADIUS_M, 0.0, 1.0)


## Explosions since the last call (for flashes and HUD).
func take_explosions() -> Array[Dictionary]:
	var out := explosions
	explosions = []
	return out


## Returns true if this wrecked the module.
func damage_module(index: int, amount: float) -> bool:
	_state_changed()
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
	_state_changed()
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
		# One space: a breach vents both halves.
		for other: int in grid.open_rooms.get(i, []):
			if not vacuum.has(other):
				vacuum[other] = true
				queue.append(other)
	for i in rooms.size():
		var was := rooms[i].pressurized
		rooms[i].pressurized = not vacuum.has(i)
		if was and not rooms[i].pressurized:
			var hurt: Vector2i = crew.vent(i) if crew != null and not suited else Vector2i.ZERO
			_note("%s %s depressurised%s" % [_room_name(i), blueprint.rooms[i].id,
				" — %d killed, %d wounded" % [hurt.x, hurt.y] if hurt != Vector2i.ZERO else ""])
			_config = null


# --- Power ---------------------------------------------------------------------

## Recompute which loads are powered on each junction network.
func solve_power() -> void:
	_state_changed()
	if not blueprint.bus.is_empty():
		_solve_bus_power()
		return
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
		if net < 0 or e.destroyed() or switched_off.has(e.id):
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


## Power over a player-routed bus: conduit cells joined face to face (also
## between decks) form networks; a cut conduit or a wrecked module's cells
## carry nothing. A system or room is on a network when one of its cells
## is. A network's reactors feed its loads only through a working power
## distribution unit on it; short networks shed loads by priority.
func _solve_bus_power() -> void:
	bus_network.clear()
	var networks := 0
	for key: String in blueprint.bus:
		if bus_network.has(key) or not _bus_alive(key):
			continue
		bus_network[key] = networks
		var queue := [key]
		while not queue.is_empty():
			var cell := ShipBlueprint.parse_cell_key(queue.pop_front())
			for face: StringName in ShipGrid.FACE_NORMALS:
				var nk := ShipBlueprint.cell_key(cell + ShipGrid.FACE_NORMALS[face])
				if blueprint.bus.has(nk) and not bus_network.has(nk) and _bus_alive(nk):
					bus_network[nk] = networks
					queue.append(nk)
		networks += 1
	var distributing := []
	distributing.resize(networks)
	distributing.fill(false)
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.POWER_DISTRIBUTION and not e.destroyed() and not switched_off.has(e.id):
			var net := _network_of_equipment(e)
			if net >= 0:
				distributing[net] = true
	var supply := []
	supply.resize(networks)
	supply.fill(0.0)
	var loads := []
	for e in equipment:
		var net := _network_of_equipment(e)
		if e.def.power_kw == 0.0:
			e.powered = not e.destroyed()  # passive: needs no conduit
			continue
		if e.def.power_kw > 0.0:
			e.powered = net >= 0 and not e.destroyed()
			if e.def.kind == EquipmentDefinition.Kind.REACTOR and e.powered and distributing[net]:
				supply[net] += e.def.power_kw * reactor_output()
			continue
		if net < 0 or e.destroyed() or switched_off.has(e.id):
			e.powered = false
			continue
		loads.append([net, PRIORITY.get(e.def.kind, 4), -e.def.power_kw, e])
	for i in blueprint.rooms.size():
		var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
		var cells := ShipGrid.room_cells(blueprint.rooms[i])
		var net := _network_of_cells(cells)
		if def == null or def.power_kw_per_cell >= 0.0:
			rooms[i].powered = true  # draws nothing
			continue
		rooms[i].powered = net >= 0 and distributing[net]
		if net >= 0:
			loads.append([net, ROOM_PRIORITY, -def.power_kw_per_cell * cells.size(), null, i])
		else:
			rooms[i].powered = false
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


func _bus_alive(key: String) -> bool:
	if bus_cut.has(key):
		return false
	var mi: int = grid.module_at.get(ShipBlueprint.parse_cell_key(key), -1)
	return mi >= 0 and not modules[mi].wrecked()


func _network_of_cells(cells: Array) -> int:
	for c in cells:
		var net: int = bus_network.get(ShipBlueprint.cell_key(c), -1)
		if net >= 0:
			return net
	return -1


func _network_of_equipment(e: EquipmentState) -> int:
	if e.def.is_external():
		return bus_network.get(ShipBlueprint.cell_key(blueprint.equipment[e.index].cell), -1)
	return _network_of_cells(grid.equipment_cells(e.index))


## A radiator works only on a coolant loop that reaches a reactor (designs
## without coolant pipes: always).
func radiator_cooled(e: EquipmentState) -> bool:
	if not CoolantLoop.routed(blueprint):
		return true
	if _cooled == null:
		_cooled = CoolantLoop.cooled_radiators(blueprint, grid, coolant_cut)
	return (_cooled as Dictionary).has(e.index)


## A round cut the coolant pipe in `cell`. True if it was intact.
func cut_coolant(cell: Vector3i) -> bool:
	var key := ShipBlueprint.cell_key(cell)
	if not blueprint.coolant.has(key) or coolant_cut.has(key):
		return false
	coolant_cut[key] = true
	_cooled = null
	return true


## A round severed the conduit in `cell`. True if it was intact.
func cut_bus(cell: Vector3i) -> bool:
	var key := ShipBlueprint.cell_key(cell)
	if not blueprint.bus.has(key) or bus_cut.has(key):
		return false
	bus_cut[key] = true
	solve_power()
	return true


func reactor_output() -> float:
	match reactor_state:
		Reactor.THROTTLED:
			return THROTTLE_OUTPUT * tech_factor("reactor")
		Reactor.SCRAM:
			return 0.0
	return tech_factor("reactor")


## Multiplier from an Earth Shipyard upgrade (1 without it).
func tech_factor(id: String) -> float:
	return TechTree.factor(id, int(tech.get(id, 0)))


## The member on the field repair works faster with skill.
func _repairer_skill() -> float:
	var m: CrewRoster.Member = crew.by_id(repair_task.member_id) if crew != null and repair_task != null else null
	return 1.0 + 0.2 * m.skill if m != null else 1.0


## Use the vessel's hired crew instead of the standard complement.
func use_crew_plan(plan: Array) -> void:
	if plan.is_empty():
		return
	crew = CrewRoster.from_plan(blueprint, grid, stats, plan)
	_config = null


## FTL-style: send crew member `id` to take on `role` at its station (they
## walk there; the role changes when they arrive). "" or why not.
func reassign(id: String, role: int) -> String:
	var m: CrewRoster.Member = crew.by_id(id) if crew != null else null
	if m == null or not m.available() or m.location < 0:
		return "%s is not free" % id
	if m.role == role:
		return "%s already is %s" % [m.label(), CrewRoster.ROLE_NAMES[role]]
	var dest := station_for(role) if ROLE_STATIONS.has(role) else m.location
	if dest < 0:
		return "no pressurised %s station" % CrewRoster.ROLE_NAMES[role]
	var path := route(m.location, dest)
	if path.is_empty():
		return "%s can't get to the %s station" % [m.label(), CrewRoster.ROLE_NAMES[role]]
	m.busy = true
	crew_orders[m.id] = {"role": role, "room": dest, "left_s": (path.size() - 1) * CrewRoster.ROOM_TRANSIT_S}
	_note("%s heading off to %s — %.0f s" % [m.label(), CrewRoster.ROLE_NAMES[role], crew_orders[m.id].left_s])
	return ""


# --- Heat ------------------------------------------------------------------------

## Advance heat and reactor state by dt, from what the ship did this tick.
## Returns true if anything changed that alters the flight config.
func tick(ship: ShipState, dt: float) -> bool:
	_state_changed()
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
	for i in modules.size():
		if not modules[i].wrecked():
			rejection += ShipStats.PASSIVE_REJECTION_KW_PER_FACE * _module_faces[i]
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
				if radiator_cooled(e):
					rejection += e.def.heat_rejection_kw * tech_factor("radiators")
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
	if repair_task != null and _advance_repair(dt * channel_factor(Channel.SYS) * tech_factor("damage_control") * _repairer_skill()):
		changed = true
	if _advance_crew_orders(dt):
		changed = true
	if _advance_medical(dt):
		changed = true
	if _advance_hull_sealing(dt):
		changed = true
	if _advance_fires(dt):
		changed = true
	if _advance_disruption(dt):
		changed = true
	for id in launcher_cooldown.keys():
		launcher_cooldown[id] = maxf(float(launcher_cooldown[id]) - dt, 0.0)
	_state_changed()
	return changed or _config == null


## EMP-reset systems come back one by one.
func _advance_disruption(dt: float) -> bool:
	var back := false
	for e in equipment:
		if e.disrupted_s > 0.0:
			e.disrupted_s = maxf(e.disrupted_s - dt, 0.0)
			if e.disrupted_s <= 0.0:
				_note("%s %s back online after the EMP" % [e.def.display_name, e.id])
				back = true
	if back:
		solve_power()
		_config = null
	return back


## Systems still resetting after an EMP: [{id, name, left_s}].
func disrupted() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in equipment:
		if e.disrupted_s > 0.0 and not e.destroyed():
			out.append({"id": e.id, "name": e.def.display_name, "left_s": e.disrupted_s})
	return out


## An EMP at `exposure` (1 = the warhead's effect radius). Returns what reset.
func emp(exposure: float) -> PackedStringArray:
	_state_changed()
	var lines := PackedStringArray()
	for e in equipment:
		if e.destroyed() or not EquipmentDefinition.ELECTRONIC.has(e.def.kind):
			continue
		var k := exposure * (1.0 - clampf(e.def.emp_hardening, 0.0, 1.0)) * (1.0 if e.def.is_external() else EMP_INTERNAL_FACTOR)
		var s := minf(EMP_RESET_S * k, EMP_MAX_S)
		if s < 2.0:
			continue
		e.disrupted_s = maxf(e.disrupted_s, s)
		lines.append("%s %s reset (%.0f s)" % [e.def.display_name, e.id, s])
	if not lines.is_empty():
		_note("EMP: %s" % "; ".join(lines))
		solve_power()
		_config = null
	return lines


## Mean armour (skin + plates, mm) on the faces turned towards `dir_body`.
func facing_armor_mm(dir_body: Vector3) -> float:
	var total := 0.0
	var n := 0
	for key: String in plates:
		var cf := ShipBlueprint.parse_plate_key(key)
		if Vector3(ShipGrid.FACE_NORMALS.get(cf[1], Vector3i.ZERO)).dot(dir_body) > 0.5:
			total += float(plates[key])
			n += 1
	var skin := 0.0
	for m in modules:
		skin += m.armor_mm
	skin /= maxf(modules.size(), 1)
	return skin + (total / n if n > 0 else 0.0)


## A nuclear burst at `exposure` from body direction `dir_body` (towards the
## burst): radiation on the crew, heat, hull ablation close in, and an EMP.
func nuclear(exposure: float, dir_body: Vector3) -> PackedStringArray:
	_state_changed()
	var dir := dir_body.normalized()
	var dose := exposure / (1.0 + facing_armor_mm(dir) / 60.0)
	var lines := PackedStringArray(["Nuclear burst: exposure %.1f, dose %.1f behind %.0f mm" % [exposure, dose, facing_armor_mm(dir)]])
	if crew != null:
		var killed := 0
		var hurt := 0
		for m in crew.members:
			if m.state == CrewRoster.State.DEAD or m.location < 0:
				continue
			var r := damage_rng.randf()
			if r < clampf(dose - 1.5, 0.0, 1.0):
				m.state = CrewRoster.State.DEAD
				killed += 1
			elif r < clampf(dose - 0.4, 0.0, 1.0) and m.state == CrewRoster.State.FIT:
				m.state = CrewRoster.State.WOUNDED
				hurt += 1
		if killed + hurt > 0:
			lines.append("radiation: %d killed, %d sick" % [killed, hurt])
	temperature_k += minf(NUKE_HEAT_K * dose, NUKE_HEAT_MAX_K)
	if exposure > 3.0:
		var c := ShipGrid.CELL_SIZE_M
		var com := stats.center_of_mass_m
		for i in modules.size():
			var center := Vector3(blueprint.modules[i].position) * c + Vector3(grid.module_size(i)) * c * 0.5 - com
			if center.normalized().dot(dir) > 0.2 and damage_module(i, modules[i].max_structure * 0.12 * (exposure - 3.0)):
				lines.append("Module %s ablated away" % blueprint.modules[i].id)
		for key: String in plates.keys():
			var cf := ShipBlueprint.parse_plate_key(key)
			if Vector3(ShipGrid.FACE_NORMALS.get(cf[1], Vector3i.ZERO)).dot(dir) > 0.5:
				plates[key] = maxf(float(plates[key]) - 4.0 * exposure, 0.0)
	lines.append_array(emp(exposure * 1.5))
	_note("; ".join(lines))
	_config = null
	return lines


## A warhead's blast at a body point: modules and systems within `radius`
## take damage falling off with distance; rooms near the centre breach.
func blast_at(pos_body: Vector3, radius: float, structure_fraction: float, hp: float, title: String) -> Dictionary:
	var blast := {"pos_body": pos_body, "radius": radius, "lines": PackedStringArray([title])}
	# Small warheads (a saturation swarm) are shown as bursts, not as big
	# explosions with their own notices.
	if radius >= SMALL_BLAST_M:
		explosions.append(blast)
	var c := ShipGrid.CELL_SIZE_M
	var com := stats.center_of_mass_m
	for i in modules.size():
		var center := Vector3(blueprint.modules[i].position) * c + Vector3(grid.module_size(i)) * c * 0.5 - com
		var k := clampf(1.0 - center.distance_to(pos_body) / radius, 0.0, 1.0)
		if k > 0.0 and damage_module(i, modules[i].max_structure * structure_fraction * k):
			blast.lines.append("Module %s wrecked" % blueprint.modules[i].id)
	for i in rooms.size():
		var cells := ShipGrid.room_cells(blueprint.rooms[i])
		var center := Vector3.ZERO
		for cell in cells:
			center += ShipGrid.cell_center_m(cell)
		center = center / cells.size() - com
		if center.distance_to(pos_body) < radius * 0.6 and breach_room(i):
			blast.lines.append("%s %s breached" % [_room_name(i), blueprint.rooms[i].id])
	for e in equipment:
		var k := clampf(1.0 - e.body_position.distance_to(pos_body) / radius, 0.0, 1.0)
		if k > 0.0 and not e.destroyed() and damage_equipment(e, hp * k):
			blast.lines.append("%s %s destroyed" % [e.def.display_name, e.id])
	_note("; ".join(blast.lines))
	return blast


## Blasts smaller than this (m) don't count as explosions for the views.
const SMALL_BLAST_M := 6.0


## Missiles left in a launcher.
func missiles_left(e: EquipmentState) -> int:
	return maxi(e.def.missile_capacity - int(missiles_used.get(e.id, 0)), 0) if e.def.missile != null else 0


## A launcher that can fire now (working, loaded, tube cycled), or null;
## `warhead` (a MissileConfig.Warhead) picks only that kind, -1 any.
func ready_launcher(warhead: int = -1) -> EquipmentState:
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER and e.working() and missiles_left(e) > 0 \
				and float(launcher_cooldown.get(e.id, 0.0)) <= 0.0 and (warhead < 0 or e.def.missile.warhead == warhead):
			return e
	return null


## Flares left in a decoy launcher (their use is kept with the missiles').
func decoys_left(e: EquipmentState) -> int:
	return maxi(e.def.decoy_capacity - int(missiles_used.get(e.id, 0)), 0) if e.def.kind == EquipmentDefinition.Kind.DECOY_LAUNCHER else 0


## Working decoy launchers with flares left and their tube cycled.
func ready_decoy_launchers() -> Array[EquipmentState]:
	var out: Array[EquipmentState] = []
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.DECOY_LAUNCHER and e.working() and decoys_left(e) > 0 \
				and float(launcher_cooldown.get(e.id, 0.0)) <= 0.0:
			out.append(e)
	return out


## Flares aboard in working launchers.
func decoys_aboard() -> int:
	var n := 0
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.DECOY_LAUNCHER and not e.destroyed():
			n += decoys_left(e)
	return n


## This ship's own jamming: its working jammers' strength (0 = none).
func jamming_strength() -> float:
	var j := 0.0
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.JAMMER and e.working() and not switched_off.has(e.id):
			j += e.def.jam_strength
	return j


## How much jamming the best working sensor mast shrugs off (0–1): a
## hardened mast's EMP hardening also filters noise.
func sensor_ew_resist() -> float:
	var best := 0.0
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.SENSOR and e.working():
			best = maxf(best, e.def.emp_hardening)
	return best


## The launcher `id` if it can fire now, else null.
func launcher_if_ready(id: String) -> EquipmentState:
	for e in equipment:
		if e.id == id:
			if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER and e.working() and missiles_left(e) > 0 \
					and float(launcher_cooldown.get(e.id, 0.0)) <= 0.0:
				return e
			return null
	return null


## Working, loaded launchers of `warhead` (-1 any): the pods a volley fires.
func loaded_launchers(warhead: int = -1) -> Array[EquipmentState]:
	var out: Array[EquipmentState] = []
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER and e.def.missile != null and e.working() \
				and missiles_left(e) > 0 and (warhead < 0 or e.def.missile.warhead == warhead):
			out.append(e)
	return out


## Missiles in launchers that can fire them (working: powered, not reset by
## an EMP, not destroyed); `warhead` -1 = every kind.
func missiles_of(warhead: int = -1) -> int:
	var n := 0
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER and e.def.missile != null and e.working() \
				and (warhead < 0 or e.def.missile.warhead == warhead):
			n += missiles_left(e)
	return n


## Missiles aboard by type (display name -> count).
func missile_count() -> Dictionary:
	var out := {}
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.MISSILE_LAUNCHER and e.def.missile != null and not e.destroyed():
			out[e.def.missile.display_name] = int(out.get(e.def.missile.display_name, 0)) + missiles_left(e)
	return out


## Fires burn, smoulder, are foamed or fought; true when something changed.
func _advance_fires(dt: float) -> bool:
	if fires.is_empty():
		return false
	var changed := false
	for room: int in fires.keys():
		var f: Dictionary = fires[room]
		if not rooms[room].pressurized:
			f.smoulder_s += dt
			if f.smoulder_s >= SMOULDER_S:
				fires.erase(room)
				_note("Fire in %s %s out — starved of air" % [_room_name(room), blueprint.rooms[room].id])
			continue
		f.burn_s += dt
		var left := FOAM_CHARGES - int(foam_used.get(room, 0))
		if f.burn_s >= FOAM_DELAY_S and left > 0 and rooms[room].powered:
			foam_used[room] = int(foam_used.get(room, 0)) + 1
			fires.erase(room)
			_note("Foam suppression put out the fire in %s %s (%d charge%s left)" % [_room_name(room), blueprint.rooms[room].id,
				left - 1, "" if left - 1 == 1 else "s"])
			continue
		if f.burn_s >= CREW_FIGHT_S and crew != null and crew.members.any(func(m: CrewRoster.Member) -> bool:
				return m.fit() and m.role == CrewRoster.Role.DAMAGE_CONTROL and m.location >= 0 and not route(m.location, room).is_empty()):
			fires.erase(room)
			_note("Damage control put out the fire in %s %s" % [_room_name(room), blueprint.rooms[room].id])
			continue
		heat_generation_kw += FIRE_HEAT_KW
		temperature_k += FIRE_HEAT_KW * 1000.0 * dt / (HEAT_CAPACITY_J_PER_K_KG * maxf(stats.mass_kg, 1.0))
		for e in equipment:
			if not e.def.is_external() and not e.destroyed() and grid.room_at.get(blueprint.equipment[e.index].cell, -1) == room:
				e.hp = maxf(e.hp - FIRE_HP_PER_S * dt, 0.0)
				if e.destroyed():
					_note("%s %s destroyed by fire" % [e.def.display_name, e.id])
					solve_power()
					changed = true
		if crew != null and damage_rng.randf() < FIRE_WOUND_CHANCE_PER_S * dt:
			for m in crew.in_room(room):
				if m.state == CrewRoster.State.FIT:
					m.state = CrewRoster.State.WOUNDED
					_note("Crew member %s burned in %s %s" % [m.id, _room_name(room), blueprint.rooms[room].id])
					changed = true
					break
	return changed


## Foam charges left in a room.
func foam_left(room: int) -> int:
	return FOAM_CHARGES - int(foam_used.get(room, 0))


## What a role's rooms are worth: 0 with none working (powered and, unless
## the crew are suited, pressurised); 1 for one cell, ROOM_BONUS_PER_CELL more
## for each further cell, up to ROOM_BONUS_MAX.
func room_bonus(role: StringName) -> float:
	var cells := 0
	for i in blueprint.rooms.size():
		if room_role(i) == role and rooms[i].powered and (suited or rooms[i].pressurized):
			cells += blueprint.rooms[i].rect.size.x * blueprint.rooms[i].rect.size.y
	if cells == 0:
		return 0.0
	return minf(1.0 + ROOM_BONUS_PER_CELL * (cells - 1), ROOM_BONUS_MAX)


## Damage control patches breached hulls one room at a time — the
## workshop's sealant drones and foam reach a breach even where the crew
## can't — with a working workshop, fit damage-control or engineering crew
## aboard and life support to put the air back. Returns true when a room is
## sealed (and re-pressurised).
func _advance_hull_sealing(dt: float) -> bool:
	var room := -1
	for i in rooms.size():
		if rooms[i].breached:
			room = i
			break
	if room < 0 or crew == null or room_bonus(&"workshop") <= 0.0 or room_bonus(&"life_support") <= 0.0:
		return false
	if not crew.members.any(func(m: CrewRoster.Member) -> bool:
			return m.fit() and m.location >= 0 and (m.role == CrewRoster.Role.DAMAGE_CONTROL or m.role == CrewRoster.Role.ENGINEERING)):
		return false
	_seal_s[room] = float(_seal_s.get(room, 0.0)) + dt * room_bonus(&"workshop") * tech_factor("damage_control")
	if _seal_s[room] < HULL_SEAL_S:
		return false
	_seal_s.erase(room)
	rooms[room].breached = false
	_note("%s %s: hull breach sealed by damage control; life support re-pressurises it" % [_room_name(room), blueprint.rooms[room].id])
	update_pressure()
	return true


## Progress (0..1) on sealing the room being patched, or -1 if none.
func hull_seal_progress() -> float:
	for i in rooms.size():
		if rooms[i].breached:
			return clampf(float(_seal_s.get(i, 0.0)) / HULL_SEAL_S, 0.0, 1.0)
	return -1.0


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
	var side_engines := PackedFloat64Array([0, 0, 0, 0, 0, 0])
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
				else:
					side_engines[ShipStats.engine_slot(blueprint.equipment[e.index].face)] += e.def.thrust_n
			EquipmentDefinition.Kind.RCS:
				rcs.append(e)
	var rcs_thrust := 0.0
	var torque := Vector3.ZERO
	for e in rcs:
		var r := e.body_position
		rcs_thrust += e.def.thrust_n
		torque += e.def.thrust_n * Vector3(Vector2(r.y, r.z).length(), Vector2(r.x, r.z).length(), Vector2(r.x, r.y).length())
	cfg.thrust_forward_n = forward
	cfg.engine_thrust_n = side_engines
	cfg.thrust_torque_body = engine_torque
	cfg.thrust_reverse_n = rcs_thrust
	cfg.thrust_lateral_n = rcs_thrust
	cfg.thrust_vertical_n = rcs_thrust
	cfg.max_torque_nm = torque
	for axis in 3:
		if torque[axis] <= 0.0:
			cfg.assist_max_rate_rad_s[axis] = 0.0
	var eng := channel_factor(Channel.ENG)
	var sys := channel_factor(Channel.SYS)
	eng *= tech_factor("thrusters")
	cfg.thrust_forward_n *= eng
	for k in 6:
		cfg.engine_thrust_n[k] *= eng * (SHIP_AI_FACTOR if not has_command() else 1.0)
	cfg.thrust_reverse_n *= eng
	cfg.thrust_lateral_n *= eng
	cfg.thrust_vertical_n *= eng
	cfg.thrust_torque_body *= eng
	cfg.max_torque_nm *= sys
	cfg.assist_max_rate_rad_s *= sys
	if cfg.cannon != null and channel_factor(Channel.WEP) * tech_factor("gunnery") != 1.0:
		cfg.scale_rate_of_fire(channel_factor(Channel.WEP) * tech_factor("gunnery"))
	if not has_command():
		# Ship AI in control: limited mobility.
		cfg.assist_max_rate_rad_s *= SHIP_AI_FACTOR
		cfg.thrust_forward_n *= SHIP_AI_FACTOR
		cfg.thrust_reverse_n *= SHIP_AI_FACTOR
		cfg.thrust_lateral_n *= SHIP_AI_FACTOR
		cfg.thrust_vertical_n *= SHIP_AI_FACTOR
		cfg.thrust_torque_body *= SHIP_AI_FACTOR
		if cfg.cannon != null:
			cfg.scale_rate_of_fire(SHIP_AI_GUN_RATE_FACTOR)
			cfg.cannon_extra_dispersion_rad += deg_to_rad(SHIP_AI_DISPERSION_DEG)
	if cfg.cannon != null and not has_gun_crew():
		cfg.scale_rate_of_fire(NO_GUN_CREW_RATE_FACTOR)
	_config = cfg
	return cfg


## Something outside (crew casualties, capture) changed what the ship can do.
func invalidate() -> void:
	_state_changed()
	_config = null


# --- Power distribution ---------------------------------------------------------

func channel_factor(ch: Channel) -> float:
	return 0.5 + 0.25 * pips[ch]


## Move one pip into `ch` from the fullest other channel. False if it is
## already at the maximum.
func divert(ch: Channel) -> bool:
	if pips[ch] >= PIPS_MAX:
		return false
	var donor := -1
	for other in Channel.size():
		if other != ch and pips[other] > 0 and (donor < 0 or pips[other] > pips[donor]):
			donor = other
	if donor < 0:
		return false
	pips[donor] -= 1
	pips[ch] += 1
	_config = null
	return true


func balance_power() -> void:
	pips = [2, 2, 2]
	_config = null


# --- Crew orders --------------------------------------------------------------------

## Room a crew role works from (-1 if the ship has none).
func station_for(role: int) -> int:
	for room_role_name in ROLE_STATIONS.get(role, []):
		for i in blueprint.rooms.size():
			if room_role(i) == room_role_name and rooms[i].pressurized:
				return i
	return -1


## Send the nearest free general crew member to take over `role`. Returns
## "" on success, or why it can't be done.
func cover_role(role: int) -> String:
	if crew == null or not ROLE_STATIONS.has(role):
		return "that role can't be covered"
	var dest := station_for(role)
	if dest < 0:
		return "no pressurised %s station" % CrewRoster.ROLE_NAMES[role]
	var best: CrewRoster.Member
	var best_path: Array[int] = []
	for m in crew.members:
		if m.role != CrewRoster.Role.GENERAL or not m.available() or m.location < 0 or crew_orders.has(m.id):
			continue
		var path := route(m.location, dest)
		if not path.is_empty() and (best == null or path.size() < best_path.size()):
			best = m
			best_path = path
	if best == null:
		return "no free general crew can reach the %s station" % CrewRoster.ROLE_NAMES[role]
	best.busy = true
	crew_orders[best.id] = {"role": role, "room": dest, "left_s": (best_path.size() - 1) * CrewRoster.ROOM_TRANSIT_S}
	_note("%s (general) heading to cover %s — %.0f s" % [best.id, CrewRoster.ROLE_NAMES[role], crew_orders[best.id].left_s])
	return ""


## Returns true when someone took over a role (the flight config changes).
## A fit medic aboard, in a pressurised room the crew can reach, treats the
## wounded one at a time: each takes MEDICAL_TREATMENT_S (those in rooms the
## medic can't reach wait). Returns true when someone is back on their feet.
func _advance_medical(dt: float) -> bool:
	if crew == null:
		return false
	var medic: CrewRoster.Member
	for m in crew.members:
		if m.role == CrewRoster.Role.MEDICAL and m.fit() and m.location >= 0 and rooms[m.location].pressurized:
			medic = m
			break
	if medic == null:
		_treatment_s = 0.0
		return false
	var patient: CrewRoster.Member
	for m in crew.members:
		if m.state == CrewRoster.State.WOUNDED and m.location >= 0 and rooms[m.location].pressurized \
				and not route(medic.location, m.location).is_empty():
			patient = m
			break
	if patient == null:
		_treatment_s = 0.0
		return false
	_treatment_s += dt * maxf(room_bonus(&"life_support"), 0.5) * tech_factor("medicine") * (1.0 + 0.2 * medic.skill)
	if _treatment_s < MEDICAL_TREATMENT_S:
		return false
	_treatment_s = 0.0
	patient.state = CrewRoster.State.FIT
	_note("Medic treated crew member %s (%s): back on duty" % [patient.id, CrewRoster.ROLE_NAMES[patient.role]])
	invalidate()
	return true


func _advance_crew_orders(dt: float) -> bool:
	var changed := false
	for id in crew_orders.keys():
		var m := crew.by_id(id)
		var order: Dictionary = crew_orders[id]
		if m == null or not m.fit() or not rooms[order.room].pressurized:
			if m != null:
				m.busy = false
			crew_orders.erase(id)
			continue
		order.left_s -= dt
		if order.left_s > 0.0:
			continue
		m.role = order.role
		m.station = order.room
		m.location = order.room
		m.busy = false
		crew_orders.erase(id)
		_note("%s now covering %s" % [id, CrewRoster.ROLE_NAMES[m.role]])
		changed = true
	if changed:
		_config = null
	return changed


# --- Crew ------------------------------------------------------------------------

## Switch a power load off (or back on) to reroute power to the rest.
## Reactors and unpowered-by-design parts can't be switched. Returns false
## if it can't be.
func set_switched_off(id: String, off: bool) -> bool:
	_state_changed()
	var e := equipment_by_id(id)
	if e == null or e.def.power_kw >= 0.0:
		return false
	if off:
		switched_off[id] = true
	else:
		switched_off.erase(id)
	_note("%s %s switched %s" % [e.def.display_name, id, "OFF — power rerouted" if off else "back ON"])
	solve_power()
	return true


## Seal a compartment off (or reopen it): crew routes avoid it.
func set_isolated(room: int, isolated: bool) -> void:
	_state_changed()
	if isolated:
		isolated_rooms[room] = true
	else:
		isolated_rooms.erase(room)
	_note("%s %s %s" % [_room_name(room), blueprint.rooms[room].id, "ISOLATED — hatches sealed" if isolated else "reopened"])
	_config = null


## Rooms from `from` to `to` (inclusive) through hatches, or [] if there is
## no way. Unsuited crew need every room pressurised; `blocked` hatch ids
## (sealed doors) are impassable; destroyed hatches are open holes.
## Isolated compartments can't be entered or left (suited boarders cut through).
## `suited`: boarders in suits (they also ignore our isolated compartments).
## Our own crew in suits (general quarters) go through vented rooms too.
func route(from: int, to: int, suited: bool = false, blocked: Dictionary = {}) -> Array[int]:
	var none: Array[int] = []
	var eva := suited or self.suited
	if from < 0 or to < 0 or (not eva and (not rooms[from].pressurized or not rooms[to].pressurized)):
		return none
	var prev := {from: -1}
	var queue := [from]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		if i == to:
			break
		for h in blueprint.hatches:
			if blocked.has(h.id) and not destroyed_hatches.has(h.id):
				continue
			var ra: int = grid.room_at.get(h.a, -1)
			var rb: int = grid.room_at.get(h.b, -1)
			var other := rb if ra == i else (ra if rb == i else -1)
			if other >= 0 and not suited and (isolated_rooms.has(other) or isolated_rooms.has(i)) and not destroyed_hatches.has(h.id):
				continue
			if other >= 0 and not prev.has(other) and (eva or rooms[other].pressurized):
				prev[other] = i
				queue.append(other)
		for other: int in grid.open_rooms.get(i, []):
			if not suited and (isolated_rooms.has(other) or isolated_rooms.has(i)):
				continue
			if not prev.has(other) and (eva or rooms[other].pressurized):
				prev[other] = i
				queue.append(other)
	if not prev.has(to):
		return none
	var path: Array[int] = []
	var at := to
	while at >= 0:
		path.push_front(at)
		at = prev[at]
	return path


## The hatch joining two neighbouring rooms ("" if none).
func hatch_between_rooms(a: int, b: int) -> String:
	for h in blueprint.hatches:
		var ra: int = grid.room_at.get(h.a, -1)
		var rb: int = grid.room_at.get(h.b, -1)
		if (ra == a and rb == b) or (ra == b and rb == a):
			return h.id
	return ""


func room_role(i: int) -> StringName:
	var def: RoomDefinition = grid.catalog.rooms.get(blueprint.rooms[i].def_id)
	return def.role if def != null else &""


func command_room() -> int:
	for i in blueprint.rooms.size():
		if room_role(i) == &"command":
			return i
	return -1


## Someone fit is in command on a pressurised bridge (ships without a crew
## model always are).
func has_command() -> bool:
	if crew == null or crew.members.is_empty():
		return true
	for m in crew.members:
		if m.fit() and m.role == CrewRoster.Role.COMMAND and m.location >= 0 \
				and rooms[m.location].pressurized and room_role(m.location) == &"command":
			return true
	return false


## A fit weapons crew member can reach a pressurised magazine.
func has_gun_crew() -> bool:
	if crew == null or not crew.members.any(func(m: CrewRoster.Member) -> bool: return m.role == CrewRoster.Role.WEAPONS):
		return true
	for m in crew.members:
		if not m.fit() or m.role != CrewRoster.Role.WEAPONS or m.location < 0:
			continue
		for i in blueprint.rooms.size():
			if room_role(i) == &"magazine" and not route(m.location, i).is_empty():
				return true
	return false


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
## Cached: the AI, the HUD and the missions ask many times a frame, and the
## command-room search is a graph walk. Every change that can alter the
## answer (damage, power, pressure, switches, EMP, a tick) clears it
## (_state_changed); capture is checked live.
func disabled_reason() -> String:
	if captured:
		return "captured"
	if not _disabled_valid:
		_disabled_cache = _compute_disabled_reason()
		_disabled_valid = true
	return _disabled_cache


func _compute_disabled_reason() -> String:
	if power_supply_kw <= 0.0:
		return "no power"
	if reachable_rooms().is_empty():
		return "command room lost"
	if count(EquipmentDefinition.Kind.CANNON, false) > 0 and count(EquipmentDefinition.Kind.CANNON, true) == 0:
		return "all guns out"
	return ""


var _disabled_valid := false
var _disabled_cache := ""


## Something that can change disabled_reason() happened.
func _state_changed() -> void:
	_disabled_valid = false


## Detection range: the best working (powered) sensor mast, else visual.
func sensor_range_m() -> float:
	var best := VISUAL_RANGE_M
	for e in equipment:
		if e.def.kind == EquipmentDefinition.Kind.SENSOR and e.working():
			best = maxf(best, e.def.sensor_range_m)
	return best


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
	var out := {"equipment": eq, "modules": mods, "breached": breached, "hatches": hatches}
	if not bus_cut.is_empty():
		var cut := bus_cut.keys()
		cut.sort()
		out["bus_cut"] = cut
	if not coolant_cut.is_empty():
		var pipes := coolant_cut.keys()
		pipes.sort()
		out["coolant_cut"] = pipes
	if not foam_used.is_empty():
		var foam := {}
		for room: int in foam_used:
			foam[blueprint.rooms[room].id] = foam_used[room]
		out["foam_used"] = foam
	if not missiles_used.is_empty():
		out["missiles_used"] = missiles_used.duplicate()
	var worn := {}
	for key in plates:
		var full := float(blueprint.armor.get(key, 0.0))
		if full > 0.0 and plates[key] < full:
			worn[key] = plates[key] / full
	if not worn.is_empty():
		out["plates"] = worn
	var hurt: Dictionary = crew.casualties() if crew != null else {}
	if not hurt.is_empty():
		out["crew"] = hurt
	return out


## Restore a saved condition. Ids the blueprint no longer has are ignored;
## parts the condition does not list are new.
func apply_condition(c: Dictionary) -> void:
	_state_changed()
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
	bus_cut.clear()
	for key in c.get("bus_cut", []):
		if blueprint.bus.has(str(key)):
			bus_cut[str(key)] = true
	coolant_cut.clear()
	for key in c.get("coolant_cut", []):
		if blueprint.coolant.has(str(key)):
			coolant_cut[str(key)] = true
	_cooled = null
	missiles_used.clear()
	var fired: Dictionary = c.get("missiles_used", {})
	for e in equipment:
		if fired.has(e.id):
			missiles_used[e.id] = clampi(int(fired[e.id]), 0, maxi(e.def.missile_capacity, e.def.decoy_capacity))
	foam_used.clear()
	var foam: Dictionary = c.get("foam_used", {})
	for i in blueprint.rooms.size():
		if foam.has(blueprint.rooms[i].id):
			foam_used[i] = clampi(int(foam[blueprint.rooms[i].id]), 0, FOAM_CHARGES)
	var worn: Dictionary = c.get("plates", {})
	for key in blueprint.armor:
		plates[key] = float(blueprint.armor[key]) * clampf(float(worn.get(key, 1.0)), 0.0, 1.0)
	var breached: Array = c.get("breached", [])
	for i in rooms.size():
		rooms[i].breached = breached.has(blueprint.rooms[i].id)
	destroyed_hatches.clear()
	for h in c.get("hatches", []):
		if blueprint.find(str(h)) != null:
			destroyed_hatches[str(h)] = true
	update_pressure()
	if crew != null:
		crew.apply_casualties(c.get("crew", {}))
		# Nobody starts a sortie in a vented room: they wait on the bridge.
		var bridge := command_room()
		for m in crew.members:
			if m.location >= 0 and not rooms[m.location].pressurized:
				m.location = bridge if bridge >= 0 and rooms[bridge].pressurized else -1
	solve_power()
	_config = null


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
## external one on EVA from a reachable room within EVA_REACH_CELLS of its mount.
func can_reach(e: EquipmentState) -> bool:
	var reach := reachable_rooms()
	for r in _access_rooms(e):
		if reach.has(r):
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
	var e := field_repair_target()
	if e == null:
		return "nothing the crew can patch (destroyed parts need the yard)"
	if _repair_crew(e).is_empty():
		return "no fit damage-control or engineering crew can get to %s" % e.id
	return ""


## [member, route] for the nearest free damage-control (else engineering)
## crew member who can walk to `e`, or [].
func _repair_crew(e: EquipmentState) -> Array:
	if crew == null:
		return []
	var best := []
	for role in [CrewRoster.Role.DAMAGE_CONTROL, CrewRoster.Role.ENGINEERING]:
		for m in crew.members:
			if m.role != role or not m.available() or m.location < 0:
				continue
			for room in _access_rooms(e):
				var path := route(m.location, room)
				if not path.is_empty() and (best.is_empty() or path.size() < (best[1] as Array).size()):
					best = [m, path]
		if not best.is_empty():
			return best
	return best


## Rooms from which the crew work on `e`: its own room, or for an external
## system any room with a cell within EVA_REACH_CELLS of its mount (an
## airlock walk along the hull).
func _access_rooms(e: EquipmentState) -> Array[int]:
	var out: Array[int] = []
	var cell: Vector3i = blueprint.equipment[e.index].cell
	if not e.def.is_external():
		var r: int = grid.room_at.get(cell, -1)
		if r >= 0:
			out.append(r)
		return out
	for r in blueprint.rooms.size():
		for c in ShipGrid.room_cells(blueprint.rooms[r]):
			var d := (c - cell).abs()
			if maxi(d.x, maxi(d.y, d.z)) <= EVA_REACH_CELLS:
				out.append(r)
				break
	return out


## Next damaged (not destroyed) system the crew can reach and patch: by
## FIELD_REPAIR_ORDER, then the most damaged.
func field_repair_target() -> EquipmentState:
	var best: EquipmentState
	for e in equipment:
		if e.destroyed() or e.hp >= FIELD_REPAIR_LIMIT * e.max_hp - 1e-6 or not can_reach(e):
			continue
		if e.id == preferred_repair_id:
			return e
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
	var who: Array = _repair_crew(e)
	var m: CrewRoster.Member = who[0]
	var path: Array = who[1]
	repair_task = RepairTask.new()
	repair_task.equipment_id = e.id
	repair_task.member_id = m.id
	repair_task.target_hp = FIELD_REPAIR_LIMIT * e.max_hp
	repair_task.travel_s = (path.size() - 1) * CrewRoster.ROOM_TRANSIT_S
	repair_task.total_s = repair_task.travel_s + (FIELD_REPAIR_SETUP_S + FIELD_REPAIR_S_PER_HP * field_repair_hp(e)) / maxf(room_bonus(&"workshop"), 1.0)
	repair_task.remaining_s = repair_task.total_s
	m.busy = true
	m.location = path[-1]
	_note("Damage control: %s (%s) patching %s %s — %.0f s incl. %.0f s to get there" % [
		m.id, CrewRoster.ROLE_NAMES[m.role], e.def.display_name, e.id, repair_task.total_s, repair_task.travel_s])
	return e


## Returns true when the task finished (the flight config changes).
func _advance_repair(dt: float) -> bool:
	var e := equipment_by_id(repair_task.equipment_id)
	var m: CrewRoster.Member = crew.by_id(repair_task.member_id) if crew != null else null
	var why := ""
	if m == null or not m.fit():
		why = "the repairer was hurt"
	elif e == null or e.destroyed():
		why = "the part was destroyed"
	elif working_workshop() < 0:
		why = "the workshop is down"
	elif not can_reach(e):
		why = "the crew lost access"
	if why != "":
		_note("Repair of %s interrupted: %s" % [repair_task.equipment_id, why])
		if m != null:
			m.busy = false
		repair_task = null
		return false
	repair_task.remaining_s -= dt
	if repair_task.remaining_s > 0.0:
		return false
	m.busy = false
	e.hp = maxf(e.hp, repair_task.target_hp)
	_note("%s %s patched to %.0f%%" % [e.def.display_name, e.id, 100.0 * e.hp / e.max_hp])
	repair_task = null
	solve_power()
	return true
