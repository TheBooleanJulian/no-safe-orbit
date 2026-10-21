class_name AirWing
extends RefCounted
## A ship's autonomous craft (spec §11, Milestone 6): one per craft rack.
## Craft fly as ordinary ships in the same simulation (same physics, same
## hits); this keeps their orders, launches and recovers them, and decides
## when they break off.
##
## - Launch needs a working rack, a docked and serviced craft, and the
##   carrier turning slower than MAX_LAUNCH_RATE_RAD_S; the craft leaves
##   LAUNCH_CLEAR_M off the rack at the carrier's velocity plus LAUNCH_PUSH_MPS.
## - Recovery: within RECOVER_RADIUS_M of the rack at under
##   RECOVER_SPEED_MPS relative. Back aboard it is rearmed and refuelled over
##   SERVICE_S before it can fly again.
## - Disengage: below its risk tolerance's hull / propellant / ammunition
##   fractions (CraftAI.DISENGAGE) a craft returns on its own.
## - Communications: beyond comms_range_m of the carrier, or jammed, for
##   COMMS_FALLBACK_S, a craft falls back to RETURN (a defined policy, not
##   inert); it resumes its directive when contact is back.
## - A craft shot down or lost on entry is LOST; replacing it costs spare
##   parts at the station. Damage persists (ShipInstance.wing).
## - Work drones (Milestone 15), on any directive but RETURN: a repair drone
##   holds WORK_STANDOFF_M off a damaged system outside a friendly hull (the
##   carrier's first) and patches it at REPAIR_HP_PER_S up to
##   ShipSystems.FIELD_REPAIR_LIMIT — the crew's field-repair limit, without
##   the walk or the airlock. A salvage drone carries the salvage beacon:
##   with one on the wing (aboard or out, not lost) G drops a beacon on a
##   wreck up to SALVAGE_RANGE_M off rather than Salvage.BEACON_RANGE_M
##   (`beacon_reach_m`; play-test batch 9 — it no longer cuts parts off one
##   by one). With no work either escorts.

enum Status { DOCKED, FLYING, LOST }

const STATUS_NAMES := ["docked", "flying", "LOST"]
const MAX_LAUNCH_RATE_RAD_S := 0.15
const LAUNCH_CLEAR_M := 8.0
const LAUNCH_PUSH_MPS := 3.0
const RECOVER_RADIUS_M := 10.0
const RECOVER_SPEED_MPS := 2.0
const SERVICE_S := 40.0
const COMMS_FALLBACK_S := 10.0
## Recon craft inside this range of the target give a close inspection.
const INSPECT_RANGE_M := 3000.0
const LOG_LIMIT := 20
## Work drones (see above).
const WORK_ROLES: Array[StringName] = [&"repair", &"salvage"]
const WORK_STANDOFF_M := 12.0
const WORK_RANGE_M := 20.0
const WORK_SPEED_MPS := 3.0
const REPAIR_HP_PER_S := 1.5
const SALVAGE_RANGE_M := 8000.0


class Craft:
	## Ship id while flying (also its stable identity).
	var id: StringName
	var rack_id: String
	var config: ShipConfig
	var label: String
	var status: int = Status.DOCKED
	var directive: int = CraftAI.Directive.STRIKE
	var risk: int = CraftAI.Risk.BALANCED
	var priority: int = 0
	var hull_fraction: float = 1.0
	var propellant_fraction: float = 1.0
	var ammo: int = 0
	var service_left_s: float = 0.0
	var comms_lost_s: float = 0.0
	## Why it is flying something other than its directive ("" = following it).
	var override_reason: String = ""
	## Its last controls (held between thoughts) and which tick of
	## THINK_EVERY it thinks on.
	var held_input: ShipControlInput
	var think_offset: int = 0
	## It came home on its own (out of ammunition or propellant, hurt, or
	## nothing left to fight) rather than recalled: it goes out again once
	## refuelled and rearmed (AirWing.auto_relaunch).
	var came_back_itself: bool = false
	## The crew member flying it (fighters; play-test batch 9) — off the
	## carrier while it is out.
	var pilot_id: String = ""

	func is_worker() -> bool:
		return config.craft_role in AirWing.WORK_ROLES

	func is_drone() -> bool:
		return config.cannon == null


## Craft think every THINK_EVERY ticks (30 Hz), staggered; on their way
## home, every tick.
const THINK_EVERY := 2

