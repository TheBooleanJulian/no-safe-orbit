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


func sync(rounds: Array[ProjectileState], alpha: float, render_origin: Vector3,
		viewer_velocity: Vector3, camera: Camera3D) -> void:
	var count := mini(rounds.size(), MAX_TRACERS)
	for i in count:
		var shot := rounds[i]
		var pos := shot.interpolated_position(alpha) - render_origin
		var rel_v := shot.velocity - viewer_velocity
		var dir := rel_v.normalized() if rel_v.length() > 1.0 else Vector3.FORWARD
		var up := Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
		var width := maxf(BASE_WIDTH_M, camera.global_position.distance_to(pos) * WIDTH_PER_M)
		var length := clampf(rel_v.length() * 0.012, 4.0, 30.0) + width * 6.0
		var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(width, width, length))
		multimesh.set_instance_transform(i, Transform3D(basis, pos))
	multimesh.visible_instance_count = count
