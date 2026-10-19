class_name MissileView
extends Node3D
## View of a missile in flight: a slim body with fins and a bright additive
## exhaust while the motor burns. Read-only, like CraftView.

var hostile: bool = false

var _exhaust: MeshInstance3D


func _ready() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.72, 0.74, 0.78)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.4
	var body := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.22
	tube.bottom_radius = 0.22
	tube.height = 2.6
	body.mesh = tube
	body.material_override = body_mat
	body.rotation_degrees = Vector3(90, 0, 0)
	add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22
	cone.height = 0.6
	nose.mesh = cone
	nose.material_override = body_mat
	nose.rotation_degrees = Vector3(-90, 0, 0)
	nose.position = Vector3(0, 0, -1.6)
	add_child(nose)
	var band_mat := StandardMaterial3D.new()
	band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_mat.albedo_color = CyberTheme.MAGENTA if hostile else CyberTheme.CYAN
	for k in 4:
		var fin := MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = Vector3(0.04, 0.5, 0.5)
		fin.mesh = plate
		fin.material_override = band_mat
		fin.position = Vector3(0, 0, 1.05)
		fin.rotation = Vector3(0, 0, PI * 0.5 * k)
		fin.position += fin.basis * Vector3(0, 0.35, 0)
		add_child(fin)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame.albedo_color = Color(1.0, 0.75, 0.45, 0.8)
	var plume := CylinderMesh.new()
	plume.top_radius = 0.05
	plume.bottom_radius = 0.3
	plume.height = 3.0
	_exhaust = MeshInstance3D.new()
	_exhaust.mesh = plume
	_exhaust.material_override = flame
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_exhaust.rotation_degrees = Vector3(-90, 0, 0)
	_exhaust.position = Vector3(0, 0, 2.8)
	add_child(_exhaust)


func sync_from(state: ShipState, alpha: float, render_origin: Vector3) -> void:
	position = state.interpolated_position(alpha) - render_origin
	quaternion = state.interpolated_orientation(alpha)
	_exhaust.visible = -state.last_thrust_body.z > 1.0
