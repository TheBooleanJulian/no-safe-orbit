class_name ShipView
extends Node3D
## Visual stand-in for a ShipState. Read-only view: it copies interpolated
## state each frame and never feeds anything back into the simulation.
## Geometry is generated from the ship's blueprint (ShipModelBuilder), with
## the model origin at the design's centre of mass (the body origin).

var ship_id: StringName
## Set before adding to the tree.
var blueprint: ShipBlueprint
var grid: ShipGrid
var stats: ShipStats
var tint: Color = Color.WHITE

var _plumes: Array[Node3D] = []
var _plume_material: StandardMaterial3D
var _parts: Dictionary = {}
var _wreck_material: StandardMaterial3D


func _ready() -> void:
	var model := ShipModelBuilder.build(blueprint, grid, stats.center_of_mass_m, tint)
	add_child(model.root)
	_parts = model.parts
	_build_plumes(model.engine_nozzles)
	_wreck_material = StandardMaterial3D.new()
	_wreck_material.albedo_color = Color(0.12, 0.1, 0.09)
	_wreck_material.roughness = 1.0


## Position relative to the floating render origin (usually the player ship).
func sync_from(state: ShipState, alpha: float, render_origin: Vector3) -> void:
	position = state.interpolated_position(alpha) - render_origin
	quaternion = state.interpolated_orientation(alpha)
	var fwd_fraction := 0.0
	if state.config.thrust_forward_n > 0.0:
		fwd_fraction = clampf(-state.last_thrust_body.z / state.config.thrust_forward_n, 0.0, 1.0)
	for pivot in _plumes:
		pivot.visible = fwd_fraction > 0.01
		pivot.scale = Vector3(1.0, 1.0, lerpf(0.2, 1.0, fwd_fraction))
	_plume_material.albedo_color.a = 0.15 + 0.4 * fwd_fraction
	if state.systems != null:
		_show_damage(state.systems)


## Destroyed external systems disappear; wrecked modules turn charred.
func _show_damage(systems: ShipSystems) -> void:
	for e in systems.equipment:
		if e.destroyed() and _parts.has(e.id):
			(_parts[e.id] as Node3D).visible = false
	for i in systems.modules.size():
		var id := systems.blueprint.modules[i].id
		if systems.modules[i].wrecked() and _parts.has(id):
			(_parts[id] as MeshInstance3D).material_override = _wreck_material


## One additive cone per main engine, pointing aft; length ∝ main thrust.
func _build_plumes(nozzles: Array[Vector3]) -> void:
	_plume_material = StandardMaterial3D.new()
	_plume_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_plume_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_plume_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_plume_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plume_material.albedo_color = Color(0.45, 0.7, 1.0, 0.4)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.3   # far end: tapers away
	cone.bottom_radius = 1.2  # nozzle end
	cone.height = 14.0
	cone.cap_top = false
	cone.cap_bottom = false
	for nozzle in nozzles:
		# Pivot at the nozzle so scaling along Z keeps the plume attached.
		var pivot := Node3D.new()
		pivot.position = nozzle
		pivot.visible = false
		add_child(pivot)
		var plume := MeshInstance3D.new()
		plume.mesh = cone
		plume.material_override = _plume_material
		plume.rotation_degrees = Vector3(90, 0, 0)  # cylinder +Y → +Z (aft)
		plume.position = Vector3(0, 0, cone.height * 0.5)
		pivot.add_child(plume)
		_plumes.append(pivot)