var carrier_id: StringName
var crafts: Array[Craft] = []
## Ship the strike / recon directives work against.
var target_id: StringName = &""
## Enemy craft ids (for intercept and escort).
var hostile_ids: Array[StringName] = []
## Enemy ships a strike may move on to once its target is beaten (Main sets
## the encounter's contacts; the nearest combat-ready one is taken).
var candidate_ids: Array[StringName] = []
## Craft that came home on their own relaunch once serviced while there is
## something combat-ready to fight (play-test batch 6). The WING tab toggles it.
var auto_relaunch: bool = true
var comms_range_m: float = 30_000.0
## Electronic warfare hook: no contact with any craft while true.
var jammed: bool = false
var log: PackedStringArray = PackedStringArray()
var log_count: int = 0
## Systems a work drone has taken on this tick (ship id + part id -> craft id).
var _claims: Dictionary = {}


## One craft per working craft rack on the carrier's blueprint.
static func for_ship(carrier: ShipState) -> AirWing:
	var wing := AirWing.new()
	wing.carrier_id = carrier.id
	if carrier.systems == null:
		return wing
	var n := {"fighter": 0, "drone": 0}
	for e in carrier.systems.equipment:
		if e.def.kind != EquipmentDefinition.Kind.CRAFT_MOUNT or e.def.craft == null:
			continue
		var c := Craft.new()
		c.config = e.def.craft
		c.rack_id = e.id
		c.id = StringName("%s_%s" % [carrier.id, e.id])
		var kind := "drone" if e.def.craft.cannon == null else "fighter"
		n[kind] += 1
		c.label = "%s %s%d" % [e.def.craft.display_name.split(" ")[0], kind.left(1).to_upper(), n[kind]]
		c.directive = CraftAI.Directive.RECON if kind == "drone" else CraftAI.Directive.STRIKE
		c.ammo = c.config.cannon.magazine_rounds if c.config.cannon != null else 0
		c.think_offset = wing.crafts.size() % THINK_EVERY
		wing.crafts.append(c)
	return wing


func by_id(id: StringName) -> Craft:
	for c in crafts:
		if c.id == id:
			return c
	return null


func flying() -> Array[Craft]:
	return crafts.filter(func(c: Craft) -> bool: return c.status == Status.FLYING)


# --- Launch and recovery -----------------------------------------------------------

## Rack position (world, local frame) and outward normal on the carrier.
func rack_frame(world: WorldSimulation, c: Craft) -> Array:
	var carrier := world.get_ship(carrier_id)
	var e := carrier.systems.equipment_by_id(c.rack_id)
	var door := carrier.systems.launch_door(e)
	return [carrier.position + carrier.orientation * (door[0] as Vector3), carrier.orientation * (door[1] as Vector3)]


## Why `c` cannot launch now ("" = it can).
func launch_block_reason(world: WorldSimulation, c: Craft) -> String:
	var carrier := world.get_ship(carrier_id)
	if carrier == null or not carrier.is_active():
		return "no carrier"
	if c.status == Status.LOST:
		return "%s is lost — replace it at the station" % c.label
	if c.status == Status.FLYING:
		return "%s is already out" % c.label
	if c.service_left_s > 0.0:
		return "%s is being rearmed (%.0f s)" % [c.label, c.service_left_s]
	var rack := carrier.systems.equipment_by_id(c.rack_id)
	if rack == null or not rack.working():
		return "%s's rack %s is down" % [c.label, c.rack_id]
	if carrier.angular_velocity.length() > MAX_LAUNCH_RATE_RAD_S:
		return "turning too fast to launch (%.1f°/s)" % rad_to_deg(carrier.angular_velocity.length())
	if CrewRoster.needs_pilot(rack.def) and _free_pilot(carrier) == null:
		return "no pilot aboard for %s — post someone as pilot (crew quarters, or Tab › CREW)" % c.label
	return ""


## A fit pilot aboard and free to fly (null: none). A carrier with no
## crew model (no rooms) needs none.
static func _free_pilot(carrier: ShipState) -> CrewRoster.Member:
	var crew := carrier.systems.crew if carrier.systems != null else null
	if crew == null or crew.members.is_empty():
		return CrewRoster.Member.new()
	for m in crew.members:
		if m.role == CrewRoster.Role.PILOT and m.available() and m.location >= 0:
			return m
	return null


