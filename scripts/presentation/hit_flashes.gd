class_name HitFlashes
extends Node3D
## Short impact flashes and reactor explosions. Each is stored as a point in
## the struck ship's body frame, so it rides along with the ship and is
## unaffected by frame rebases.

const LIFETIME_S := 0.6
const EXPLOSION_LIFETIME_S := 2.5

var _flashes: Array[Dictionary] = []  # {ship_id, point_body, age, life, grow, node, material, light}
var _explosions: Array[ReactorExplosion] = []


func add(ev: HitEvent) -> void:
	_add(ev.target_id, ev.point_body, 1.5, 5.0, LIFETIME_S, Color(1.0, 0.85, 0.55, 1.0), false)


## Reactor containment failure: flash, fireball, shockwaves, debris, glow.
## `nuclear`: the warhead's profile (bigger, brighter, longer; ReactorExplosion).
func add_explosion(ship_id: StringName, point_body: Vector3, radius: float, nuclear: bool = false) -> ReactorExplosion:
	var boom := ReactorExplosion.new()
	add_child(boom)
	boom.setup(ship_id, point_body, radius, hash(String(ship_id)) + int(point_body.x * 31.0 + point_body.z * 17.0), nuclear)
	_explosions.append(boom)
	return boom


func explosion_count() -> int:
	return _explosions.size()


## A small fireball (a missile breaking up, a small warhead): an orange
## flash growing to about 3 × `radius`, lit, gone in under a second.
func add_fireball(ship_id: StringName, point_body: Vector3, radius: float) -> void:
	_add(ship_id, point_body, radius, 3.0, 0.8, Color(1.0, 0.62, 0.3, 1.0), true)


## A ring of light expanding to `radius` (an EMP burst), riding on a ship.
func add_burst(ship_id: StringName, point_body: Vector3, radius: float, color: Color) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 0.085
	ring.outer_radius = radius * 0.1
	ring.rings = 48
	_add(ship_id, point_body, radius * 0.1, 10.0, 1.2, color, true, ring)


func _add(ship_id: StringName, point_body: Vector3, radius: float, grow: float, life: float, color: Color, light: bool,
		mesh: Mesh = null) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	if mesh == null:
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		sphere.radial_segments = 16
		sphere.rings = 8
		mesh = sphere
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var lamp: OmniLight3D
	if light:
		lamp = OmniLight3D.new()
		lamp.light_color = color
		lamp.light_energy = 8.0
		lamp.omni_range = radius * 12.0
		node.add_child(lamp)
	_flashes.append({"ship_id": ship_id, "point_body": point_body, "age": 0.0, "life": life, "grow": grow,
		"node": node, "material": mat, "light": lamp})


func clear() -> void:
	for f in _flashes:
		(f.node as Node).queue_free()
	_flashes.clear()
	for e in _explosions:
		e.queue_free()
	_explosions.clear()


func update(world: WorldSimulation, alpha: float, render_origin: Vector3, delta: float) -> void:
	var booming: Array[ReactorExplosion] = []
	for e in _explosions:
		e.step(world, alpha, render_origin, delta)
		if e.finished():
			e.queue_free()
		else:
			booming.append(e)
	_explosions = booming
	var alive: Array[Dictionary] = []
	for f in _flashes:
		f.age += delta
		var ship := world.get_ship(f.ship_id)
		var node: MeshInstance3D = f.node
		if ship == null or f.age >= f.life:
			node.queue_free()
			continue
		var k: float = f.age / f.life
		node.position = ship.interpolated_position(alpha) - render_origin \
			+ ship.interpolated_orientation(alpha) * (f.point_body as Vector3)
		node.scale = Vector3.ONE * lerpf(1.0, f.grow, sqrt(k))
		(f.material as StandardMaterial3D).albedo_color.a = 1.0 - k
		if f.light != null:
			(f.light as OmniLight3D).light_energy = 8.0 * (1.0 - k)
		alive.append(f)
	_flashes = alive
