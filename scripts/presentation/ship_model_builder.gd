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
	## Gun turrets: {id, pivot} — views point each pivot's −Z along its barrel.
	var turrets: Array[Dictionary] = []
	## Craft shown docked on their external racks, by rack id.
	var docked_craft: Dictionary = {}


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
		var part: MeshInstance3D
		if def.is_wedge():
			part = _wedge(model.root, def, bp.modules[i], center, _hull_mat(mats, def.color * tint))
		else:
			part = _box(model.root, size_m - Vector3.ONE * 0.15, center, _hull_mat(mats, def.color * tint))
		model.parts[bp.modules[i].id] = part
	_add_plates(model, bp, grid, origin_m, mats, tint)
	var flank := _best_flank(bp, grid)
	if hull_name != "" and not flank.is_empty():
		_paint_name(model.root, flank, origin_m, hull_name)
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null:
			continue
		if not def.is_external():
			if def.kind == EquipmentDefinition.Kind.CRAFT_MOUNT:
				_hangar_door(model, bp, grid, i, origin_m, mats, tint)
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
				# Ring base on the hull; the turret (house and barrel) trains on
				# a pivot one turret height off the face (WorldSimulation).
				var ring := _cylinder(part, 1.1, 1.2, 0.4, mount + normal * 0.2, mat)
				ring.transform.basis = _basis_y_along(normal)
				var pivot := Node3D.new()
				pivot.name = "TurretPivot"
				pivot.position = mount + normal * WorldSimulation.TURRET_HEIGHT_M
				part.add_child(pivot)
				var house_mat := _mat(mats, (def.color * tint).darkened(0.25))
				_box(pivot, Vector3(1.7, 0.9, 1.9), Vector3(0, 0, 0.2), house_mat)
				var barrel := _cylinder(pivot, 0.16, 0.2, 5.0, Vector3(0, 0, -2.6), mat)
				barrel.rotation_degrees = Vector3(90, 0, 0)
				model.turrets.append({"id": bp.equipment[i].id, "pivot": pivot})
			EquipmentDefinition.Kind.RADIATOR:
				# A fin standing off the face, as long as the cells it spans.
				var cells := grid.external_cells(i)
				var along := Vector3(cells[1] - cells[0]).abs() if cells.size() > 1 else Vector3(0, 0, 1)
				var long_m := cells.size() * c - 0.2
				# Long along the span, 3 m off the face, thin across.
				var fin := Vector3.ONE * 0.12
				for axis in 3:
					if along[axis] > 0.5:
						fin[axis] = long_m
					elif absf(normal[axis]) > 0.5:
						fin[axis] = 3.0
				_box(part, fin, mount + normal * 1.5, mat)
				_box(part, Vector3.ONE * 0.5 + along * (long_m - 0.5), mount + normal * 0.15, _mat(mats, Color(0.3, 0.32, 0.35) * tint))
			EquipmentDefinition.Kind.DOCKING_COLLAR:
				model.beacons.append(_collar(part, mount, normal))
			EquipmentDefinition.Kind.POINT_DEFENCE:
				# A small dome with twin barrels on a pivot.
				var dome := _cylinder(part, 0.6, 0.75, 0.5, Vector3.ZERO, mat)
				dome.transform = Transform3D(_basis_y_along(normal), mount + normal * 0.25)
				var pd_pivot := Node3D.new()
				pd_pivot.name = "PdPivot"
				pd_pivot.position = mount + normal * 0.6
				part.add_child(pd_pivot)
				for side in [-0.18, 0.18]:
					var tube := _cylinder(pd_pivot, 0.06, 0.07, 1.8, Vector3(side, 0, -0.9), mat)
					tube.rotation_degrees = Vector3(90, 0, 0)
				model.turrets.append({"id": bp.equipment[i].id, "pivot": pd_pivot, "pd": true})
			EquipmentDefinition.Kind.SENSOR:
				_sensor_mast(part, mount, normal, mat, _mat(mats, Color(0.22, 0.24, 0.27) * tint))
			EquipmentDefinition.Kind.CRAFT_MOUNT:
				# A cradle on the hull; the docked craft sits in it (views hide it
				# while the craft is out).
				_box(part, Vector3(2.4, 0.3, 2.4), mount + normal * 0.15, _mat(mats, Color(0.25, 0.27, 0.3) * tint))
				var craft := Node3D.new()
				craft.name = "DockedCraft"
				part.add_child(craft)
				craft.transform = Transform3D(_basis_y_along(normal), mount + normal * 0.9)
				CraftView.build_model(craft, def.craft, def.craft.cannon != null, false)
				model.docked_craft[bp.equipment[i].id] = craft
	return model