func launch(world: WorldSimulation, c: Craft) -> String:
	var why := launch_block_reason(world, c)
	if why != "":
		return why
	var carrier := world.get_ship(carrier_id)
	var frame := rack_frame(world, c)
	var ship := ShipState.create(c.id, c.label, c.config, frame[0] + frame[1] * LAUNCH_CLEAR_M,
		carrier.velocity + frame[1] * LAUNCH_PUSH_MPS, carrier.orientation)
	ship.propellant_kg = c.config.propellant_capacity_kg * c.propellant_fraction
	ship.set_rounds(c.ammo)
	ship.hull_damage = (1.0 - c.hull_fraction) * c.config.hull_hp
	ship.side = carrier.side
	world.add_ship(ship)
	var rack_def := carrier.systems.equipment_by_id(c.rack_id).def
	if CrewRoster.needs_pilot(rack_def):
		var pilot := _free_pilot(carrier)
		if pilot != null and pilot.id != "":
			pilot.busy = true
			pilot.location = -1
			c.pilot_id = pilot.id
	c.status = Status.FLYING
	c.comms_lost_s = 0.0
	_note("%s launched — %s" % [c.label, CraftAI.DIRECTIVE_NAMES[c.directive]])
	return ""


## Launch every craft that can go; returns how many did.
func launch_all(world: WorldSimulation) -> int:
	var n := 0
	for c in crafts:
		if c.status == Status.DOCKED and launch(world, c) == "":
			n += 1
	return n


func recall_all() -> void:
	for c in crafts:
		c.came_back_itself = false
		if c.status == Status.FLYING:
			c.directive = CraftAI.Directive.RETURN
	_note("All craft recalled")


## Recall one craft (K on it, or its row's Recall): it stays home.
func recall(c: Craft) -> void:
	c.came_back_itself = false
	if c.status == Status.FLYING:
		c.directive = CraftAI.Directive.RETURN


## Still worth shooting: active, not a derelict, not disabled.
static func combat_ready(ship: ShipState) -> bool:
	return ship != null and ship.is_active() and not ship.derelict \
		and (ship.systems == null or ship.systems.disabled_reason() == "")


## What strikes go for: the chosen target while it is combat-ready, else the
## combat-ready candidate nearest the carrier (null: nothing left to fight).
func strike_target(world: WorldSimulation) -> ShipState:
	var chosen := world.get_ship(target_id) if target_id != &"" else null
	if combat_ready(chosen):
		return chosen
	var carrier := world.get_ship(carrier_id)
	var best: ShipState = null
	var best_d := INF
	for id in candidate_ids:
		var s := world.get_ship(id)
		if not combat_ready(s):
			continue
		var d := s.position.distance_to(carrier.position) if carrier != null else 0.0
		if d < best_d:
			best_d = d
			best = s
	return best


# --- Every tick --------------------------------------------------------------------

## Set every flying craft's controls; recover, service and lose craft.
## Called by WorldSimulation at the start of each tick.
func update(world: WorldSimulation, dt: float) -> void:
	var carrier := world.get_ship(carrier_id)
	var target := strike_target(world)
	var hostiles: Array[ShipState] = []
	for id in hostile_ids:
		var h := world.get_ship(id)
		if h != null and h.is_active():
			hostiles.append(h)
	_claims.clear()
	# Our side (never in the line of fire) and hostile missiles (interceptors).
	_friends.clear()
	_enemy_missiles.clear()
	var side := carrier.side if carrier != null else &""
	for id in world.ship_ids():
		var s := world.get_ship(id)
		if s == null or not s.is_active():
			continue
		if s.missile != null:
			if s.side != side:
				_enemy_missiles.append(s)
		elif (side != &"" and s.side == side) or s == carrier or by_id(s.id) != null:
			# Unaligned ships (no side) are only friends if they are ours.
			_friends.append(s)
	for c in crafts:
		match c.status:
			Status.DOCKED:
				if c.service_left_s > 0.0:
					# A roomier hangar turns its craft round faster (play-test batch 9).
					var deck := carrier.systems.stats.hangar_factor * carrier.systems.tech_factor("hangar_crews") if carrier != null and carrier.systems != null else 1.0
					c.service_left_s = maxf(c.service_left_s - dt * deck, 0.0)
					if c.service_left_s <= 0.0:
						_note("%s %s" % [c.label, _resupply_from(carrier, c)])
				elif c.came_back_itself and auto_relaunch and c.hull_fraction > 0.5 and launch_block_reason(world, c) == "" \
						and (target != null if not c.is_worker() else (carrier != null and not _work_job(world, c, carrier.position, carrier, target).is_empty())):
					c.came_back_itself = false
					launch(world, c)
					_note("%s back out — %s" % [c.label, target.display_name if not c.is_worker() else "there is work"])
			Status.FLYING:
				_fly(world, c, carrier, target, hostiles, dt)


