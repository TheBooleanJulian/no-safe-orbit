class_name EquipmentDefinition
extends Resource
## Reusable installable system (spec §6C). Internal equipment sits inside a
## room of an allowed role; external equipment mounts on an exterior hull
## face. Data lives in data/catalog/equipment/*.tres.
## Units: kg, kW (positive power = generation), N.

enum Kind {
	REACTOR,
	## Pushes the ship forward (−Z); must be mounted on an aft face.
	MAIN_ENGINE,
	## Pushes in every direction; lever arm from the centre of mass gives torque.
	RCS,
	CANNON,
	RADIATOR,
	## Holds propellant for main engines and RCS.
	PROPELLANT_TANK,
	## Docking port with an extendable gangway into the room behind it.
	DOCKING_COLLAR,
	## External rack carrying one autonomous craft (fighter or drone).
	CRAFT_MOUNT,
	## Sensor mast: detects and tracks other ships out to sensor_range_m.
	SENSOR,
	## Power distribution unit: a bus network's reactors only feed its loads
	## through a working one (designs with a routed bus).
	POWER_DISTRIBUTION,
	## Point-defence turret: engages hostile craft on its own (its `cannon`).
	POINT_DEFENCE,
	## Grappling arm: grabs a ship alongside, steadies it, lines up a collar
	## and siphons a hulk's propellant and rounds (Grapple).
	GRAPPLE,
	## Missile launcher: `missile_capacity` of its `missile` (M fires).
	MISSILE_LAUNCHER,
	## Decoy (flare) launcher: `decoy_capacity` flares, `decoy_salvo` a
	## launch (Space); missile seekers may chase them instead (Milestone 11).
	DECOY_LAUNCHER,
	## Jammer: `jam_strength` of electronic noise — enemy sensor tracks lose
	## confidence and missiles may lose lock, outside burn-through range.
	JAMMER,
}

## Kinds with control electronics an EMP can reset (engines, tanks and
## radiators are mechanical).
const ELECTRONIC := [Kind.REACTOR, Kind.CANNON, Kind.DOCKING_COLLAR, Kind.CRAFT_MOUNT, Kind.SENSOR,
	Kind.POWER_DISTRIBUTION, Kind.POINT_DEFENCE, Kind.GRAPPLE, Kind.MISSILE_LAUNCHER, Kind.DECOY_LAUNCHER, Kind.JAMMER]

enum Mount { INTERNAL, EXTERNAL }

@export var id: StringName
@export var display_name: String = "Equipment"
@export var kind: Kind = Kind.REACTOR
@export var mount: Mount = Mount.INTERNAL
## Internal only: footprint in cells (x, z) on one deck.
@export var footprint_cells: Vector2i = Vector2i(1, 1)
## Internal only: room roles this can be installed in.
@export var allowed_room_roles: Array[StringName] = []
## External only: hull faces (body frame) this can be mounted on.
@export var allowed_faces: Array[StringName] = []
## External only: cells it spans along the hull from its cell — aft, or
## across the ship (or up a flank) when turned with R.
@export var length_cells: int = 1
## Missile launchers: the missile and how many the launcher holds.
@export var missile: MissileConfig
@export var missile_capacity: int = 0
## Missiles a launcher sends away at once (a saturation pod's swarm).
@export var missile_salvo: int = 1
## EMP hardening (0 = exposed electronics, 1 = immune): shielded and
## filtered control electronics cost mass.
@export var emp_hardening: float = 0.0
## Superseded: still loads and flies, no longer offered or dropped.
@export var legacy: bool = false
@export var mass_kg: float = 1000.0
@export var power_kw: float = 0.0
## Waste heat generated while operating.
@export var heat_kw: float = 0.0
## Radiators: heat rejected to space.
@export var heat_rejection_kw: float = 0.0
## MAIN_ENGINE: forward thrust. RCS: thrust available in each direction.
@export var thrust_n: float = 0.0
## MAIN_ENGINE / RCS: specific impulse (s); propellant flow = F / (Isp·g0).
@export var isp_s: float = 0.0
## PROPELLANT_TANK: propellant held when full (kg; mass_kg is the dry tank).
@export var propellant_capacity_kg: float = 0.0
@export_group("Damage")
## Damage (mm of penetration absorbed) before it is destroyed; 0 = default for its kind.
@export var hit_points: float = 0.0
## Penetration (mm) a round loses passing through it; 0 = default for its kind.
@export var shield_mm: float = 0.0

