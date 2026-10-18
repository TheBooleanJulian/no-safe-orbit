class_name ShipModelBuilder
extends RefCounted
## Placeholder 3D geometry generated from a blueprint: one box per hull module
## and simple shapes for external equipment. Shared by the flight view and
## the shipyard preview so both show the same ship. Geometry is visual only;
## simulation truth stays in the blueprint and ShipStats.


class Model:
	var root: Node3D
	## Main-engine nozzle positions (body frame), for plumes.
	var engine_nozzles: Array[Vector3] = []


## `origin_m`: grid-metre point placed at the model origin (normally the
## centre of mass). `tint` multiplies every colour (e.g. to mark the enemy).
static func build(bp: ShipBlueprint, grid: ShipGrid, origin_m: Vector3, tint: Color = Color.WHITE) -> Model:
	var model := Model.new()
	model.root = Node3D.new()
	model.root.name = "ShipModel"
	var mats := {}
	var c := ShipGrid.CELL_SIZE_M
	for i in bp.modules.size():
		var def := grid.module_def(i)
		if def == null:
			continue
		var size_m := Vector3(grid.module_size(i)) * c
		var center := Vector3(bp.modules[i].position) * c + size_m * 0.5 - origin_m
		_box(model.root, size_m - Vector3.ONE * 0.15, center, _mat(mats, def.color * tint))
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or not def.is_external():
			continue
		var normal := Vector3(ShipGrid.FACE_NORMALS.get(bp.equipment[i].face, Vector3i.ZERO))
		var mount := grid.equipment_position_m(i) - origin_m
		var mat := _mat(mats, def.color * tint)
		match def.kind:
			EquipmentDefinition.Kind.MAIN_ENGINE:
				# Cylinder +Y is rotated to +Z (aft): top = aft end = wide mouth.
				var bell := _cylinder(model.root, 1.4, 0.7, 2.4, mount + normal * 1.2, mat)
				bell.rotation_degrees = Vector3(90, 0, 0)
				model.engine_nozzles.append(mount + normal * 2.4)
			EquipmentDefinition.Kind.RCS:
				_box(model.root, Vector3.ONE * 0.9, mount + normal * 0.45, mat)
			EquipmentDefinition.Kind.CANNON:
				_box(model.root, Vector3(1.8, 0.9, 1.8), mount + normal * 0.45, mat)
				var barrel := _cylinder(model.root, 0.16, 0.16, 5.0, mount + normal * 0.6 + Vector3(0, 0, -2.5), mat)
				barrel.rotation_degrees = Vector3(90, 0, 0)
			EquipmentDefinition.Kind.RADIATOR:
				var fin := Vector3(0.12, 3.0, 2.8) if normal.y != 0.0 else Vector3(3.0, 0.12, 2.8)
				_box(model.root, fin, mount + normal * 1.5, mat)
	return model


static func _mat(cache: Dictionary, color: Color) -> StandardMaterial3D:
	if not cache.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = 0.4
		mat.roughness = 0.55
		cache[color] = mat
	return cache[color]


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cylinder(parent: Node3D, top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