var _friends: Array[ShipState] = []
var _enemy_missiles: Array[ShipState] = []


func _fly(world: WorldSimulation, c: Craft, carrier: ShipState, target: ShipState, hostiles: Array[ShipState], dt: float) -> void:
	var s := world.get_ship(c.id)
	if s == null or not s.is_active():
		c.status = Status.LOST
		c.hull_fraction = 0.0
		_pilot_home(carrier, c, false)
		if s != null:
			world.remove_ship(c.id)
		_note("%s LOST" % c.label)
		return
	c.hull_fraction = s.hull_fraction()
	c.propellant_fraction = s.propellant_kg / maxf(c.config.propellant_capacity_kg, 1.0)
	c.ammo = s.cannon_rounds
	var in_contact := carrier != null and carrier.is_active() and not jammed \
		and s.position.distance_to(carrier.position) <= comms_range_m
	c.comms_lost_s = 0.0 if in_contact else c.comms_lost_s + dt
	var directive: int = c.directive
	var why := ""
	if c.comms_lost_s > COMMS_FALLBACK_S:
		directive = CraftAI.Directive.RETURN
		why = "no comms — returning"
	elif directive != CraftAI.Directive.RETURN:
		var d := CraftAI.disengage_reason(s, c.risk)
		if d != "":
			directive = CraftAI.Directive.RETURN
			why = "disengaging: %s — back to refuel and rearm" % d
			c.came_back_itself = true
		elif directive == CraftAI.Directive.STRIKE and target == null and not c.is_drone():
			directive = CraftAI.Directive.RETURN
			why = "nothing left to strike — returning"
			c.came_back_itself = true
	var job := {}
	if c.is_worker() and directive != CraftAI.Directive.RETURN:
		job = _work_job(world, c, s.position, carrier, target)
		if not job.is_empty():
			why = job.text
		else:
			directive = CraftAI.Directive.ESCORT
	if why != c.override_reason:
		c.override_reason = why
		if why != "":
			_note("%s %s" % [c.label, why])
	if not job.is_empty():
		c.held_input = _work_input(s, job)
		world.set_input(c.id, c.held_input)
		_work(c, s, job, dt)
		return
	var rack_point := s.position
	if carrier != null and carrier.is_active():
		var frame := rack_frame(world, c)
		rack_point = frame[0] + frame[1] * (RECOVER_RADIUS_M * 0.5)
	# A craft thinks every THINK_EVERY ticks (staggered) and holds its controls
	# in between — every tick on its way home, where landing needs precise
	# braking (play-test batch 6: many fighters).
	var landing := directive == CraftAI.Directive.RETURN
	if landing or c.held_input == null or (world.tick + c.think_offset) % THINK_EVERY == 0:
		c.held_input = CraftAI.command(s, directive, carrier, rack_point, target, hostiles, c.priority, _slot_of(c, directive),
			_friends, _enemy_missiles, dt * (1.0 if landing else float(THINK_EVERY)))
	world.set_input(c.id, c.held_input)
	if directive == CraftAI.Directive.RETURN and carrier != null and carrier.is_active() \
			and s.position.distance_to(rack_point) < RECOVER_RADIUS_M \
			and (s.velocity - carrier.velocity).length() < RECOVER_SPEED_MPS:
		_recover(world, c)


# --- Work drones (Milestone 15) -------------------------------------------------------

