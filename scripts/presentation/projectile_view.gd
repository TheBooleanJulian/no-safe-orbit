class_name ProjectileView
extends MultiMeshInstance3D
## Tracers for rounds in flight: thin glowing streaks along each round's
## velocity relative to the viewer, widened with distance so they stay a few
## pixels wide out to NEAR_M; further out they shrink and dim (to FAR_SCALE)
## so a distant exchange reads as distant. Read-only view of
## WorldSimulation rounds.
##
## The streak is built on the GPU (play-test batch 6: ~10 µs per round in
## GDScript was 17 ms a frame with 1,700 rounds): each tracer instance
## carries only its position (an identity transform's origin) and its
## velocity relative to the viewer (custom data); the vertex shader turns,
## widens, lengthens and dims it exactly as before. The buffer is written
## in one go; its fixed identity entries are filled once.
##
## Up to MAX_TRACERS are drawn, incoming rounds first (those not fired by
## the viewer's side): a ship with a dozen point-defence mounts can have
## more than a thousand of its own rounds out, and the round about to hit
## it must never be the one left undrawn.

const MAX_TRACERS := 4096
## Minimum tracer width (m) and growth per metre of camera distance
## (≈3 px at 70° FOV / 900 px, before glow).
const BASE_WIDTH_M := 0.5
const WIDTH_PER_M := 0.0035
## Ricochets: white-hot sparks with a longer streak, so the deflected path reads.
const RICOCHET_STREAK := 3.0
## Full size and glow out to this distance (m); beyond it, both fall off
## as NEAR_M / distance, down to FAR_SCALE.
const NEAR_M := 1500.0
const FAR_SCALE := 0.3
const GLOW := 6.0

## Unshaded, HDR-bright (so it blooms), dimmed with distance. The unit box
## is stretched along the relative velocity in the vertex stage.
const TRACER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords;
uniform vec3 tint = vec3(1.0, 0.68, 0.3);
uniform float energy = 6.0;
uniform float base_width = 0.5;
uniform float width_per_m = 0.0035;
uniform float near_m = 1500.0;
uniform float far_scale = 0.3;
varying float v_far;
void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - center;
	vec3 rel_v = INSTANCE_CUSTOM.xyz;
	float speed = length(rel_v);
	vec3 dir = speed > 1.0 ? rel_v / speed : vec3(0.0, 0.0, -1.0);
	vec3 up = abs(dir.y) > 0.98 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 z = -dir;
	vec3 x = normalize(cross(up, z));
	vec3 y = cross(z, x);
	float dist = distance(CAMERA_POSITION_WORLD, center);
	float far = clamp(near_m / max(dist, 1.0), far_scale, 1.0);
	float width = max(base_width, dist * width_per_m) * far;
	float len = clamp(speed * 0.012, 4.0, 30.0) * far + width * 6.0;
	VERTEX = center + x * local.x * width + y * local.y * width + z * local.z * len;
	v_far = far;
}
void fragment() {
	ALBEDO = tint * energy * v_far;
}
"""
## Floats per tracer instance in the buffer: a 3×4 transform, then custom data.
const STRIDE := 16

var _sparks: MultiMeshInstance3D
var _buf := PackedFloat32Array()


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	# Bright enough to bloom (Environment glow) and read at range.
	var shader := Shader.new()
	shader.code = TRACER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("energy", GLOW)
	box.material = mat
	mat.set_shader_parameter("base_width", BASE_WIDTH_M)
	mat.set_shader_parameter("width_per_m", WIDTH_PER_M)
	mat.set_shader_parameter("near_m", NEAR_M)
	mat.set_shader_parameter("far_scale", FAR_SCALE)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	mm.instance_count = MAX_TRACERS
	mm.visible_instance_count = 0
	multimesh = mm
	# Identity bases once; sync writes origins and velocities only.
	_buf.resize(MAX_TRACERS * STRIDE)
	_buf.fill(0.0)
	for i in MAX_TRACERS:
		_buf[i * STRIDE] = 1.0
		_buf[i * STRIDE + 5] = 1.0
		_buf[i * STRIDE + 10] = 1.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spark_box := BoxMesh.new()
	spark_box.size = Vector3.ONE
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color.BLACK
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(0.85, 0.95, 1.0)
	spark_mat.emission_energy_multiplier = 8.0
	spark_box.material = spark_mat
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_3D
	smm.mesh = spark_box
	smm.instance_count = MAX_TRACERS
	smm.visible_instance_count = 0
	_sparks = MultiMeshInstance3D.new()
	_sparks.multimesh = smm
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)


## `camera_position`: render space. `own`: shooter ids on the viewer's side
## (drawn after everyone else's when there are more rounds than tracers).
func sync(rounds: Array[ProjectileState], alpha: float, render_origin: Vector3,
		viewer_velocity: Vector3, camera_position: Vector3, own: Dictionary = {}) -> void:
	var ordered := draw_order(rounds, own)
	var tracers := 0
	var sparks := 0
	var a := clampf(alpha, 0.0, 1.0)
	for shot in ordered:
		if tracers >= MAX_TRACERS or sparks >= MAX_TRACERS:
			break
		var pos := shot.prev_position.lerp(shot.position, a) - render_origin
		var rel_v := shot.velocity - viewer_velocity
		if not shot.ricochet:
			var k := tracers * STRIDE
			_buf[k + 3] = pos.x
			_buf[k + 7] = pos.y
			_buf[k + 11] = pos.z
			_buf[k + 12] = rel_v.x
			_buf[k + 13] = rel_v.y
			_buf[k + 14] = rel_v.z
			tracers += 1
			continue
		var dir := rel_v.normalized() if rel_v.length() > 1.0 else Vector3.FORWARD
		var up := Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
		var dist := camera_position.distance_to(pos)
		var far := clampf(NEAR_M / maxf(dist, 1.0), FAR_SCALE, 1.0)
		var width := maxf(BASE_WIDTH_M, dist * WIDTH_PER_M) * far
		var length := clampf(rel_v.length() * 0.012, 4.0, 30.0) * far + width * 6.0
		if shot.ricochet:
			length *= RICOCHET_STREAK
			# Streak trails behind the spark: centre it half a length back.
			var b := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(width * 0.7, width * 0.7, length))
			_sparks.multimesh.set_instance_transform(sparks, Transform3D(b, pos - dir * length * 0.5))
			sparks += 1
	if tracers > 0:
		multimesh.buffer = _buf
	multimesh.visible_instance_count = tracers
	_sparks.multimesh.visible_instance_count = sparks
	drawn = tracers + sparks


## Rounds drawn by the last sync (tracers and ricochet sparks).
var drawn := 0


## The rounds to draw, at most MAX_TRACERS: everyone else's before those of
## `own` (shooter ids) when there are more rounds than tracers.
static func draw_order(rounds: Array[ProjectileState], own: Dictionary) -> Array[ProjectileState]:
	var out: Array[ProjectileState] = []
	if rounds.size() <= MAX_TRACERS or own.is_empty():
		out = rounds.slice(0, MAX_TRACERS)
		return out
	for shot in rounds:
		if not own.has(shot.shooter_id):
			out.append(shot)
	for shot in rounds:
		if out.size() >= MAX_TRACERS:
			break
		if own.has(shot.shooter_id):
			out.append(shot)
	return out.slice(0, MAX_TRACERS)
