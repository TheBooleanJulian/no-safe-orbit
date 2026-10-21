class_name DecoyView
extends MultiMeshInstance3D
## Flares in flight (WorldSimulation.decoys): white-hot points that flicker,
## cool to orange and shrink as they burn down, widened with distance (like
## tracers) so a pattern reads at a few kilometres. Each leaves a trail of
## smoke-lit sparks that dim away over TRAIL_LIFE_S (play-test batch 11).
## Read-only view.

const MAX_DECOYS := 256
const BASE_SIZE_M := 2.2
const SIZE_PER_M := 0.005
const GLOW := 14.0
## The trail: a spark every TRAIL_EVERY_S per flare, fading over TRAIL_LIFE_S.
const MAX_TRAIL := 2048
const TRAIL_EVERY_S := 0.08
const TRAIL_LIFE_S := 3.0
const TRAIL_SIZE := 0.55
var _trail: Array[Dictionary] = []  # {position (local frame), born}
var _trail_clock: Dictionary = {}  # decoy id -> when it last dropped a spark
var _trail_mesh: MultiMeshInstance3D
var _epoch := 0

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
	var trail := MultiMesh.new()
	trail.transform_format = MultiMesh.TRANSFORM_3D
	trail.use_colors = true
	trail.mesh = sphere
	trail.instance_count = MAX_TRAIL
	trail.visible_instance_count = 0
	_trail_mesh = MultiMeshInstance3D.new()
	_trail_mesh.multimesh = trail
	_trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail_mesh)


## `render_origin`: subtracted from each flare's local-frame position.
## `epoch`: the frame's rebase count — a rebase moves every local position,
## so the trail laid before it is dropped.
func sync(decoys: Array[Dictionary], render_origin: Vector3, camera_position: Vector3, clock: float, epoch: int = 0) -> void:
	_sync_trail(decoys, render_origin, camera_position, clock, epoch)
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


func _sync_trail(decoys: Array[Dictionary], render_origin: Vector3, camera_position: Vector3, clock: float, epoch: int) -> void:
	if _trail_mesh == null:
		return
	if epoch != _epoch:
		_epoch = epoch
		_trail.clear()
	for d in decoys:
		var id: int = d.id
		if clock - float(_trail_clock.get(id, -INF)) >= TRAIL_EVERY_S and float(d.age) < float(d.life):
			_trail_clock[id] = clock
			_trail.append({"position": d.position, "born": clock})
	var alive: Array[Dictionary] = []
	for p in _trail:
		if clock - float(p.born) < TRAIL_LIFE_S:
			alive.append(p)
	if alive.size() > MAX_TRAIL:
		alive = alive.slice(alive.size() - MAX_TRAIL)
	_trail = alive
	var mm := _trail_mesh.multimesh
	for i in _trail.size():
		var p: Dictionary = _trail[i]
		var fade := 1.0 - (clock - float(p.born)) / TRAIL_LIFE_S
		var pos: Vector3 = (p.position as Vector3) - render_origin
		var size := maxf(BASE_SIZE_M, camera_position.distance_to(pos) * SIZE_PER_M) * TRAIL_SIZE * (0.6 + 0.4 * fade)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), pos))
		mm.set_instance_color(i, Color(1.0, 0.75, 0.5, 0.35 * fade * fade))
	mm.visible_instance_count = _trail.size()
	if _trail_clock.size() > 4 * MAX_DECOYS:
		_trail_clock.clear()
