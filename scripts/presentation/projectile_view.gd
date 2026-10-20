class_name ProjectileView
extends MultiMeshInstance3D
## Tracers for rounds in flight: thin glowing streaks along each round's
## velocity relative to the viewer, widened with distance so they stay a few
## pixels wide out to NEAR_M; further out they shrink and dim (to FAR_SCALE)
## so a distant exchange reads as distant. Read-only view of
## WorldSimulation rounds.
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

## Unshaded, HDR-bright (so it blooms), dimmed per tracer by its colour alpha.
const TRACER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 tint = vec3(1.0, 0.68, 0.3);
uniform float energy = 6.0;
void fragment() {
	ALBEDO = tint * energy * COLOR.a;
}
"""

var _sparks: MultiMeshInstance3D


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
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = MAX_TRACERS
	mm.visible_instance_count = 0
	multimesh = mm
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
	for shot in ordered:
		if tracers >= MAX_TRACERS or sparks >= MAX_TRACERS:
			break
		var pos := shot.interpolated_position(alpha) - render_origin
		var rel_v := shot.velocity - viewer_velocity
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
			continue
		var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(width, width, length))
		multimesh.set_instance_transform(tracers, Transform3D(basis, pos))
		multimesh.set_instance_color(tracers, Color(1, 1, 1, far))
		tracers += 1
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
