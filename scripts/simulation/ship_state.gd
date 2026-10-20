class_name ShipState
extends RefCounted
## Authoritative runtime state of one physical vessel. Rendering reads this;
## it never writes it. Positions are in the local engagement frame (metres).

## What a gun mount is doing this tick (HUD reticles).
enum Turret {
	## On its aim and clear to fire.
	READY,
	## Training towards the aim point.
	SLEWING,
	## Its own hull is in the line of fire: it holds fire.
	BLOCKED,
	## The aim is outside its arc (below its face): it holds at the limit.
	OUT_OF_ARC,
	## Destroyed or unpowered.
	OFFLINE,
	## A gangway is attached: primary weapons are locked.
	LOCKED,
}

enum Status {
	ACTIVE,
	## Crossed the body's entry interface; no longer simulated.
	ENTERED_ATMOSPHERE,
	## Hull shot through (craft with hull_hp); no longer simulated.
	DESTROYED,
}

## Stable identity — never derived from scene-tree position.
var id: StringName
var display_name: String
var config: ShipConfig

var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var orientation: Quaternion = Quaternion.IDENTITY
## Angular velocity in the BODY frame (rad/s about body X, Y, Z).
var angular_velocity: Vector3 = Vector3.ZERO

## State at the start of the most recent tick, for render interpolation.
var prev_position: Vector3 = Vector3.ZERO
var prev_orientation: Quaternion = Quaternion.IDENTITY

## Thrust (N) and torque (N·m) applied during the last tick, body frame.
var last_thrust_body: Vector3 = Vector3.ZERO
var last_torque_body: Vector3 = Vector3.ZERO

## Total thruster delta-v spent so far (m/s), summed per axis because each
## thruster group burns propellant independently. Feeds the future propellant model.
var delta_v_expended: float = 0.0

var status: Status = Status.ACTIVE
## Simulation time at which status last changed away from ACTIVE (s).
var status_time: float = 0.0

## Propellant on board (kg); unused when config.unlimited_propellant.
var propellant_kg: float = 0.0

## Runtime condition of a ship built from a blueprint (damage, power, heat,
## pressure); null for fixed test configs. When set, `config` is its
## effective (damage-reduced) config.
var systems: ShipSystems
## A missile in flight: what it is, who fired it, what it is after, and
## how long it has flown (null / "" for ships and craft).
var missile: MissileConfig
var missile_owner: StringName = &""
var missile_target: StringName = &""
var missile_age: float = 0.0
## A beaten ship (or its craft) left drifting: it gets no commands, fires
## nothing and its point defence is silent; it can still be hit.
var derelict: bool = false

## Cannon state (unused when config.cannon is null). Rounds are shared by
## every mount; each mount has its own cooldown.
var cannon_rounds: int = 0
## Rounds per gun type (display name): a ship mixing guns keeps a separate
## magazine for each calibre, sharing the magazine's stowage mass by mount
## count (so a heavier round means fewer of them). `cannon_rounds` is
## always their sum.
var magazines: Dictionary = {}
## Each gun type's share of the magazine space (0..1).
var _magazine_share: Dictionary = {}
var cannon_cooldowns: PackedFloat32Array = PackedFloat32Array()
## Point defence per mount: barrel direction (body), cooldown, rounds left,
## and the craft it is engaging ("" = none).
var pd_dirs: PackedVector3Array = PackedVector3Array()
var pd_cooldowns: PackedFloat32Array = PackedFloat32Array()
var pd_rounds: PackedInt32Array = PackedInt32Array()
var pd_targets: PackedStringArray = PackedStringArray()
## Each mount's barrel direction (body frame) and what it is doing.
var turret_dirs: PackedVector3Array = PackedVector3Array()
var turret_status: PackedInt32Array = PackedInt32Array()
## Last blocked-by-own-hull check per mount: [direction checked, result].
var _block_checked: PackedVector3Array = PackedVector3Array()
var turret_blocked: PackedByteArray = PackedByteArray()
var rounds_fired: int = 0
## Total recoil impulse from firing (N·s), for the HUD.
var recoil_impulse: float = 0.0
var hits_taken: int = 0
## Damage to a craft's hull (see ShipConfig.hull_hp).
var hull_damage: float = 0.0


## Remaining hull fraction for craft (1 for ships without hull_hp).
func hull_fraction() -> float:
	return 1.0 - hull_damage / config.hull_hp if config.hull_hp > 0.0 else 1.0