## Per-kind defaults: [hit points, shield mm].
const DAMAGE_DEFAULTS := {
	Kind.REACTOR: [60.0, 35.0],
	Kind.MAIN_ENGINE: [40.0, 20.0],
	Kind.RCS: [10.0, 5.0],
	Kind.CANNON: [30.0, 15.0],
	Kind.RADIATOR: [10.0, 3.0],
	Kind.PROPELLANT_TANK: [25.0, 10.0],
	Kind.DOCKING_COLLAR: [20.0, 8.0],
	Kind.CRAFT_MOUNT: [20.0, 8.0],
	Kind.SENSOR: [12.0, 4.0],
	Kind.POWER_DISTRIBUTION: [15.0, 6.0],
	Kind.POINT_DEFENCE: [12.0, 5.0],
	Kind.MISSILE_LAUNCHER: [18.0, 8.0],
	Kind.DECOY_LAUNCHER: [12.0, 6.0],
	Kind.JAMMER: [14.0, 4.0],
}


func max_hit_points() -> float:
	return hit_points if hit_points > 0.0 else DAMAGE_DEFAULTS.get(kind, [20.0, 10.0])[0]


func shielding_mm() -> float:
	return shield_mm if shield_mm > 0.0 else DAMAGE_DEFAULTS.get(kind, [20.0, 10.0])[1]
## DECOY_LAUNCHER only: flares carried and fired a launch, each flare's
## starting signature (a ship is ~1; WorldSimulation.signature_of) and how
## long it burns (s).
@export var decoy_capacity: int = 0
@export var decoy_salvo: int = 3
@export var decoy_signature: float = 2.5
@export var decoy_life_s: float = 6.0
## JAMMER only: noise strength (1 = a standard jammer).
@export var jam_strength: float = 0.0
## CANNON only.
@export var cannon: KineticCannonConfig
## CRAFT_MOUNT only: the craft it carries (its mass is part of mass_kg).
@export var craft: ShipConfig
## SENSOR only: detection range (m).
@export var sensor_range_m: float = 0.0
@export var color: Color = Color(0.8, 0.8, 0.8)
@export_group("Progression")
## COMMON parts are always available; rarer ones must be found as loot.
@export var rarity: Rarity.Tier = Rarity.Tier.COMMON
## Relative chance of this part among loot drops of the same rarity.
@export var drop_weight: float = 10.0


func is_external() -> bool:
	return mount == Mount.EXTERNAL


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id must be set")
	if drop_weight < 0.0:
		problems.append("%s: drop_weight must not be negative" % id)
	if mass_kg <= 0.0:
		problems.append("%s: mass_kg must be positive" % id)
	if mount == Mount.INTERNAL and (footprint_cells.x <= 0 or footprint_cells.y <= 0):
		problems.append("%s: footprint_cells must be positive" % id)
	if mount == Mount.EXTERNAL and allowed_faces.is_empty():
		problems.append("%s: external equipment needs allowed_faces" % id)
	if kind == Kind.CRAFT_MOUNT and craft == null:
		problems.append("%s: craft mounts need a craft ShipConfig" % id)
	if (kind == Kind.CANNON or kind == Kind.POINT_DEFENCE) and cannon == null:
		problems.append("%s: gun equipment needs a KineticCannonConfig" % id)
	if kind == Kind.MISSILE_LAUNCHER and (missile == null or missile_capacity <= 0):
		problems.append("%s: launchers need a MissileConfig and a capacity" % id)
	if kind == Kind.DECOY_LAUNCHER and (decoy_capacity <= 0 or decoy_salvo <= 0 or decoy_signature <= 0.0 or decoy_life_s <= 0.0):
		problems.append("%s: decoy launchers need a capacity, a salvo, a signature and a burn time" % id)
	if kind == Kind.JAMMER and jam_strength <= 0.0:
		problems.append("%s: jammers need a positive jam_strength" % id)
	if (kind == Kind.MAIN_ENGINE or kind == Kind.RCS) and isp_s <= 0.0:
		problems.append("%s: thrusters need a positive isp_s" % id)
	if kind == Kind.PROPELLANT_TANK and propellant_capacity_kg <= 0.0:
		problems.append("%s: tanks need a positive propellant_capacity_kg" % id)
	for face in allowed_faces:
		if not ShipGrid.FACE_NORMALS.has(face):
			problems.append("%s: unknown face '%s'" % [id, face])
	return problems
