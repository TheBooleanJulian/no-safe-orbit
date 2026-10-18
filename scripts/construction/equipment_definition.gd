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
}

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
}


func max_hit_points() -> float:
	return hit_points if hit_points > 0.0 else DAMAGE_DEFAULTS.get(kind, [20.0, 10.0])[0]


func shielding_mm() -> float:
	return shield_mm if shield_mm > 0.0 else DAMAGE_DEFAULTS.get(kind, [20.0, 10.0])[1]
## CANNON only.
@export var cannon: KineticCannonConfig
@export var color: Color = Color(0.8, 0.8, 0.8)


func is_external() -> bool:
	return mount == Mount.EXTERNAL


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id must be set")
	if mass_kg <= 0.0:
		problems.append("%s: mass_kg must be positive" % id)
	if mount == Mount.INTERNAL and (footprint_cells.x <= 0 or footprint_cells.y <= 0):
		problems.append("%s: footprint_cells must be positive" % id)
	if mount == Mount.EXTERNAL and allowed_faces.is_empty():
		problems.append("%s: external equipment needs allowed_faces" % id)
	if kind == Kind.CANNON and cannon == null:
		problems.append("%s: cannon equipment needs a KineticCannonConfig" % id)
	if (kind == Kind.MAIN_ENGINE or kind == Kind.RCS) and isp_s <= 0.0:
		problems.append("%s: thrusters need a positive isp_s" % id)
	if kind == Kind.PROPELLANT_TANK and propellant_capacity_kg <= 0.0:
		problems.append("%s: tanks need a positive propellant_capacity_kg" % id)
	for face in allowed_faces:
		if not ShipGrid.FACE_NORMALS.has(face):
			problems.append("%s: unknown face '%s'" % [id, face])
	return problems
