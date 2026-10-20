class_name ReactorExplosion
extends Node3D
## A reactor containment failure, seen from outside: a white-hot core flash
## and light; a lumpy fireball that cools from yellow to deep red as it
## swells to the blast radius; two shockwave rings racing out; glowing
## debris flung clear on their own trajectories (they leave the ship
## behind); and a dim plasma glow that lingers where the reactor was.
## Purely visual: the damage is ShipSystems' (REACTOR_BLAST_RADIUS_M).
##
## `nuclear`: a nuclear warhead instead — a blinding white flash, a fireball
## swelling to the warhead's effect radius over seconds, three shockwave
## rings and a shock shell racing out to ~4 × the radius, and a violet
## ionisation afterglow; everything bigger, brighter and longer.
##
## The fireball, rings and glow ride with the ship (a point in its body
## frame); the debris lives in the world (continuous coordinates, so frame
## rebases don't move it).

const LIFETIME_S := 4.5
const FLASH_S := 0.45
const FIREBALL_S := 1.8
const RING_S := 0.7
const DEBRIS_S := 4.0
const LOBES := 7
const DEBRIS := 26
## The nuclear profile (setup(..., true)).
const NUKE_LIFETIME_S := 8.0
const NUKE_FLASH_S := 0.6
const NUKE_FIREBALL_S := 3.2
const NUKE_RING_S := 1.6
const NUKE_LOBES := 14

var nuclear := false
var _lifetime := LIFETIME_S
var _flash_s := FLASH_S
var _fireball_s := FIREBALL_S
var _ring_s := RING_S
var _ring_reach := 4.0
var _fire_scale := 2.6
var _light_peak := 16.0
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D

var ship_id: StringName
var point_body: Vector3
var radius: float = 15.0
var age: float = 0.0

var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _lobes: Array[Dictionary] = []   # {node, mat, offset, delay}
var _rings: Array[Dictionary] = []   # {node, mat}
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _debris: Array[Dictionary] = []  # {node, mat, start: Vec3d, velocity, spin}
var _debris_root: Node3D
var _spawned := false


## `seed_value` makes the shape repeatable (same reactor, same blast).
func setup(p_ship_id: StringName, p_point_body: Vector3, p_radius: float, seed_value: int, p_nuclear: bool = false) -> void:
	ship_id = p_ship_id
	point_body = p_point_body
	radius = p_radius
	nuclear = p_nuclear
	if nuclear:
		_lifetime = NUKE_LIFETIME_S
		_flash_s = NUKE_FLASH_S
		_fireball_s = NUKE_FIREBALL_S
		_ring_s = NUKE_RING_S
		_fire_scale = 2.2
		_light_peak = 60.0
		_ring_reach = 10.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_core_mat = _additive(Color(1.0, 0.97, 0.9))
	_core = _sphere(self, radius * (0.4 if nuclear else 0.25), _core_mat)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.light_energy = _light_peak
	_light.omni_range = radius * (25.0 if nuclear else 10.0)
	add_child(_light)
	for i in (NUKE_LOBES if nuclear else LOBES):
		var mat := _additive(Color(1.0, 0.8, 0.35))
		var offset := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0) * radius * 0.35
		var node := _sphere(self, radius * rng.randf_range(0.35, 0.55), mat)
		node.visible = false
		_lobes.append({"node": node, "mat": mat, "offset": offset, "delay": rng.randf_range(0.0, 0.25)})
	var ring_axes: Array[Vector3] = [Vector3(rng.randf(), 1.0, rng.randf()).normalized(), Vector3(1.0, rng.randf() * 0.3, rng.randf()).normalized()]
	if nuclear:
		ring_axes.append(Vector3(rng.randf() * 0.3, rng.randf() * 0.3, 1.0).normalized())
		# The shock front itself: a faint shell racing out with the rings.
		_shell_mat = _additive(Color(0.8, 0.9, 1.0, 0.0))
		_shell = _sphere(self, 1.0, _shell_mat)
	for axis in ring_axes:
		var mat := _additive(Color(0.75, 0.88, 1.0))
		var torus := TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 6
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.basis = _basis_y_along(axis)
		add_child(ring)
		_rings.append({"node": ring, "mat": mat})
	# Afterglow: a reactor's plasma glows red; a nuclear burst leaves a
	# violet cloud of ionised gas.
	_glow_mat = _additive(Color(0.55, 0.3, 1.0, 0.0) if nuclear else Color(0.9, 0.25, 0.08, 0.0))
	_glow = _sphere(self, radius * (0.9 if nuclear else 0.4), _glow_mat)
	_debris_root = Node3D.new()
	_debris_root.top_level = true
	add_child(_debris_root)
	for i in DEBRIS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.18, 0.16)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.55, 0.15)
		mat.emission_energy_multiplier = 3.0
		var box := BoxMesh.new()
		var s := rng.randf_range(0.25, 1.1)
		box.size = Vector3(s, s * rng.randf_range(0.2, 0.8), s * rng.randf_range(0.4, 1.4))
		var node := MeshInstance3D.new()
		node.mesh = box
		node.material_override = mat
		_debris_root.add_child(node)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		dir = dir.normalized() if dir.length() > 0.05 else Vector3.UP
		_debris.append({"node": node, "mat": mat, "dir": dir, "speed": rng.randf_range(12.0, 48.0),
			"spin": Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))})


