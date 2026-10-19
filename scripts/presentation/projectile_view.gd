class_name ProjectileView
extends MultiMeshInstance3D
## Tracers for rounds in flight: thin glowing streaks along each round's
## velocity relative to the viewer, widened with distance so they stay a few
## pixels wide at long range. Read-only view of WorldSimulation rounds.

const MAX_TRACERS := 512
## Minimum tracer width (m) and growth per metre of camera distance
## (≈3 px at 70° FOV / 900 px, before glow).
const BASE_WIDTH_M := 0.5
const WIDTH_PER_M := 0.0035
## Ricochets: white-hot sparks with a longer streak, so the deflected path reads.
const RICOCHET_STREAK := 3.0

var _sparks: MultiMeshInstance3D


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	# Strong emission so tracers bloom (Environment glow) and read at range.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.68, 0.3)
	mat.emission_energy_multiplier = 6.0
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
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


func sync(rounds: Array[ProjectileState], alpha: float, render_origin: Vector3,
		viewer_velocity: Vector3, camera: Camera3D) -> void:
	var tracers := 0
	var sparks := 0
	for shot in rounds:
		if tracers >= MAX_TRACERS or sparks >= MAX_TRACERS:
			break
		var pos := shot.interpolated_position(alpha) - render_origin
		var rel_v := shot.velocity - viewer_velocity
		var dir := rel_v.normalized() if rel_v.length() > 1.0 else Vector3.FORWARD
		var up := Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
		var width := maxf(BASE_WIDTH_M, camera.global_position.distance_to(pos) * WIDTH_PER_M)
		var length := clampf(rel_v.length() * 0.012, 4.0, 30.0) + width * 6.0
		if shot.ricochet:
			length *= RICOCHET_STREAK
			# Streak trails behind the spark: centre it half a length back.
			var b := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(width * 0.7, width * 0.7, length))
			_sparks.multimesh.set_instance_transform(sparks, Transform3D(b, pos - dir * length * 0.5))
			sparks += 1
			continue
		var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(width, width, length))
		multimesh.set_instance_transform(tracers, Transform3D(basis, pos))
		tracers += 1
	multimesh.visible_instance_count = tracers
	_sparks.multimesh.visible_instance_count = sparks