## Sensor mast: a lattice pole with a dish and a sensor head on top.
static func _sensor_mast(part: Node3D, mount: Vector3, normal: Vector3, mat: Material, dark: Material) -> void:
	var b := _basis_y_along(normal)
	var pole := _cylinder(part, 0.18, 0.28, 4.0, Vector3.ZERO, dark)
	pole.transform = Transform3D(b, mount + normal * 2.0)
	var head := _box(part, Vector3(1.0, 0.6, 1.0), Vector3.ZERO, mat)
	head.transform = Transform3D(b, mount + normal * 4.2)
	var dish := _cylinder(part, 1.3, 0.4, 0.35, Vector3.ZERO, mat)
	# Tilted dish beside the head.
	dish.transform = Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(55)), mount + normal * 3.5 + b.z * 0.9)
	for k in 3:
		var arm := _box(part, Vector3(0.08, 0.08, 1.6), Vector3.ZERO, dark)
		arm.transform = Transform3D(b * Basis(Vector3.UP, TAU * k / 3.0), mount + normal * (1.0 + k * 0.9))


## An internal craft bay's hangar door: a framed dark panel on the room's
## open face where its craft come and go.
static func _hangar_door(model: Model, bp: ShipBlueprint, grid: ShipGrid, i: int, origin_m: Vector3, mats: Dictionary, tint: Color) -> void:
	var e := bp.equipment[i]
	var cells: Array = grid.equipment_cells(i)
	for face: StringName in [&"ventral", &"port", &"starboard", &"dorsal", &"aft", &"fore"]:
		for cell: Vector3i in cells:
			if not grid.is_exterior_face(cell, face):
				continue
			var n := Vector3(ShipGrid.FACE_NORMALS[face])
			var part := Node3D.new()
			part.name = e.id
			model.root.add_child(part)
			model.parts[e.id] = part
			var pos := ShipGrid.cell_center_m(cell) + n * ShipGrid.CELL_SIZE_M * 0.5 - origin_m
			var b := _basis_y_along(n)
			var frame := _box(part, Vector3(2.8, 0.1, 2.8), Vector3.ZERO, _mat(mats, Color(0.95, 0.75, 0.15) * tint))
			frame.transform = Transform3D(b, pos + n * 0.05)
			var door := _box(part, Vector3(2.4, 0.12, 2.4), Vector3.ZERO, _mat(mats, Color(0.06, 0.07, 0.08)))
			door.transform = Transform3D(b, pos + n * 0.08)
			return


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


## A wedge: a triangular prism, slope rising towards its own aft end (down
## when flipped), turned with the module.
static func _wedge(parent: Node3D, def: HullModuleDefinition, m: ShipBlueprint.PlacedModule, center: Vector3, mat: Material) -> MeshInstance3D:
	var c := ShipGrid.CELL_SIZE_M
	var s := Vector3(def.size_cells) * c - Vector3.ONE * 0.15
	var prism := PrismMesh.new()
	# Prism: triangle in its X–Y plane (apex over +X with left_to_right = 1),
	# extruded along Z. Its X runs aft, Y up, Z to port.
	prism.size = Vector3(s.z, s.y, s.x)
	prism.left_to_right = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = prism
	mi.material_override = mat
	var b := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	if m.flip:
		b = Basis(Vector3.BACK, PI) * b
	mi.transform = Transform3D(Basis(Vector3.UP, m.rotation * PI * 0.5) * b, center)
	parent.add_child(mi)
	return mi


