class_name MissileView
extends Node3D
## View of a missile in flight: a slim body with fins and a bright additive
## exhaust while the motor burns. Read-only, like CraftView.
##
## Body, nose and fins are merged into one mesh (two surfaces) shared by
## every missile on a side, and nothing casts shadows: a big salvo is dozens
## of these, and separate parts cost a draw call each.

var hostile: bool = false

var _exhaust: MeshInstance3D

static var _bodies: Dictionary = {}  # hostile: bool -> ArrayMesh
static var _plume: CylinderMesh
static var _flame: StandardMaterial3D


func _ready() -> void:
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh(hostile)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	_exhaust = MeshInstance3D.new()
	_exhaust.mesh = _plume_mesh()
	_exhaust.material_override = _flame
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_exhaust.rotation_degrees = Vector3(-90, 0, 0)
	_exhaust.position = Vector3(0, 0, 2.8)
	add_child(_exhaust)


func sync_from(state: ShipState, alpha: float, render_origin: Vector3) -> void:
	position = state.interpolated_position(alpha) - render_origin
	quaternion = state.interpolated_orientation(alpha)
	_exhaust.visible = -state.last_thrust_body.z > 1.0


static func _body_mesh(is_hostile: bool) -> ArrayMesh:
	if _bodies.has(is_hostile):
		return _bodies[is_hostile]
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.72, 0.74, 0.78)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.4
	var band_mat := StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.albedo_color = CyberTheme.MAGENTA if is_hostile else CyberTheme.CYAN
	var tube := CylinderMesh.new()
	tube.top_radius = 0.22
	tube.bottom_radius = 0.22
	tube.height = 2.6
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22
	cone.height = 0.6
	var plate := BoxMesh.new()
	plate.size = Vector3(0.04, 0.5, 0.5)
	# Detail (play-test batch 10): a flared nozzle, a band and four canards.
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = 0.2
	nozzle.bottom_radius = 0.14
	nozzle.height = 0.35
	var band := CylinderMesh.new()
	band.top_radius = 0.24
	band.bottom_radius = 0.24
	band.height = 0.1
	var canard := BoxMesh.new()
	canard.size = Vector3(0.03, 0.22, 0.26)
	var shell := SurfaceTool.new()
	shell.append_from(tube, 0, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3.ZERO))
	shell.append_from(cone, 0, Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 0, -1.6)))
	shell.append_from(nozzle, 0, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0, 1.45)))
	var fins := SurfaceTool.new()
	for k in 4:
		var b := Basis.from_euler(Vector3(0, 0, PI * 0.5 * k))
		fins.append_from(plate, 0, Transform3D(b, Vector3(0, 0, 1.05) + b * Vector3(0, 0.35, 0)))
		var c := Basis.from_euler(Vector3(0, 0, PI * 0.5 * k + PI * 0.25))
		fins.append_from(canard, 0, Transform3D(c, Vector3(0, 0, -0.95) + c * Vector3(0, 0.3, 0)))
	fins.append_from(band, 0, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0, -0.35)))
	var mesh := shell.commit()
	mesh.surface_set_material(0, body_mat)
	fins.commit(mesh)
	mesh.surface_set_material(1, band_mat)
	_bodies[is_hostile] = mesh
	return mesh


static func _plume_mesh() -> CylinderMesh:
	if _plume == null:
		_flame = StandardMaterial3D.new()
		_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flame.albedo_color = Color(1.0, 0.75, 0.45, 0.8)
		_plume = CylinderMesh.new()
		_plume.top_radius = 0.05
		_plume.bottom_radius = 0.3
		_plume.height = 3.0
	return _plume
