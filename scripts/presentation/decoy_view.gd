class_name DecoyView
extends MultiMeshInstance3D
## Flares in flight (WorldSimulation.decoys): white-hot points that flicker,
## cool to orange and shrink as they burn down, widened with distance (like
## tracers) so a pattern reads at a few kilometres. Read-only view.

const MAX_DECOYS := 256
const BASE_SIZE_M := 1.6
const SIZE_PER_M := 0.004
const GLOW := 8.0

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float energy = 8.0;
void fragment() {
	ALBEDO = COLOR.rgb * energy * COLOR.a;
}
"""


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 10
	sphere.rings = 5
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("energy", GLOW)
	sphere.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sphere
	mm.instance_count = MAX_DECOYS
	mm.visible_instance_count = 0
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## `render_origin`: subtracted from each flare's local-frame position.
func sync(decoys: Array[Dictionary], render_origin: Vector3, camera_position: Vector3, clock: float) -> void:
	var n := mini(decoys.size(), MAX_DECOYS)
	for i in n:
		var d: Dictionary = decoys[i]
		var pos: Vector3 = (d.position as Vector3) - render_origin
		var burn := clampf(1.0 - float(d.age) / float(d.life), 0.0, 1.0)
		var flicker := 0.8 + 0.2 * sin(clock * 37.0 + float(d.id) * 1.7)
		var size := maxf(BASE_SIZE_M, camera_position.distance_to(pos) * SIZE_PER_M) * (0.5 + 0.5 * burn) * flicker
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), pos))
		var col := Color(1.0, 0.55, 0.2).lerp(Color(1.0, 0.97, 0.9), burn)
		col.a = 0.35 + 0.65 * burn
		multimesh.set_instance_color(i, col)
	multimesh.visible_instance_count = n
