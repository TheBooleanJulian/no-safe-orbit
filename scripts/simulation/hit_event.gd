class_name HitEvent
extends RefCounted
## A round striking a ship's hit box. Milestone 3 will resolve this against
## armour and components; for now it is recorded and shown.

var tick: int
var round_id: int
var shooter_id: StringName
var target_id: StringName
## Impact point in the target's body frame (m).
var point_body: Vector3
## Round speed relative to the target at impact (m/s).
var relative_speed: float
## Kinetic energy relative to the target (J).
var energy_j: float
## What the round did inside the ship (null for ships without systems).
var report: DamageReport
## A missile's warhead, not a gun round (counted apart from gun accuracy).
var missile: bool = false
## A beam pulse, not a round (play-test batch 6).
var beam: bool = false