## Armour plates as raised panels on their faces: slate for 40 mm, darker
## and thicker for 80 mm; slope plates lie on the slope.
static func _add_plates(model: Model, bp: ShipBlueprint, grid: ShipGrid, origin_m: Vector3, mats: Dictionary, tint: Color) -> void:
	if bp.armor.is_empty():
		return
	var c := ShipGrid.CELL_SIZE_M
	var holder := Node3D.new()
	holder.name = "Armour"
	model.root.add_child(holder)
	model.parts["armour"] = holder
	var thin := _hull_mat(mats, Color(0.5, 0.53, 0.58) * tint)
	var thick := _hull_mat(mats, Color(0.36, 0.38, 0.42) * tint)
	for key: String in bp.armor:
		var cf := ShipBlueprint.parse_plate_key(key)
		var cell: Vector3i = cf[0]
		var face: StringName = cf[1]
		if not grid.is_hull(cell):
			continue
		var mm := int(bp.armor[key])
		var depth := 0.35 if mm >= ShipBlueprint.PLATE_THICK_MM else 0.2
		var mat := thick if mm >= ShipBlueprint.PLATE_THICK_MM else thin
		var cell_center := ShipGrid.cell_center_m(cell) - origin_m
		if grid.is_wedge_cell(cell) and grid.slope_faces(cell).has(face):
			var n := grid.wedge_normal(grid.module_at[cell])
			var basis := _basis_y_along(n)
			var plate := _box(holder, Vector3(c * 0.96, depth, c * 0.96 * grid.plate_area_factor(cell, face)), cell_center + n * depth * 0.5, mat)
			# Square the plate to the slope: its long side runs up the slope.
			var up_slope := (Vector3(ShipGrid.FACE_NORMALS[grid.slope_faces(cell)[0]]) * -1.0).slide(n).normalized()
			plate.transform.basis = Basis(up_slope.cross(n), n, up_slope).orthonormalized() if up_slope.length() > 0.1 else basis
			continue
		var fn := Vector3(ShipGrid.FACE_NORMALS[face])
		var size := Vector3(c * 0.96, c * 0.96, c * 0.96)
		for axis in 3:
			if fn[axis] != 0.0:
				size[axis] = depth
		_box(holder, size, cell_center + fn * (c * 0.5 + depth * 0.5), mat)


## Where to paint the name: the longest straight run of exposed side faces
## along the hull (same deck, same side), on both flanks. {} if none.
static func _best_flank(bp: ShipBlueprint, grid: ShipGrid) -> Dictionary:
	var best := {}
	var best_len := 0
	var b := grid.cell_bounds()
	for y in range(int(b.position.y), int(b.end.y)):
		for side in [&"port", &"starboard"]:
			var runs := {}  # x -> [start z, length] of the current run
			for z in range(int(b.position.z), int(b.end.z) + 1):
				for x in range(int(b.position.x), int(b.end.x)):
					var cell := Vector3i(x, y, z)
					var exposed := grid.is_hull(cell) and grid.is_interior(cell) and grid.is_exterior_face(cell, side)
					var run: Array = runs.get(x, [z, 0])
					if exposed:
						if run[1] == 0:
							run[0] = z
						run[1] += 1
						runs[x] = run
						if run[1] > best_len:
							best_len = run[1]
							best = {"x": x, "y": y, "z0": run[0], "len": run[1], "side": side}
					else:
						runs[x] = [z, 0]
	return best


## The ship's name stencilled along a flank run, mirrored on the far side.
static func _paint_name(root: Node3D, flank: Dictionary, origin_m: Vector3, hull_name: String) -> void:
	var c := ShipGrid.CELL_SIZE_M
	var length: float = flank.len * c
	var x_port: float = flank.x * c if flank.side == &"port" else (flank.x + 1) * c
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = hull_name.to_upper()
		label.font_size = 96
		label.outline_size = 12
		label.pixel_size = minf(length * 0.85 / maxf(hull_name.length(), 1) / 58.0, c * 0.32 / 96.0)
		label.modulate = Color(0.92, 0.94, 0.9, 0.9)
		label.outline_modulate = Color(0.05, 0.05, 0.05, 0.8)
		label.double_sided = false
		label.shaded = true
		# The run's own flank, and the mirror image of it on the other side
		# of the centreline. Face outward along ±X, reading nose-to-the-left
		# on the port side and nose-to-the-right on starboard.
		var x := x_port if (side < 0.0) == (flank.side == &"port") else -x_port + 2.0 * origin_m.x
		var plate_off := 0.4
		label.position = Vector3(x - origin_m.x + side * plate_off, (flank.y + 0.55) * c - origin_m.y, (flank.z0 + flank.len * 0.5) * c - origin_m.z)
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
