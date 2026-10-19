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

	func is_drone() -> bool:
		return config.cannon == null


var carrier_id: StringName
var crafts: Array[Craft] = []
## Ship the strike / recon directives work against.
var target_id: StringName = &""
## Enemy craft ids (for intercept and escort).
var hostile_ids: Array[StringName] = []
var comms_range_m: float = 30_000.0
## Electronic warfare hook: no contact with any craft while true.
var jammed: bool = false
var log: PackedStringArray = PackedStringArray()
var log_count: int = 0


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
	return ""


func launch(world: WorldSimulation, c: Craft) -> String:
	var why := launch_block_reason(world, c)
	if why != "":
		return why
	var carrier := world.get_ship(carrier_id)
	var frame := rack_frame(world, c)
	var ship := ShipState.create(c.id, c.label, c.config, frame[0] + frame[1] * LAUNCH_CLEAR_M,
		carrier.velocity + frame[1] * LAUNCH_PUSH_MPS, carrier.orientation)
	ship.propellant_kg = c.config.propellant_capacity_kg * c.propellant_fraction
	ship.cannon_rounds = c.ammo
	ship.hull_damage = (1.0 - c.hull_fraction) * c.config.hull_hp
	world.add_ship(ship)
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
		if c.status == Status.FLYING:
			c.directive = CraftAI.Directive.RETURN
	_note("All craft recalled")


# --- Every tick --------------------------------------------------------------------

## Set every flying craft's controls; recover, service and lose craft.
## Called by WorldSimulation at the start of each tick.
func update(world: WorldSimulation, dt: float) -> void:
	var carrier := world.get_ship(carrier_id)
	var target := world.get_ship(target_id) if target_id != &"" else null
	var hostiles: Array[ShipState] = []
	for id in hostile_ids:
		var h := world.get_ship(id)
		if h != null and h.is_active():
			hostiles.append(h)
	for c in crafts:
		match c.status:
			Status.DOCKED:
				if c.service_left_s > 0.0:
					c.service_left_s = maxf(c.service_left_s - dt, 0.0)
					if c.service_left_s <= 0.0:
						c.propellant_fraction = 1.0
						c.ammo = c.config.cannon.magazine_rounds if c.config.cannon != null else 0
						_note("%s rearmed and refuelled" % c.label)
			Status.FLYING:
				_fly(world, c, carrier, target, hostiles, dt)


func _fly(world: WorldSimulation, c: Craft, carrier: ShipState, target: ShipState, hostiles: Array[ShipState], dt: float) -> void:
	var s := world.get_ship(c.id)
	if s == null or not s.is_active():
		c.status = Status.LOST
		c.hull_fraction = 0.0
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
			why = "disengaging: %s" % d
	if why != c.override_reason:
		c.override_reason = why
		if why != "":
			_note("%s %s" % [c.label, why])
	var rack_point := s.position
	if carrier != null and carrier.is_active():
		var frame := rack_frame(world, c)
		rack_point = frame[0] + frame[1] * (RECOVER_RADIUS_M * 0.5)
	world.set_input(c.id, CraftAI.command(s, directive, carrier, rack_point, target, hostiles, c.priority))
	if directive == CraftAI.Directive.RETURN and carrier != null and carrier.is_active() \
			and s.position.distance_to(rack_point) < RECOVER_RADIUS_M \
			and (s.velocity - carrier.velocity).length() < RECOVER_SPEED_MPS:
		_recover(world, c)


func _recover(world: WorldSimulation, c: Craft) -> void:
	world.remove_ship(c.id)
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