static func create(
		p_id: StringName,
		p_display_name: String,
		p_config: ShipConfig,
		p_position: Vector3 = Vector3.ZERO,
		p_velocity: Vector3 = Vector3.ZERO,
		p_orientation: Quaternion = Quaternion.IDENTITY) -> ShipState:
	var state := ShipState.new()
	state.id = p_id
	state.display_name = p_display_name
	state.config = p_config
	state.position = p_position
	state.velocity = p_velocity
	state.orientation = p_orientation.normalized()
	if p_config.cannon != null:
		var n := p_config.cannon_muzzles_body.size()
		var weights := {}
		var sum := 0.0
		for k in maxi(n, 1):
			var gun := p_config.mount_cannon(k)
			var w := 1.0 / maxf(gun.round_mass_kg, 1e-3)
			weights[gun.display_name] = float(weights.get(gun.display_name, 0.0)) + w
			sum += w
		for gun_name in weights:
			state._magazine_share[gun_name] = float(weights[gun_name]) / sum
		state.set_rounds(p_config.cannon.magazine_rounds)
		state.cannon_cooldowns.resize(n)
		state.cannon_cooldowns.fill(0.0)
		state.turret_dirs.resize(n)
		state.turret_dirs.fill(Vector3.FORWARD)
		state.turret_status.resize(n)
		state.turret_status.fill(Turret.READY)
		state._block_checked.resize(n)
		state._block_checked.fill(Vector3.ZERO)
		state.turret_blocked.resize(n)
		state.turret_blocked.fill(0)
	if p_config.pd_gun != null:
		var n := p_config.pd_mounts_body.size()
		state.pd_dirs.resize(n)
		for k in n:
			state.pd_dirs[k] = p_config.pd_normals_body[k]
		state.pd_cooldowns.resize(n)
		state.pd_cooldowns.fill(0.0)
		state.pd_rounds.resize(n)
		state.pd_rounds.fill(p_config.pd_gun.magazine_rounds)
		state.pd_targets.resize(n)
	if not p_config.unlimited_propellant:
		state.propellant_kg = p_config.propellant_capacity_kg
	state.snapshot_previous()
	return state


## Current mass: dry structure plus propellant on board.
func mass_kg() -> float:
	return config.mass_kg + (0.0 if config.unlimited_propellant else propellant_kg)


## Inertia scaled from full tanks to the current mass (propellant is assumed
## to sit where the tanks are, so the shape of the mass distribution holds).
func inertia_kgm2() -> Vector3:
	return config.inertia_kgm2 * (mass_kg() / config.wet_mass_kg())


## Δv left on the main engines (rocket equation), m/s; INF when unlimited.
func delta_v_remaining() -> float:
	if config.unlimited_propellant:
		return INF
	return config.main_isp_s * ShipDynamics.G0 * log(mass_kg() / config.mass_kg)


func is_active() -> bool:
	return status == Status.ACTIVE


## Attach the runtime systems of the ship's blueprint and fly their config.
func attach_systems(p_systems: ShipSystems) -> void:
	systems = p_systems
	config = p_systems.effective_config()


func snapshot_previous() -> void:
	prev_position = position
	prev_orientation = orientation


func basis() -> Basis:
	return Basis(orientation)


## Unit vector of the ship's nose in world space.
func forward() -> Vector3:
	return orientation * Vector3.FORWARD


## Velocity expressed along the ship's own axes (x right, y up, z aft).
func body_velocity() -> Vector3:
	return orientation.inverse() * velocity


func interpolated_position(alpha: float) -> Vector3:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))


func interpolated_orientation(alpha: float) -> Quaternion:
	return prev_orientation.slerp(orientation, clampf(alpha, 0.0, 1.0))


## Rounds left for one gun type.
func rounds_for(gun: KineticCannonConfig) -> int:
	return int(magazines.get(gun.display_name, 0)) if gun != null else 0


## Take one round for `gun`. False if its magazine is empty.
func spend_round(gun: KineticCannonConfig) -> bool:
	if rounds_for(gun) <= 0:
		return false
	magazines[gun.display_name] = rounds_for(gun) - 1
	cannon_rounds -= 1
	return true


## Set the total, shared out by each gun type's share of the space.
func set_rounds(total: int) -> void:
	total = maxi(total, 0)
	var left := total
	var names := _magazine_share.keys()
	for i in names.size():
		var n: int = left if i == names.size() - 1 else floori(total * float(_magazine_share[names[i]]))
		magazines[names[i]] = n
		left -= n
	cannon_rounds = total


## Draw up to `n` rounds from the fullest magazines (a carrier rearming its
## craft). Returns how many were taken.
func draw_rounds(n: int) -> int:
	var taken := 0
	while taken < n and cannon_rounds > 0:
		var best := ""
		for gun_name in magazines:
			if best == "" or int(magazines[gun_name]) > int(magazines[best]):
				best = gun_name
		if int(magazines[best]) <= 0:
			break
		magazines[best] = int(magazines[best]) - 1
		cannon_rounds -= 1
		taken += 1
	return taken


## Cached own-hull blocking for mount k: recomputed by `check` only when the
## barrel has moved more than ~0.3° since the last check.
func blocked_cached(k: int, dir: Vector3, check: Callable) -> bool:
	if _block_checked[k] == Vector3.ZERO or _block_checked[k].dot(dir) < 0.99998:
		_block_checked[k] = dir
		turret_blocked[k] = 1 if check.call() else 0
	return turret_blocked[k] == 1
