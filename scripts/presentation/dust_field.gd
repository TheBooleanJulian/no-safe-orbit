class_name DustField
extends MultiMeshInstance3D
## Infinite field of motes fixed in the local frame. In empty space this is the
## only cue for translation, so it is a gameplay aid rather than decoration.
## A cube of motes is tiled 3×3×3 and wrapped around the render origin, so it
## stays seamless however far the ship travels (no float precision growth).
## Main runs two layers with different tile sizes (1.5 km and 1.9 km), so the
## combined pattern only repeats every ~28 km.

@export var tile_size_m: float = 1500.0
@export var motes_per_tile: int = 140
@export var seed_value: int = 1337


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points: Array[Vector3] = []
	for i in motes_per_tile:
		points.append(Vector3(rng.randf(), rng.randf(), rng.randf()) * tile_size_m)

	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	sphere.radial_segments = 6
	sphere.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.45, 0.6)
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	# min > max: fully visible up close, fades out before the tile edge.
	mat.distance_fade_min_distance = tile_size_m * 0.95
	mat.distance_fade_max_distance = tile_size_m * 0.55
	sphere.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = motes_per_tile * 27
	var idx := 0
	for tx in [-1, 0, 1]:
		for ty in [-1, 0, 1]:
			for tz in [-1, 0, 1]:
				var tile_offset := Vector3(tx, ty, tz) * tile_size_m
				for p in points:
					var s := rng.randf_range(0.5, 1.6)
					mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), p + tile_offset))
					idx += 1
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Keep the field fixed in the local frame while rendering around the render
## origin. `continuous_origin` is the render origin in rebase-continuous
## coordinates (WorldSimulation.continuous_position), so frame rebases never
## make the dust jump.
func update_origin(continuous_origin: Vec3d) -> void:
	position = -Vector3(
		fposmod(continuous_origin.x, tile_size_m),
		fposmod(continuous_origin.y, tile_size_m),
		fposmod(continuous_origin.z, tile_size_m))
