class_name Starfield
extends MultiMeshInstance3D
## Distant stars at a fixed radius around the camera. Translation never moves
## them (infinitely far); rotation does — the main cue for ship attitude.

@export var star_count: int = 2500
@export var radius_m: float = 80_000.0
@export var seed_value: int = 42


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 4
	sphere.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	sphere.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sphere
	mm.instance_count = star_count
	for i in star_count:
		# Uniform direction on the sphere.
		var z := rng.randf_range(-1.0, 1.0)
		var t := rng.randf_range(0.0, TAU)
		var r := sqrt(1.0 - z * z)
		var dir := Vector3(r * cos(t), r * sin(t), z)
		var size := rng.randf_range(60.0, 170.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), dir * radius_m))
		var warmth := rng.randf()
		var brightness := rng.randf_range(0.45, 1.0)
		mm.set_instance_color(i, Color(0.8 + 0.2 * warmth, 0.85, 1.0 - 0.25 * warmth) * brightness)
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
