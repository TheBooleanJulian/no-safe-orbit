class_name ShipView
extends Node3D
## Visual stand-in for a ShipState. Read-only view: it copies interpolated
## state each frame and never feeds anything back into the simulation.
## Placeholder geometry is generated in code (~60 m frigate silhouette) until
## Milestone 2 generates hulls from blueprint modules.

@export var hull_color: Color = Color(0.55, 0.58, 0.62)
@export var accent_color: Color = Color(0.9, 0.55, 0.15)

var ship_id: StringName

var _plume_root: Node3D
var _plume_material: StandardMaterial3D


func _ready() -> void:
	_build_placeholder()


## Position relative to the floating render origin (usually the player ship).
func sync_from(state: ShipState, alpha: float, render_origin: Vector3) -> void:
	position = state.interpolated_position(alpha) - render_origin
	quaternion = state.interpolated_orientation(alpha)
	var fwd_fraction := 0.0
	if state.config.thrust_forward_n > 0.0:
		fwd_fraction = clampf(-state.last_thrust_body.z / state.config.thrust_forward_n, 0.0, 1.0)
	_plume_root.visible = fwd_fraction > 0.01
	_plume_root.scale = Vector3(1.0, 1.0, lerpf(0.2, 1.0, fwd_fraction))
	_plume_material.albedo_color.a = 0.15 + 0.4 * fwd_fraction


func _build_placeholder() -> void:
	var hull_mat := _material(hull_color)
	var accent_mat := _material(accent_color)
	var dark_mat := _material(hull_color.darkened(0.6))

	# Main hull, 44 m long (body Z), centred.
	_add_box(Vector3(12, 9, 44), Vector3.ZERO, hull_mat)
	# Nose cone pointing -Z.
	_add_cone(5.5, 12.0, Vector3(0, 0, -28), Vector3(-90, 0, 0), hull_mat)
	# Command block on top, slightly forward — reads "up" at a glance.
	_add_box(Vector3(6, 3, 10), Vector3(0, 6, -10), accent_mat)
	# Side sponsons.
	_add_box(Vector3(4, 5, 24), Vector3(-8, -1, 6), hull_mat)
	_add_box(Vector3(4, 5, 24), Vector3(8, -1, 6), hull_mat)
	# Twin engine bells at the stern (+Z).
	for x in [-3.5, 3.5]:
		_add_cone(2.8, 4.0, Vector3(x, 0, 24), Vector3(90, 0, 0), dark_mat, 1.8)

	# Engine plumes: one cone per bell, pointing aft, length ∝ main thrust.
	_plume_root = Node3D.new()
	_plume_root.position = Vector3(0, 0, 26)
	_plume_root.visible = false
	add_child(_plume_root)
	_plume_material = StandardMaterial3D.new()
	_plume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plume_material.albedo_color = Color(0.45, 0.7, 1.0, 0.4)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.4   # far end: tapers away
	cone.bottom_radius = 1.6  # nozzle end
	cone.height = 18.0
	cone.cap_top = false
	cone.cap_bottom = false
	for x in [-3.5, 3.5]:
		var plume := MeshInstance3D.new()
		plume.mesh = cone
		plume.material_override = _plume_material
		# Cylinder +Y → +Z; shifted half its length so scaling the root along Z
		# keeps the nozzle end anchored at the bells.
		plume.rotation_degrees = Vector3(90, 0, 0)
		plume.position = Vector3(x, 0, 9.0)
		_plume_root.add_child(plume)


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.4
	mat.roughness = 0.55
	return mat


func _add_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _add_cone(radius: float, height: float, pos: Vector3, rot_deg: Vector3, mat: Material, base_radius := -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0 if base_radius < 0.0 else radius
	mesh.bottom_radius = radius if base_radius < 0.0 else base_radius
	mesh.height = height
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