## The job for work drone `c` seen from `from`: {ship, part, point (where to
## hold), look (the part), text} — {} if there is none.
func _work_job(_world: WorldSimulation, c: Craft, from: Vector3, carrier: ShipState, _target: ShipState) -> Dictionary:
	var best := {}
	var best_score := INF
	if c.config.craft_role == &"repair":
		for ship in _friends:
			if ship.systems == null or ship.missile != null or (carrier != null and ship.position.distance_to(carrier.position) > comms_range_m):
				continue
			for e in ship.systems.equipment:
				if e.destroyed() or not e.def.is_external() or e.hp >= ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp - 1e-3 \
						or ship.systems.is_under_repair(e.id) or _claimed_by_other(ship, e, c):
					continue
				var site := _site(ship, e)
				var score := from.distance_to(site[0]) + (0.0 if ship == carrier else 1.0e6)
				if score < best_score:
					best_score = score
					best = {"ship": ship, "part": e, "point": site[0], "look": site[1],
						"text": "patching %s %s on %s" % [e.def.display_name, e.id, ship.display_name]}
	if not best.is_empty():
		_claims["%s/%s" % [(best.ship as ShipState).id, (best.part as ShipSystems.EquipmentState).id]] = c.id
	return best


## How far off G can drop a salvage beacon: SALVAGE_RANGE_M with a salvage
## drone on the wing (aboard or out — it carries the beacon), else
## Salvage.BEACON_RANGE_M.
func beacon_reach_m() -> float:
	for c in crafts:
		if c.config.craft_role == &"salvage" and c.status != Status.LOST:
			return SALVAGE_RANGE_M
	return Salvage.BEACON_RANGE_M


func _claimed_by_other(ship: ShipState, e: ShipSystems.EquipmentState, c: Craft) -> bool:
	var who: StringName = _claims.get("%s/%s" % [ship.id, e.id], &"")
	return who != &"" and who != c.id


## [where to hold, the part] (world) for work on part `e` of `ship`: off its
## mount's face for a system outside the hull, else off the hull towards it.
func _site(ship: ShipState, e: ShipSystems.EquipmentState) -> Array:
	var part := ship.position + ship.orientation * e.body_position
	var face: StringName = ship.systems.blueprint.equipment[e.index].face
	var out := Vector3(ShipGrid.FACE_NORMALS.get(face, Vector3i.ZERO))
	var depth := WORK_STANDOFF_M
	if out == Vector3.ZERO or not e.def.is_external():
		out = e.body_position - ship.config.hit_box_center
		depth += ship.config.hit_box_half_extents.length()
	if out.length_squared() < 1e-6:
		out = Vector3.UP
	return [part + ship.orientation * out.normalized() * depth, part]


## Hold the work station, nose on the part (no avoidance: it works close in).
func _work_input(s: ShipState, job: Dictionary) -> ShipControlInput:
	var input := ShipControlInput.create(Vector3.ZERO, Vector3.ZERO, true)
	input.hold_translation = false
	var point: Vector3 = job.point
	CraftAI.steer(s, point, (job.ship as ShipState).velocity, input, clampf(s.position.distance_to(point) * 0.25, 2.0, CraftAI.MAX_CLOSING_MPS))
	CraftAI.point(s, (job.look as Vector3) - s.position, input)
	return input


## On station and matched in speed: patch.
func _work(c: Craft, s: ShipState, job: Dictionary, dt: float) -> void:
	var ship: ShipState = job.ship
	if s.position.distance_to(job.point) > WORK_RANGE_M or (s.velocity - ship.velocity).length() > WORK_SPEED_MPS:
		return
	var sys := ship.systems
	var e: ShipSystems.EquipmentState = job.part
	var limit := ShipSystems.FIELD_REPAIR_LIMIT * e.max_hp
	e.hp = minf(e.hp + REPAIR_HP_PER_S * dt, limit)
	if e.hp >= limit - 1e-6:
		sys.solve_power()
		ship.config = sys.effective_config()
		_note("%s patched %s %s on %s to %d %%" % [c.label, e.def.display_name, e.id, ship.display_name, roundi(ShipSystems.FIELD_REPAIR_LIMIT * 100.0)])


## The pilot back aboard at their station (`alive`), or lost with the craft.
func _pilot_home(carrier: ShipState, c: Craft, alive: bool) -> void:
	if c.pilot_id == "" or carrier == null or carrier.systems == null or carrier.systems.crew == null:
		return
	var m := carrier.systems.crew.by_id(c.pilot_id)
	c.pilot_id = ""
	if m == null:
		return
	m.busy = false
	if alive:
		m.location = m.station
	else:
		m.state = CrewRoster.State.DEAD
		_note("%s's pilot %s was lost with it" % [c.label, m.label()])
	carrier.systems.invalidate()


