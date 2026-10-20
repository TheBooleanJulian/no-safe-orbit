class_name LocalFrame
extends RefCounted
## Free-falling, non-rotating engagement frame around one OrbitalBody.
##
## The origin's planet-centred inertial (PCI) state is double precision and
## follows a two-body free-fall path. Ships and rounds live at small 32-bit
## offsets from it and feel thrust plus the tidal term
##     g(origin + x) − g(origin)
## which is exact for a free-falling, non-rotating frame: origin + offset
## follows true two-body motion while local coordinates stay small.
## WorldSimulation re-centres (rebases) the origin on the player when it
## drifts too far; the origin keeps its own velocity, so local velocities
## are continuous across a rebase. See docs/ARCHITECTURE.md.

var body: OrbitalBody
var origin_position: Vec3d
var origin_velocity: Vec3d
## Origin at the start of the current tick (for tidal terms and interpolation).
var prev_origin_position: Vec3d
## Sum of every rebase shift. rebase_offset + local position is a coordinate
## that never jumps at a rebase (used by the dust motion cue).
var rebase_offset: Vec3d = Vec3d.new()


static func create(p_body: OrbitalBody, p_position: Vec3d, p_velocity: Vec3d) -> LocalFrame:
	var frame := LocalFrame.new()
	frame.body = p_body
	frame.origin_position = p_position.copy()
	frame.origin_velocity = p_velocity.copy()
	frame.prev_origin_position = p_position.copy()
	return frame


## Kick-drift-kick leapfrog (symplectic, second order) of the origin.
func step(dt: float) -> void:
	prev_origin_position = origin_position
	origin_velocity = origin_velocity.plus(gravity_at(origin_position).times(dt * 0.5))
	origin_position = origin_position.plus(origin_velocity.times(dt))
	origin_velocity = origin_velocity.plus(gravity_at(origin_position).times(dt * 0.5))


func gravity_at(pci: Vec3d) -> Vec3d:
	var r := pci.length()
	return pci.times(-body.mu_m3_s2 / (r * r * r))


## Tidal acceleration (m/s²) at local offset `local`, relative to the origin at
## the start (`at_tick_start`) or end of the current tick.
func tidal_acceleration(local: Vector3, at_tick_start: bool) -> Vector3:
	var o := prev_origin_position if at_tick_start else origin_position
	return tidal(body.mu_m3_s2, o.x, o.y, o.z, local.x, local.y, local.z)


## g(o + l) − g(o), all in double precision; the small result fits a Vector3.
static func tidal(mu: float, ox: float, oy: float, oz: float, lx: float, ly: float, lz: float) -> Vector3:
	var rx := ox + lx
	var ry := oy + ly
	var rz := oz + lz
	var r2 := rx * rx + ry * ry + rz * rz
	var o2 := ox * ox + oy * oy + oz * oz
	var kr := mu / (r2 * sqrt(r2))
	var ko := mu / (o2 * sqrt(o2))
	return Vector3(ko * ox - kr * rx, ko * oy - kr * ry, ko * oz - kr * rz)


func pci_position(local: Vector3) -> Vec3d:
	return origin_position.plus_v3(local)


func pci_velocity(local_velocity: Vector3) -> Vec3d:
	return origin_velocity.plus_v3(local_velocity)


func altitude(local: Vector3) -> float:
	return pci_position(local).length() - body.radius_m


## Origin linearly interpolated within the current tick, for rendering.
func interpolated_origin(alpha: float) -> Vec3d:
	var a := clampf(alpha, 0.0, 1.0)
	return prev_origin_position.plus(origin_position.minus(prev_origin_position).times(a))


## Rebases so far (a pull worked out before one is stale).
var rebase_count := 0


## Moves the origin by `shift` (local coordinates); callers subtract `shift`
## from every local position so PCI positions are unchanged.
func rebase(shift: Vector3) -> void:
	rebase_count += 1
	origin_position = origin_position.plus_v3(shift)
	prev_origin_position = prev_origin_position.plus_v3(shift)
	rebase_offset = rebase_offset.plus_v3(shift)
