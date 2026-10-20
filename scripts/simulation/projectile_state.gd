class_name ProjectileState
extends RefCounted
## One unguided round. Rounds never expire: they coast on their own orbits
## until they hit something or cross the entry interface.
##
## Near the engagement a round lives in the local frame like a ship (32-bit
## offset, leapfrog with the tidal term, swept hit tests). Far away it is
## "far": its exact planet-centred state is kept in doubles and propagated
## analytically (OrbitElements.propagate) until its orbit brings it back.

var id: int
var shooter_id: StringName
## Weapon that fired it (mass, penetration). Null for hand-made test rounds.
var weapon: KineticCannonConfig
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Position at the start of the most recent tick (swept hits, interpolation).
var prev_position: Vector3 = Vector3.ZERO
var age_s: float = 0.0
## Deflected off armour (drawn as a spark, not a tracer).
var ricochet: bool = false
## A point-defence flak round aimed at round `pd_target_round` (-1 = none).
var pd_target_round: int = -1

## Far-mode state: PCI position/velocity at sim time `far_epoch`.
var far: bool = false
var far_position: Vec3d
var far_velocity: Vec3d
var far_epoch: float = 0.0
## Sim time at which a far round's orbit crosses the entry interface (INF = never).
var reentry_time: float = INF


func interpolated_position(alpha: float) -> Vector3:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))


func mass_kg() -> float:
	return weapon.round_mass_kg if weapon != null else 0.0