## Refuel and rearm a docked craft from the carrier's own stores: its
## propellant from the carrier's tanks, its rounds from the carrier's
## magazine by mass. Returns what happened.
func _resupply_from(carrier: ShipState, c: Craft) -> String:
	var cap := c.config.propellant_capacity_kg
	var need_kg := (1.0 - c.propellant_fraction) * cap
	var take := need_kg
	if carrier != null and not carrier.config.unlimited_propellant:
		take = minf(need_kg, carrier.propellant_kg)
		carrier.propellant_kg -= take
	c.propellant_fraction = clampf(c.propellant_fraction + take / maxf(cap, 1.0), 0.0, 1.0)
	var short := take < need_kg - 1e-3
	if c.config.cannon != null:
		var need_rounds := c.config.cannon.magazine_rounds - c.ammo
		var got := need_rounds
		# A beam's charges come back from the carrier's power, not its magazine.
		if carrier != null and carrier.config.cannon != null and need_rounds > 0 and not c.config.cannon.is_beam():
			var per_round := c.config.cannon.round_mass_kg / maxf(carrier.config.cannon.round_mass_kg, 1e-3)
			var cost := ceili(need_rounds * per_round - 1e-9)
			if cost > carrier.cannon_rounds:
				got = floori(carrier.cannon_rounds / maxf(per_round, 1e-6))
				cost = carrier.cannon_rounds
			carrier.draw_rounds(cost)
		c.ammo += got
		short = short or got < need_rounds
	return "refuelled and rearmed from the carrier" if not short else "only partly refuelled / rearmed — the carrier is short"


## Formation slot: this craft's place among the flying craft on the same
## directive (0 = lead).
func _slot_of(c: Craft, directive: int) -> int:
	var slot := 0
	for other in crafts:
		if other == c:
			return slot
		if other.status == Status.FLYING and other.directive == directive:
			slot += 1
	return slot


func _recover(world: WorldSimulation, c: Craft) -> void:
	world.remove_ship(c.id)
	_pilot_home(world.get_ship(carrier_id), c, true)
	c.status = Status.DOCKED
	c.override_reason = ""
	c.comms_lost_s = 0.0
	if c.directive == CraftAI.Directive.RETURN:
		c.directive = CraftAI.Directive.RECON if c.is_drone() else CraftAI.Directive.STRIKE
	var needs := c.propellant_fraction < 1.0 or (c.config.cannon != null and c.ammo < c.config.cannon.magazine_rounds)
	c.service_left_s = SERVICE_S if needs else 0.0
	_note("%s recovered%s" % [c.label, " — servicing %.0f s" % SERVICE_S if needs else ""])


## A recon craft (or the carrier itself) is close enough to inspect `target`.
func has_close_look(world: WorldSimulation, target: ShipState) -> bool:
	if target == null:
		return false
	var carrier := world.get_ship(carrier_id)
	if carrier != null and carrier.position.distance_to(target.position) <= INSPECT_RANGE_M:
		return true
	for c in flying():
		var s := world.get_ship(c.id)
		if s != null and c.directive == CraftAI.Directive.RECON and s.position.distance_to(target.position) <= INSPECT_RANGE_M:
			return true
	return false


# --- Persistence ---------------------------------------------------------------------

## {rack id: {"hull": fraction, "lost": bool}} for craft not like new.
func state() -> Dictionary:
	var out := {}
	for c in crafts:
		if c.status == Status.LOST or c.status == Status.FLYING:
			# Not back aboard when the sortie ends: lost.
			out[c.rack_id] = {"hull": 0.0, "lost": true}
		elif c.hull_fraction < 1.0:
			out[c.rack_id] = {"hull": c.hull_fraction, "lost": false}
	return out


func apply_state(saved: Dictionary) -> void:
	for c in crafts:
		var entry: Dictionary = saved.get(c.rack_id, {})
		if entry.is_empty():
			continue
		c.status = Status.LOST if entry.get("lost", false) else Status.DOCKED
		c.hull_fraction = clampf(float(entry.get("hull", 1.0)), 0.0, 1.0)


func _note(text: String) -> void:
	log.append(text)
	log_count += 1
	if log.size() > LOG_LIMIT:
		log.remove_at(0)
