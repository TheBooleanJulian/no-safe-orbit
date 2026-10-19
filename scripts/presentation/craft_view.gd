class_name CraftView
extends Node3D
## View of an autonomous craft (fighter or drone): a small procedural model
## in the hull plating, an engine plume when it burns, and its callsign.
## Read-only, like ShipView.

var craft_id: StringName
var config: ShipConfig
var callsign: String = ""
var hostile: bool = false

var _plume: Node3D
var _plume_mat: StandardMaterial3D


func _ready() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.7, 0.74, 0.76) * (Color(1.0, 0.75, 0.72) if hostile else Color.WHITE)
	hull.metallic = 0.5
	hull.roughness = 0.5
	var accent := StandardMaterial3D.new()
	accent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	accent.albedo_color = CyberTheme.MAGENTA if hostile else CyberTheme.CYAN
	var e := config.hit_box_half_extents
	if config.cannon != null:
		# Fighter: fuselage, swept wings, canopy, gun.
		_box(Vector3(e.x * 0.3, e.y * 0.8, e.z * 2.0), Vector3.ZERO, hull)
		_box(Vector3(e.x * 2.0, e.y * 0.15, e.z * 0.7), Vector3(0, 0, e.z * 0.35), hull)
		_box(Vector3(e.x * 0.25, e.y * 0.35, e.z * 0.5), Vector3(0, e.y * 0.5, -e.z * 0.4), accent)
		_box(Vector3(0.15, 0.15, 2.0), Vector3(0, -e.y * 0.2, -e.z - 0.8), hull)
	else:
		# Drone: a body with sensor dish and solar wings.
		var body := SphereMesh.new()
		body.radius = e.x * 0.7
		body.height = e.x * 1.4
		var mi := MeshInstance3D.new()
		mi.mesh = body
		mi.material_override = hull
		add_child(mi)
		_box(Vector3(e.x * 3.0, 0.05, e.z * 0.8), Vector3.ZERO, accent)
	_plume_mat = StandardMaterial3D.new()
	_plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume_mat.albedo_color = Color(0.5, 0.8, 1.0, 0.5)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = e.y * 0.5
	cone.height = e.z * 1.5
	_plume = Node3D.new()
	_plume.position = Vector3(0, 0, e.z)
	add_child(_plume)
	var plume := MeshInstance3D.new()
	plume.mesh = cone
	plume.material_override = _plume_mat
	plume.rotation_degrees = Vector3(90, 0, 0)
	plume.position = Vector3(0, 0, cone.height * 0.5)
	_plume.add_child(plume)
	var label := Label3D.new()
	label.text = callsign
	label.pixel_size = 0.02
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = CyberTheme.MAGENTA if hostile else CyberTheme.CYAN
	label.position = Vector3(0, e.y + 2.5, 0)
	add_child(label)


func sync_from(state: ShipState, alpha: float, render_origin: Vector3) -> void:
	position = state.interpolated_position(alpha) - render_origin
	quaternion = state.interpolated_orientation(alpha)
	var fwd := clampf(-state.last_thrust_body.z / maxf(state.config.thrust_forward_n, 1.0), 0.0, 1.0)
	_plume.visible = fwd > 0.02
	_plume.scale = Vector3(1, 1, lerpf(0.3, 1.0, fwd))


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
