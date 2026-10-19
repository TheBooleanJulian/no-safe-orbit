class_name ShipModelBuilder
extends RefCounted
## Placeholder 3D geometry generated from a blueprint: one box per hull module
## and simple shapes for external equipment. Shared by the flight view and
## the shipyard preview so both show the same ship. Geometry is visual only;
## simulation truth stays in the blueprint and ShipStats.
##
## Look: gunmetal hull plating (a procedural panel texture, mapped
## triplanar so it needs no UVs), the ship's name stencilled on both flanks,
## and docking collars in high-visibility hazard stripes with a beacon so
## boarders can see where to dock.

const PLATE_SIZE_M := 12.0
const HULL_TONE := Color(0.86, 0.9, 0.9)

static var _plate_texture: ImageTexture
static var _hazard_texture: ImageTexture


class Model:
	var root: Node3D
	## Main-engine nozzle positions (body frame), for plumes.
	var engine_nozzles: Array[Vector3] = []
	## RCS blocks: {id, position, normal} (body frame), for thruster jets.
	var rcs_blocks: Array[Dictionary] = []
	## Docking collar beacons (for blinking).
	var beacons: Array[Node3D] = []
	## Blueprint id → node holding that module's / external system's meshes
	## (so views can hide destroyed parts and darken wrecked modules).
	var parts: Dictionary = {}


## `origin_m`: grid-metre point placed at the model origin (normally the
## centre of mass). `tint` multiplies every colour (e.g. to mark the enemy).
## `hull_name`: painted on both sides of the largest module ("" = none).
static func build(bp: ShipBlueprint, grid: ShipGrid, origin_m: Vector3, tint: Color = Color.WHITE, hull_name: String = "") -> Model:
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
		var part := _box(model.root, size_m - Vector3.ONE * 0.15, center, _hull_mat(mats, def.color * tint))
		model.parts[bp.modules[i].id] = part
	var flank := _best_flank(bp, grid)
	if hull_name != "" and flank >= 0:
		_paint_name(model.root, bp, grid, flank, origin_m, hull_name)
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or not def.is_external():
			continue
		var normal := Vector3(ShipGrid.FACE_NORMALS.get(bp.equipment[i].face, Vector3i.ZERO))
		var mount := grid.equipment_position_m(i) - origin_m
		var mat := _mat(mats, def.color * tint)
		var part := Node3D.new()
		part.name = bp.equipment[i].id
		model.root.add_child(part)
		model.parts[bp.equipment[i].id] = part
		match def.kind:
			EquipmentDefinition.Kind.MAIN_ENGINE:
				# Cylinder +Y is rotated to +Z (aft): top = aft end = wide mouth.
				var bell := _cylinder(part, 1.4, 0.7, 2.4, mount + normal * 1.2, mat)
				bell.rotation_degrees = Vector3(90, 0, 0)
				model.engine_nozzles.append(mount + normal * 2.4)
			EquipmentDefinition.Kind.RCS:
				_box(part, Vector3.ONE * 0.9, mount + normal * 0.45, mat)
				model.rcs_blocks.append({"id": bp.equipment[i].id, "position": mount + normal * 0.45, "normal": normal})
			EquipmentDefinition.Kind.CANNON:
				_box(part, Vector3(1.8, 0.9, 1.8), mount + normal * 0.45, mat)
				var barrel := _cylinder(part, 0.16, 0.16, 5.0, mount + normal * 0.6 + Vector3(0, 0, -2.5), mat)
				barrel.rotation_degrees = Vector3(90, 0, 0)
			EquipmentDefinition.Kind.RADIATOR:
				var fin := Vector3(0.12, 3.0, 2.8) if normal.y != 0.0 else Vector3(3.0, 0.12, 2.8)
				_box(part, fin, mount + normal * 1.5, mat)
			EquipmentDefinition.Kind.DOCKING_COLLAR:
				model.beacons.append(_collar(part, mount, normal))
	return model


## Hazard-striped collar ring around a dark hatch, and a blinking beacon.
static func _collar(part: Node3D, mount: Vector3, normal: Vector3) -> Node3D:
	var basis := _basis_y_along(normal)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_texture = _hazard()
	ring_mat.uv1_triplanar = true
	ring_mat.uv1_scale = Vector3.ONE * 0.8
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.75, 0.1)
	ring_mat.emission_energy_multiplier = 0.35
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.6
	ring.mesh = torus
	ring.material_override = ring_mat
	ring.transform = Transform3D(basis, mount + normal * 0.25)
	part.add_child(ring)
	var hatch_mat := StandardMaterial3D.new()
	hatch_mat.albedo_color = Color(0.08, 0.08, 0.09)
	var hatch := _cylinder(part, 1.0, 1.0, 0.2, Vector3.ZERO, hatch_mat)
	hatch.transform = Transform3D(basis, mount + normal * 0.12)
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.albedo_color = Color(1.0, 0.85, 0.2)
	var beacon := MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.35
	bulb.height = 0.7
	beacon.mesh = bulb
	beacon.material_override = beacon_mat
	beacon.position = mount + normal * 0.6 + basis.x * 1.9
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.2)
	light.light_energy = 2.0
	light.omni_range = 14.0
	beacon.add_child(light)
	part.add_child(beacon)
	return beacon


