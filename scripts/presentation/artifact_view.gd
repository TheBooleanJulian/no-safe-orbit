class_name ArtifactView
extends Node3D
## A real object in space (Artifact): a simple procedural model at its real
## size, by kind — a station's truss, modules and solar wings; Hubble's tube
## and two wings; a probe's dish, bus and booms; an orbiter's foil-wrapped
## bus, panel and dish; the Roadster with Starman. Read-only, like ShipView.

var artifact: Artifact

const FOIL := Color(0.78, 0.62, 0.3)
const WHITE := Color(0.86, 0.87, 0.88)
const SILVER := Color(0.7, 0.72, 0.75)
const PANEL := Color(0.13, 0.16, 0.3)
const DARK := Color(0.12, 0.12, 0.13)


func _ready() -> void:
	var s := artifact.size_m
	match artifact.kind:
		&"station":
			_box(Vector3(s, 2.0, 2.0), Vector3.ZERO, WHITE)  # main truss
			for i in 5:
				_cyl(2.2, s * 0.08, Vector3(0, -2.5, (i - 2) * s * 0.07), WHITE, Vector3(90, 0, 0))
			for side in [-1.0, 1.0]:
				for j in 4:
					var x: float = side * s * (0.28 + 0.06 * j)
					_box(Vector3(s * 0.04, 0.1, s * 0.33), Vector3(x, 0, s * 0.18), PANEL)
					_box(Vector3(s * 0.04, 0.1, s * 0.33), Vector3(x, 0, -s * 0.18), PANEL)
		&"telescope":
			_cyl(s * 0.16, s, Vector3.ZERO, SILVER, Vector3(90, 0, 0))
			_cyl(s * 0.16, 0.3, Vector3(0, 0, -s * 0.5), DARK, Vector3(90, 0, 0))
			for side in [-1.0, 1.0]:
				_box(Vector3(s * 0.55, 0.05, s * 0.2), Vector3(side * s * 0.45, 0, s * 0.1), PANEL)
		&"orbiter":
			_box(Vector3(s * 0.3, s * 0.3, s * 0.35), Vector3.ZERO, FOIL)
			_box(Vector3(s * 0.7, 0.05, s * 0.3), Vector3(s * 0.5, 0, 0), PANEL)
			_cyl(s * 0.15, 0.2, Vector3(0, s * 0.25, 0), WHITE)
		&"car":
			_box(Vector3(1.75, 0.7, s), Vector3(0, 0.35, 0), Color(0.75, 0.05, 0.06))  # cherry red
			_box(Vector3(1.4, 0.45, s * 0.25), Vector3(0, 0.9, 0.1), DARK)  # cockpit
			_box(Vector3(0.4, 0.6, 0.35), Vector3(-0.35, 1.0, 0.25), WHITE)  # Starman
			for x in [-0.85, 0.85]:
				for z in [-1.25, 1.25]:
					_cyl(0.33, 0.25, Vector3(x, 0.05, z), DARK, Vector3(0, 0, 90))
		_:  # probe
			_cyl(s * 0.14, 0.35, Vector3(0, s * 0.06, 0), WHITE)  # high-gain dish
			_box(Vector3(s * 0.12, s * 0.06, s * 0.12), Vector3.ZERO, FOIL)  # bus
			_cyl(0.05, s * 0.6, Vector3(s * 0.3, 0, 0), SILVER, Vector3(0, 0, 90))  # boom
			_cyl(0.18, s * 0.1, Vector3(-s * 0.15, 0, 0), DARK, Vector3(0, 0, 90))  # RTG
	var label := Label3D.new()
	label.text = artifact.display_name.to_upper()
	label.pixel_size = 0.03
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = CyberTheme.AMBER
	label.position = Vector3(0, s * 0.5 + 3.0, 0)
	add_child(label)


func sync_from(state: ShipState, alpha: float, render_origin: Vector3) -> void:
	position = state.interpolated_position(alpha) - render_origin
	quaternion = state.interpolated_orientation(alpha)


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.6 if c == FOIL or c == SILVER else 0.1
	m.roughness = 0.35
	return m


func _box(size: Vector3, pos: Vector3, c: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(mesh, pos, c, Vector3.ZERO)


func _cyl(radius: float, height: float, pos: Vector3, c: Color, rot_deg := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add(mesh, pos, c, rot_deg)


func _add(mesh: PrimitiveMesh, pos: Vector3, c: Color, rot_deg: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(c)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
