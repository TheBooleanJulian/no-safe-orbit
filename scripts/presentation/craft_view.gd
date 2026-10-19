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
	var e := config.hit_box_half_extents
	CraftView.build_model(self, config, config.cannon != null, hostile)
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


## The craft's 3D model under `parent` (also used for craft sitting docked
## on a carrier). Fighter: a lifting-body fuselage with canopy, swept wings
## with wingtip lights, twin fins, a nose gun and an engine bell. Drone: a
## sensor body on four arms with thruster pods, a dish and solar panels.
static func build_model(parent: Node3D, cfg: ShipConfig, fighter: bool, is_hostile: bool) -> void:
	var e := cfg.hit_box_half_extents
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.7, 0.74, 0.76) * (Color(1.0, 0.75, 0.72) if is_hostile else Color.WHITE)
	hull.metallic = 0.5
	hull.roughness = 0.5
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.18, 0.2, 0.22)
	dark.metallic = 0.4
	dark.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	accent.albedo_color = CyberTheme.MAGENTA if is_hostile else CyberTheme.CYAN
	if fighter:
		var body := _mesh(parent, CapsuleMesh.new(), Vector3.ZERO, hull)
		(body.mesh as CapsuleMesh).radius = e.y * 0.45
		(body.mesh as CapsuleMesh).height = e.z * 2.0
		body.rotation_degrees = Vector3(90, 0, 0)
		var canopy := _mesh(parent, SphereMesh.new(), Vector3(0, e.y * 0.35, -e.z * 0.45), accent)
		(canopy.mesh as SphereMesh).radius = e.y * 0.28
		(canopy.mesh as SphereMesh).height = e.y * 0.4
		for side in [-1.0, 1.0]:
			var wing := _box_in(parent, Vector3(e.x * 0.95, e.y * 0.08, e.z * 0.75), Vector3(side * e.x * 0.5, -e.y * 0.05, e.z * 0.2), hull)
			wing.rotation_degrees = Vector3(0, side * -18.0, 0)
			_box_in(parent, Vector3(0.2, 0.2, 0.2), Vector3(side * e.x * 0.95, -e.y * 0.05, e.z * 0.45), accent)
			var fin := _box_in(parent, Vector3(e.x * 0.05, e.y * 0.6, e.z * 0.4), Vector3(side * e.x * 0.18, e.y * 0.45, e.z * 0.7), dark)
			fin.rotation_degrees = Vector3(0, 0, side * -12.0)
		var gun := _mesh(parent, CylinderMesh.new(), Vector3(0, -e.y * 0.2, -e.z - 0.5), dark)
		(gun.mesh as CylinderMesh).top_radius = 0.08
		(gun.mesh as CylinderMesh).bottom_radius = 0.1
		(gun.mesh as CylinderMesh).height = 1.6
		gun.rotation_degrees = Vector3(90, 0, 0)
		var bell := _mesh(parent, CylinderMesh.new(), Vector3(0, 0, e.z * 1.05), dark)
		(bell.mesh as CylinderMesh).top_radius = e.y * 0.35
		(bell.mesh as CylinderMesh).bottom_radius = e.y * 0.22
		(bell.mesh as CylinderMesh).height = e.z * 0.3
		bell.rotation_degrees = Vector3(90, 0, 0)
		return
	var core := _mesh(parent, SphereMesh.new(), Vector3.ZERO, hull)
	(core.mesh as SphereMesh).radius = e.x * 0.45
	(core.mesh as SphereMesh).height = e.x * 0.8
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var arm := _box_in(parent, Vector3(e.x * 0.9, 0.12, 0.12), dir * e.x * 0.55, dark)
		arm.rotation = Vector3(0, -a, 0)
		var pod := _mesh(parent, CylinderMesh.new(), dir * e.x, hull)
		(pod.mesh as CylinderMesh).top_radius = e.x * 0.14
		(pod.mesh as CylinderMesh).bottom_radius = e.x * 0.18
		(pod.mesh as CylinderMesh).height = e.y * 0.6
		_box_in(parent, Vector3(0.12, 0.12, 0.12), dir * e.x + Vector3(0, e.y * 0.35, 0), accent)
	var dish := _mesh(parent, CylinderMesh.new(), Vector3(0, e.y * 0.55, 0), hull)
	(dish.mesh as CylinderMesh).top_radius = e.x * 0.4
	(dish.mesh as CylinderMesh).bottom_radius = e.x * 0.1
	(dish.mesh as CylinderMesh).height = e.y * 0.25
	for side in [-1.0, 1.0]:
		_box_in(parent, Vector3(e.x * 1.1, 0.04, e.z * 0.5), Vector3(side * e.x * 1.25, 0, 0), accent)


static func _mesh(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box_in(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, pos, mat)