## The module whose port and starboard faces are most exposed (the name
## must not hide behind side pods): most exterior side cells on its less
## exposed flank.
static func _best_flank(bp: ShipBlueprint, grid: ShipGrid) -> int:
	var best := -1
	var best_exposed := 0
	for i in bp.modules.size():
		var def := grid.module_def(i)
		if def == null or not def.interior:
			continue
		var pos := bp.modules[i].position
		var sz := grid.module_size(i)
		var sides := [0, 0]
		for y in sz.y:
			for z in sz.z:
				if not grid.is_hull(Vector3i(pos.x - 1, pos.y + y, pos.z + z)):
					sides[0] += 1
				if not grid.is_hull(Vector3i(pos.x + sz.x, pos.y + y, pos.z + z)):
					sides[1] += 1
		var exposed: int = mini(sides[0], sides[1])
		if exposed > best_exposed:
			best_exposed = exposed
			best = i
	return best


## The ship's name stencilled on both flanks of a module.
static func _paint_name(root: Node3D, bp: ShipBlueprint, grid: ShipGrid, i: int, origin_m: Vector3, hull_name: String) -> void:
	var c := ShipGrid.CELL_SIZE_M
	var size_m := Vector3(grid.module_size(i)) * c
	var center := Vector3(bp.modules[i].position) * c + size_m * 0.5 - origin_m
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = hull_name.to_upper()
		label.font_size = 96
		label.outline_size = 12
		label.pixel_size = minf(size_m.z * 0.85 / maxf(hull_name.length(), 1) / 58.0, size_m.y * 0.32 / 96.0)
		label.modulate = Color(0.92, 0.94, 0.9, 0.9)
		label.outline_modulate = Color(0.05, 0.05, 0.05, 0.8)
		label.double_sided = false
		label.shaded = true
		# Face outward along ±X, reading nose-to-the-left on the port side
		# and nose-to-the-right on starboard.
		label.position = center + Vector3(side * (size_m.x * 0.5 - 0.05), size_m.y * 0.1, 0)
		label.rotation = Vector3(0, side * PI * 0.5, 0)
		root.add_child(label)


static func _basis_y_along(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := (Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).cross(y).normalized()
	return Basis(x, y, x.cross(y))


static func _hull_mat(cache: Dictionary, color: Color) -> StandardMaterial3D:
	var key := "hull%s" % color
	if not cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color * HULL_TONE
		mat.albedo_texture = _plates()
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE / PLATE_SIZE_M
		mat.metallic = 0.55
		mat.roughness = 0.6
		cache[key] = mat
	return cache[key]


## Hull plating: panels with dark seams, rivet lines, a few weathered
## plates and access hatches (seeded, so every run looks the same).
static func _plates() -> ImageTexture:
	if _plate_texture != null:
		return _plate_texture
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var panel := 64
	for py in n / panel:
		for px in n / panel:
			var shade := 0.82 + rng.randf() * 0.16
			for y in panel:
				for x in panel:
					var v := shade + rng.randf_range(-0.015, 0.015)
					img.set_pixel(px * panel + x, py * panel + y, Color(v, v, v))
			# Seams.
			for k in panel:
				img.set_pixel(px * panel + k, py * panel, Color(0.35, 0.35, 0.36))
				img.set_pixel(px * panel, py * panel + k, Color(0.35, 0.35, 0.36))
			# Rivets along the seams.
			for k in range(4, panel, 8):
				img.set_pixel(px * panel + k, py * panel + 3, Color(0.55, 0.55, 0.56))
				img.set_pixel(px * panel + 3, py * panel + k, Color(0.55, 0.55, 0.56))
			# The odd access hatch.
			if rng.randf() < 0.25:
				var hx := px * panel + 16
				var hy := py * panel + 20
				for k in 24:
					for e in [0, 15]:
						img.set_pixel(hx + k, hy + e, Color(0.4, 0.4, 0.42))
					if k < 16:
						img.set_pixel(hx, hy + k, Color(0.4, 0.4, 0.42))
						img.set_pixel(hx + 23, hy + k, Color(0.4, 0.4, 0.42))
	img.generate_mipmaps()
	_plate_texture = ImageTexture.create_from_image(img)
	return _plate_texture


## Yellow and black diagonal hazard stripes.
static func _hazard() -> ImageTexture:
	if _hazard_texture != null:
		return _hazard_texture
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color(0.95, 0.75, 0.1) if ((x + y) / 16) % 2 == 0 else Color(0.06, 0.06, 0.06))
	img.generate_mipmaps()
	_hazard_texture = ImageTexture.create_from_image(img)
	return _hazard_texture


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