func finished() -> bool:
	return age >= _lifetime


## Advance by `delta` and place everything (render space). False once the
## ship is gone from the world: the debris still flies, the rest is gone.
func step(world: WorldSimulation, alpha: float, render_origin: Vector3, delta: float) -> void:
	age += delta
	var ship := world.get_ship(ship_id)
	if ship != null:
		position = ship.interpolated_position(alpha) - render_origin + ship.interpolated_orientation(alpha) * point_body
		if not _spawned:
			# Debris starts at the reactor with the ship's own velocity plus its kick.
			var start := world.continuous_position(ship.interpolated_position(alpha) + ship.interpolated_orientation(alpha) * point_body)
			for d in _debris:
				d["start"] = start
				d["velocity"] = ship.velocity + ship.orientation * (d.dir as Vector3) * float(d.speed)
			_spawned = true
	_animate_core()
	_animate_fireball()
	_animate_rings()
	_animate_shell()
	_animate_glow()
	if _spawned:
		var origin := world.continuous_position(render_origin)
		for d in _debris:
			var node: MeshInstance3D = d.node
			var p: Vec3d = (d.start as Vec3d).plus_v3((d.velocity as Vector3) * age)
			node.position = p.minus(origin).to_vector3()
			node.rotation = (d.spin as Vector3) * age
			var cool := clampf(age / DEBRIS_S, 0.0, 1.0)
			(d.mat as StandardMaterial3D).emission_energy_multiplier = 3.0 * (1.0 - cool) * (1.0 - cool)
			node.visible = age < DEBRIS_S


func _animate_core() -> void:
	var k := clampf(age / _flash_s, 0.0, 1.0)
	_core.scale = Vector3.ONE * lerpf(1.0, 4.0, sqrt(k))
	_core_mat.albedo_color.a = (1.0 - k) * (1.0 - k)
	_core.visible = k < 1.0
	# Light: a sharp flash, then the fireball's dimmer glow fading out.
	var flash := _light_peak * (1.0 - k)
	var fire := _light_peak * 0.375 * clampf(1.0 - age / _fireball_s, 0.0, 1.0)
	_light.light_energy = maxf(flash, fire)
	_light.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.45, 0.15), clampf(age / _fireball_s, 0.0, 1.0))


func _animate_fireball() -> void:
	for lobe in _lobes:
		var t := age - float(lobe.delay)
		var node: MeshInstance3D = lobe.node
		if t < 0.0 or t > _fireball_s:
			node.visible = false
			continue
		node.visible = true
		var k := t / _fireball_s
		node.position = (lobe.offset as Vector3) * lerpf(0.5, 2.2, sqrt(k))
		node.scale = Vector3.ONE * lerpf(0.6, _fire_scale, sqrt(k))
		# Yellow-white → orange → deep red, thinning out.
		var c := Color(1.0, 0.85, 0.4).lerp(Color(1.0, 0.4, 0.1), clampf(k * 1.6, 0.0, 1.0)).lerp(Color(0.6, 0.08, 0.04), clampf(k * 1.6 - 0.6, 0.0, 1.0))
		c.a = 0.85 * (1.0 - k) * (1.0 - 0.5 * k)
		(lobe.mat as StandardMaterial3D).albedo_color = c


func _animate_rings() -> void:
	for r in _rings:
		var node: MeshInstance3D = r.node
		var k := clampf(age / _ring_s, 0.0, 1.0)
		node.visible = k < 1.0
		var s := radius * lerpf(0.3, _ring_reach, sqrt(k))
		node.scale = Vector3(s, s * 0.6, s)
		(r.mat as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - k)


func _animate_shell() -> void:
	if _shell == null:
		return
	var k := clampf(age / _ring_s, 0.0, 1.0)
	_shell.visible = k < 1.0
	_shell.scale = Vector3.ONE * radius * lerpf(0.4, _ring_reach, sqrt(k))
	_shell_mat.albedo_color.a = 0.12 * (1.0 - k)


func _animate_glow() -> void:
	# Fades in as the fireball fades, then slowly out.
	var start := _fireball_s * 0.33
	var a := clampf((age - start) / 0.8, 0.0, 1.0) * clampf((_lifetime - age) / (_lifetime * 0.45), 0.0, 1.0)
	_glow_mat.albedo_color.a = 0.45 * a
	_glow.scale = Vector3.ONE * (1.0 + 0.15 * sin(age * 9.0))


static func _additive(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


static func _sphere(parent: Node3D, r: float, mat: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


static func _basis_y_along(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := (Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).cross(y).normalized()
	return Basis(x, y, x.cross(y))
