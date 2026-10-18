class_name HitFlashes
extends Node3D
## Short impact flashes. Each is stored as a point in the struck ship's body
## frame, so it rides along with the ship and is unaffected by frame rebases.

const LIFETIME_S := 0.6

var _flashes: Array[Dictionary] = []  # {ship_id, point_body, age, node, material}


func add(ev: HitEvent) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.55, 1.0)
	var sphere := SphereMesh.new()
	sphere.radius = 1.5
	sphere.height = 3.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_flashes.append({"ship_id": ev.target_id, "point_body": ev.point_body, "age": 0.0, "node": node, "material": mat})


func clear() -> void:
	for f in _flashes:
		(f.node as Node).queue_free()
	_flashes.clear()


func update(world: WorldSimulation, alpha: float, render_origin: Vector3, delta: float) -> void:
	var alive: Array[Dictionary] = []
	for f in _flashes:
		f.age += delta
		var ship := world.get_ship(f.ship_id)
		var node: MeshInstance3D = f.node
		if ship == null or f.age >= LIFETIME_S:
			node.queue_free()
			continue
		var k: float = f.age / LIFETIME_S
		node.position = ship.interpolated_position(alpha) - render_origin \
			+ ship.interpolated_orientation(alpha) * (f.point_body as Vector3)
		node.scale = Vector3.ONE * lerpf(1.0, 5.0, k)
		(f.material as StandardMaterial3D).albedo_color.a = 1.0 - k
		alive.append(f)
	_flashes = alive
