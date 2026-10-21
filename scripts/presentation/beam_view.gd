class_name BeamView
extends Node3D
## Beam pulses (play-test batch 6): a bright line from the muzzle to where
## the pulse struck — or out to its full reach — fading over LIFE_S. Both
## ends ride with their ships (WorldSimulation.take_beams gives them in body
## frames), so a pulse stays on the hull it hit while the fight moves.
## The width grows with distance from the camera so a far beam still shows.

const LIFE_S := 0.18
const POOL := 64
## Width (m) per metre from the camera, and the least width.
const WIDTH_PER_M := 0.0015
const MIN_WIDTH_M := 0.25

var _pulses: Array[Dictionary] = []
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	for i in POOL:
		var m := MeshInstance3D.new()
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_meshes.append(m)


func add(pulses: Array[Dictionary]) -> void:
	for p in pulses:
		p.age = 0.0
		_pulses.append(p)
	if _pulses.size() > POOL:
		_pulses = _pulses.slice(_pulses.size() - POOL)


func active_count() -> int:
	return _pulses.size()


func sync(world: WorldSimulation, alpha: float, render_origin: Vector3, camera_pos: Vector3, delta: float) -> void:
	for p in _pulses:
		p.age = float(p.age) + delta
	_pulses = _pulses.filter(func(p: Dictionary) -> bool: return float(p.age) < LIFE_S)
	for i in _meshes.size():
		var m := _meshes[i]
		m.visible = false
		if i >= _pulses.size():
			continue
		var p := _pulses[i]
		var shooter := world.get_ship(p.shooter_id)
		if shooter == null:
			continue
		var a := shooter.interpolated_position(alpha) + shooter.interpolated_orientation(alpha) * Vector3(p.from_body) - render_origin
		var b := a + Vector3(p.to_body)
		var target := world.get_ship(p.target_id) if StringName(p.target_id) != &"" else null
		if target != null:
			b = target.interpolated_position(alpha) + target.interpolated_orientation(alpha) * Vector3(p.to_body) - render_origin
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var y := (b - a) / length
		var u := clampf((camera_pos - a).dot(y), 0.0, length)
		var width := maxf(MIN_WIDTH_M, camera_pos.distance_to(a + y * u) * WIDTH_PER_M)
		var x := y.cross(Vector3.UP)
		if x.length_squared() < 1e-6:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(y)
		m.transform = Transform3D(Basis(x * width, y * length, z * width), (a + b) * 0.5)
		var fade := 1.0 - float(p.age) / LIFE_S
		var c: Color = p.color
		(m.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, fade)
		m.visible = true
