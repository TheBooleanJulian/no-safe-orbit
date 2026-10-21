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
## Painted on the hull's flanks.
var hull_name: String = ""

var _plumes: Array[Node3D] = []
var _plume_material: StandardMaterial3D
var _parts: Dictionary = {}
var _missile_cones: Dictionary = {}  # launcher id -> Array[Node3D]
var _arms: Dictionary = {}  # grappling arm id -> ShipModelBuilder arm
## What each arm holds: arm id -> the point it grips (body frame); Main sets
## it every frame (empty: folded). How far out each arm is (0 folded, 1 out).
var grapple_holds: Dictionary = {}
var _arm_out: Dictionary = {}
## Seconds an arm takes to unfold onto its target, or to fold back.
const ARM_UNFOLD_S := 1.8
var _cones_shown: Dictionary = {}  # launcher id -> how many are shown
var _wreck_material: StandardMaterial3D
var _jets: Array[Dictionary] = []  # {pivot, id, position, normal}
var _jet_material: StandardMaterial3D
var _beacons: Array[Node3D] = []
var _clock := 0.0

## Jets shorter than this fraction of full thrust are not drawn.
const JET_MIN_FRACTION := 0.04
const JET_LENGTH_M := 4.0
const BEACON_PERIOD_S := 1.2
## Shell holes kept on the hull (oldest go first).
const MAX_HOLES := 80
const ENTRY_HOLE_RADIUS_M := 0.55
const EXIT_HOLE_RADIUS_M := 0.9

var _holes: Array[Node3D] = []
## Gun turrets {id, pivot}, trained from the ship's turret directions.
var _turrets: Array[Dictionary] = []
## Craft drawn sitting on their external racks, by rack id.
var _docked_craft: Dictionary = {}


## Show or hide the craft sitting on rack `rack_id` (Main: hidden while out).
func show_docked_craft(rack_id: String, docked: bool) -> void:
	var node: Node3D = _docked_craft.get(rack_id)
	if node != null:
		node.visible = docked
var _hole_material: StandardMaterial3D
var _scorch_material: StandardMaterial3D


func _ready() -> void:
	var model := ShipModelBuilder.build(blueprint, grid, stats.center_of_mass_m, tint, hull_name)
	add_child(model.root)
	_parts = model.parts
	_missile_cones = model.missile_cones
	_arms = model.grapple_arms
	_beacons = model.beacons
	_turrets = model.turrets
	_docked_craft = model.docked_craft
	_build_plumes(model.engine_nozzles, model.engine_normals)
	_plates = model.plates
	_bake_hull(model)
	_spinners = model.spinners
	_windows = model.windows
	_nav_lights = model.nav_lights
	_build_jets(model.rcs_blocks)
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
	for k in _plumes.size():
		# Each plume: how hard the ship is pushing away from its face.
		var n: Vector3 = _plume_normals[k]
		var f := fwd_fraction
		if n.z < 0.9:
			var axis := 0 if absf(n.x) > 0.5 else (1 if absf(n.y) > 0.5 else 2)
			var cap := state.config.max_thrust(axis, n[axis] < 0.0)
			f = clampf(state.last_thrust_body.dot(-n) / cap, 0.0, 1.0) if cap > 0.0 else 0.0
		_plumes[k].visible = f > 0.01
		_plumes[k].scale = Vector3(1.0, 1.0, lerpf(0.2, 1.0, f))
	_plume_material.albedo_color.a = 0.15 + 0.4 * fwd_fraction
	if state.systems != null:
		_show_damage(state.systems)
		_show_emp(state.systems, get_process_delta_time())
		_update_lights_and_radar(state.systems, get_process_delta_time())
	_update_spool(get_process_delta_time())
	_drift_pieces(get_process_delta_time())
	_train_turrets(state)
	_move_arms(get_process_delta_time())
	_update_jets(state)
	_clock += get_process_delta_time()
	var on := fmod(_clock, BEACON_PERIOD_S) < 0.25
	for b in _beacons:
		b.visible = on and b.get_parent().visible


## EMP (play-test batch 9): a part an EMP has reset crackles with light-blue
## static — jagged arcs redrawn EMP_REDRAW_S apart — until it recovers; with
## several parts down the static crawls over the hull too.
const EMP_ARCS_PER_PART := 3
const EMP_REDRAW_S := 0.07
const EMP_ARC_RADIUS_M := 2.4
const EMP_COLOR := Color(0.55, 0.85, 1.0, 0.9)
## Parts crackling now (ids), and the arcs drawn last.
var emp_sparking := PackedStringArray()
var emp_arcs := 0
var _emp_mesh: MeshInstance3D
var _emp_clock := 0.0
var _emp_rng := RandomNumberGenerator.new()


func _show_emp(systems: ShipSystems, delta: float) -> void:
	_emp_clock -= delta
	if _emp_clock > 0.0:
		return
	_emp_clock = EMP_REDRAW_S
	var points: Array[Vector3] = []
	emp_sparking = PackedStringArray()
	emp_arcs = 0
	for e in systems.equipment:
		if e.disrupted_s > 0.0 and not e.destroyed():
			emp_sparking.append(e.id)
			points.append(e.body_position)
	if points.is_empty():
		if _emp_mesh != null:
			_emp_mesh.visible = false
		return
	if _emp_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = EMP_COLOR
		_emp_mesh = MeshInstance3D.new()
		_emp_mesh.name = "EmpStatic"
		_emp_mesh.mesh = ImmediateMesh.new()
		_emp_mesh.material_override = mat
		_emp_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_emp_mesh)
	if points.size() >= 3:
		# Over the hull: points on its bounding box's faces.
		var b := stats.hull_bounds_m
		for k in points.size():
			var p := b.position + Vector3(_emp_rng.randf(), _emp_rng.randf(), _emp_rng.randf()) * b.size
			var axis := _emp_rng.randi() % 3
			p[axis] = b.position[axis] if _emp_rng.randf() < 0.5 else b.end[axis]
			points.append(p - stats.center_of_mass_m)
	var im := _emp_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in points:
		for k in EMP_ARCS_PER_PART:
			_emp_arc(im, p)
			emp_arcs += 1
	im.surface_end()
	_emp_mesh.visible = true


## One jagged arc near `centre`: five short kinked segments.
func _emp_arc(im: ImmediateMesh, centre: Vector3) -> void:
	var a := centre + _rand_dir() * EMP_ARC_RADIUS_M * 0.4
	var heading := _rand_dir()
	for k in 5:
		heading = (heading + _rand_dir() * 0.9).normalized()
		var b := a + heading * EMP_ARC_RADIUS_M * _emp_rng.randf_range(0.15, 0.3)
		# Two crossed ribbons, so it reads from any side.
		var dir := (b - a).normalized()
		var u := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized() * 0.11
		var v := dir.cross(u).normalized() * 0.11
		for side: Vector3 in [u, v]:
			for q: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
				im.surface_add_vertex(q)
		a = b


func _rand_dir() -> Vector3:
	var d := Vector3(_emp_rng.randf_range(-1, 1), _emp_rng.randf_range(-1, 1), _emp_rng.randf_range(-1, 1))
	return d.normalized() if d.length_squared() > 1e-4 else Vector3.UP


## Hold [B] (play-test batch 9): Main sets how far the jump drive has charged
## (0–1). Rings of light gather along the hull and spin up, closing in on
## its middle, brightening until it jumps.
var jump_spool := 0.0
const SPOOL_RINGS := 3
const SPOOL_COLOR := Color(0.55, 0.8, 1.0)
var _spool: Node3D
var _spool_rings: Array[Node3D] = []
var _spool_ring_z: Array[float] = []
var _spool_mat: StandardMaterial3D


func _update_spool(delta: float) -> void:
	if jump_spool <= 0.0:
		if _spool != null:
			_spool.visible = false
		return
	if _spool == null:
		_build_spool()
	_spool.visible = true
	var s := clampf(jump_spool, 0.0, 1.0)
	for k in _spool_rings.size():
		var ring := _spool_rings[k]
		ring.rotate_object_local(Vector3.UP, (1.0 + 12.0 * s * s) * delta * (1.0 if k % 2 == 0 else -1.0))
		ring.position.z = _spool_ring_z[k] * (1.0 - 0.7 * s)
		ring.scale = Vector3.ONE * lerpf(1.2, 0.9, s)
	_spool_mat.albedo_color.a = 0.2 + 0.6 * s


func _build_spool() -> void:
	var b := stats.hull_bounds_m
	var centre := b.get_center() - stats.center_of_mass_m
	var r := maxf(b.size.x, b.size.y) * 0.6 + 3.0
	_spool = Node3D.new()
	_spool.name = "JumpSpool"
	_spool.position = Vector3(centre.x, centre.y, 0.0)
	add_child(_spool)
	_spool_mat = StandardMaterial3D.new()
	_spool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spool_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spool_mat.albedo_color = SPOOL_COLOR
	var torus := TorusMesh.new()
	torus.inner_radius = r * 0.94
	torus.outer_radius = r
	torus.rings = 48
	for k in SPOOL_RINGS:
		var holder := Node3D.new()
		var z := centre.z + b.size.z * lerpf(-0.4, 0.4, float(k) / float(SPOOL_RINGS - 1))
		holder.position.z = z
		_spool.add_child(holder)
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = _spool_mat
		ring.rotation_degrees = Vector3(90, 0, 0)  # the torus's axis (+Y) along the ship's length
		holder.add_child(ring)
		_spool_rings.append(ring)
		_spool_ring_z.append(z)


## A black shell hole where a round pierced the hull (body frame point and
## outward normal); exit holes are wider and ragged-edged.
func add_hole(point_body: Vector3, normal_body: Vector3, exit_hole: bool) -> void:
	if normal_body.length_squared() < 0.5:
		return
	if _hole_material == null:
		_hole_material = StandardMaterial3D.new()
		_hole_material.albedo_color = Color(0.0, 0.0, 0.0)
		_hole_material.roughness = 1.0
		_scorch_material = StandardMaterial3D.new()
		_scorch_material.albedo_color = Color(0.09, 0.08, 0.07)
		_scorch_material.roughness = 1.0
	var n := normal_body.normalized()
	var x := (Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).cross(n).normalized()
	var basis := Basis(x, n, x.cross(n))
	var r := EXIT_HOLE_RADIUS_M if exit_hole else ENTRY_HOLE_RADIUS_M
	var hole := Node3D.new()
	hole.transform = Transform3D(basis, point_body + n * 0.02)
	add_child(hole)
	for layer in [[r * 1.7, 0.0, _scorch_material], [r, 0.02, _hole_material]]:
		var disc := CylinderMesh.new()
		disc.top_radius = layer[0]
		disc.bottom_radius = layer[0]
		disc.height = 0.02
		disc.radial_segments = 7 if exit_hole else 16  # exit: ragged
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = layer[2]
		mi.position = Vector3(0, layer[1], 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hole.add_child(mi)
	_holes.append(hole)
	if _holes.size() > MAX_HOLES:
		_holes.pop_front().queue_free()


func hole_count() -> int:
	return _holes.size()


## White conical RCS jets. Each block's share of the commanded thrust and
## torque gives the force it makes; the exhaust leaves along the opposite
## direction, snapped to the block's nearest outward axis.
func _build_jets(blocks: Array[Dictionary]) -> void:
	_jet_material = StandardMaterial3D.new()
	_jet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_jet_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_jet_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_jet_material.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.06   # far end
	cone.bottom_radius = 0.45  # nozzle
	cone.height = JET_LENGTH_M
	cone.cap_top = false
	cone.cap_bottom = false
	for b in blocks:
		var pivot := Node3D.new()
		pivot.visible = false
		add_child(pivot)
		var jet := MeshInstance3D.new()
		jet.mesh = cone
		jet.material_override = _jet_material
		jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		jet.position = Vector3(0, JET_LENGTH_M * 0.5, 0)
		pivot.add_child(jet)
		_jets.append({"pivot": pivot, "id": b.id, "position": b.position, "normal": b.normal})


func _update_jets(state: ShipState) -> void:
	var n := _jets.size()
	if n == 0:
		return
	var per_block := maxf(state.config.thrust_lateral_n / n, 1.0)
	var t := state.last_thrust_body
	t.z = maxf(t.z, 0.0)  # forward thrust is the main engines'
	var tau := state.last_torque_body / n
	for j in _jets:
		var pivot: Node3D = j.pivot
		var r: Vector3 = j.position
		var f := t / n
		if r.length_squared() > 1.0:
			f += tau.cross(r) / r.length_squared()
		var fraction := clampf(f.length() / per_block, 0.0, 1.0)
		# A destroyed block (its part hidden) fires nothing.
		pivot.visible = fraction > JET_MIN_FRACTION and (not _parts.has(j.id) or (_parts[j.id] as Node3D).visible)
		if not pivot.visible:
			continue
		var exhaust := _snap_exhaust(-f.normalized(), j.normal)
		var x := (Vector3.UP if absf(exhaust.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).cross(exhaust).normalized()
		pivot.transform = Transform3D(Basis(x, exhaust * lerpf(0.35, 1.0, fraction), x.cross(exhaust)), r + j.normal * 0.45)


## Nearest of the six body axes to `dir`, never pointing into the hull.
static func _snap_exhaust(dir: Vector3, normal: Vector3) -> Vector3:
	var best := normal
	var best_dot := -INF
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		if axis.dot(normal) < -0.5:
			continue
		var d: float = axis.dot(dir)
		if d > best_dot:
			best_dot = d
			best = axis
	return best



## Each turret's house and barrel point along its mount's barrel direction.
## Grappling arms: unfold and telescope out to the point each holds, or fold
## back along the hull (the joints ease between the two poses).
func _move_arms(delta: float) -> void:
	for id: String in _arms:
		var arm: Dictionary = _arms[id]
		var folded: Array = arm.folded
		var holding := grapple_holds.has(id)
		var was := float(_arm_out.get(id, 0.0))
		var out := clampf(was + (delta if holding else -delta) / ARM_UNFOLD_S, 0.0, 1.0)
		if is_equal_approx(out, was) and not holding:
			continue
		_arm_out[id] = out
		if holding:
			arm["target"] = grapple_holds[id]
		var p0: Vector3 = folded[0]
		var goal: Vector3 = arm.get("target", folded[3])
		var reach := minf(p0.distance_to(goal), Grapple.REACH_M)
		var dir := (goal - p0).normalized() if p0.distance_to(goal) > 1e-3 else (arm.normal as Vector3)
		var s := smoothstep(0.0, 1.0, out)
		var joints := []
		for k in 4:
			var straight := p0 + dir * reach * k / 3.0
			joints.append((folded[k] as Vector3).lerp(straight, s))
		ShipModelBuilder.place_arm(arm, joints)


func _train_turrets(state: ShipState) -> void:
	var ids := state.config.cannon_mount_ids
	for t in _turrets:
		var pd: bool = t.get("pd", false)
		var k := (state.config.pd_mount_ids if pd else ids).find(t.id)
		var dirs := state.pd_dirs if pd else state.turret_dirs
		if k < 0 or k >= dirs.size():
			continue
		var dir := dirs[k]
		var pivot: Node3D = t.pivot
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK
		pivot.basis = Basis.looking_at(dir, up)


## Radar turntables spin while their mast works; windows go dark when their
## room loses power, running lights when the ship has none (they blink).
func _update_lights_and_radar(systems: ShipSystems, delta: float) -> void:
	for s in _spinners:
		var e := systems.equipment_by_id(s.id)
		if e != null and e.working():
			(s.node as Node3D).rotate_object_local(Vector3.UP, RADAR_RPM / 60.0 * TAU * delta)
	_lights_check -= delta
	if _lights_check > 0.0:
		return
	_lights_check = 0.3
	for w in _windows:
		var room: int = w.room
		(w.node as Node3D).visible = room < systems.rooms.size() and systems.rooms[room].powered and systems.rooms[room].pressurized
	var on := systems.power_supply_kw > 0.0 and fmod(_clock, 1.6) < 1.2
	for n in _nav_lights:
		n.visible = on


## Worn armour darkens with scorching; a plate shot through (or on a wrecked
## module) is charred black and crumpled. Checked twice a second.
func _show_plate_wear(systems: ShipSystems) -> void:
	_wear_check -= get_process_delta_time()
	if _wear_check > 0.0 or _plates.is_empty():
		return
	_wear_check = 0.5
	for key: String in _plates:
		var full := float(systems.blueprint.armor.get(key, 0.0))
		if full <= 0.0:
			continue
		var left: float = systems.plates.get(key, full)
		var cf := ShipBlueprint.parse_plate_key(key)
		var mi: int = systems.grid.module_at.get(cf[0], -1)
		var dead := left <= 0.0 or (mi >= 0 and systems.modules[mi].wrecked())
		var level := 3 if dead else (2 if left < full * 0.5 else (1 if left < full * 0.9 else 0))
		if int(_plate_level.get(key, 0)) == level:
			continue
		_plate_level[key] = level
		_hull_dirty = true
		var node := _plates[key] as MeshInstance3D
		node.material_override = _char_material(level, node.material_override)
		if dead:
			# Buckled: squashed, twisted a little, sagging off the hull.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(key)
			node.basis = node.basis * Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.2, 0.2))) \
				* Basis.from_scale(Vector3(rng.randf_range(0.7, 0.9), rng.randf_range(0.5, 0.8), rng.randf_range(0.7, 0.9)))
			_hull_flats[node] = ShipModelBuilder.flat_arrays(node, _model_root)


func _char_material(level: int, current: Material) -> Material:
	if level == 0:
		return current
	if not _char_mats.has(level):
		var m := StandardMaterial3D.new()
		m.albedo_color = [Color.WHITE, Color(0.3, 0.29, 0.27), Color(0.17, 0.15, 0.13), Color(0.06, 0.05, 0.045)][level]
		m.roughness = 0.95
		m.metallic = 0.2
		_char_mats[level] = m
	return _char_mats[level]


## Destroyed external systems disappear; a wrecked module breaks up: its
## plating shears off in tumbling pieces that drift away from the hull,
## leaving a charred, dented frame at full size (its edges still meet the
## blocks around it).
func _show_damage(systems: ShipSystems) -> void:
	_show_plate_wear(systems)
	# Missiles left: a tube shows a white nose while its share is aboard.
	for id: String in _missile_cones:
		var e := systems.equipment_by_id(id)
		if e == null:
			continue
		var cones: Array = _missile_cones[id]
		var shown := ceili(float(systems.missiles_left(e)) / maxf(e.def.missile_capacity, 1.0) * cones.size())
		if int(_cones_shown.get(id, -1)) != shown:
			_cones_shown[id] = shown
			for k in cones.size():
				(cones[k] as Node3D).visible = k < shown
	for e in systems.equipment:
		if e.destroyed() and _parts.has(e.id):
			(_parts[e.id] as Node3D).visible = false
	for i in systems.modules.size():
		var id := systems.blueprint.modules[i].id
		if systems.modules[i].wrecked() and _parts.has(id) and not _broken.has(id):
			_broken[id] = true
			var mi := _parts[id] as MeshInstance3D
			_break_off(mi)
			mi.material_override = _wreck_material
			mi.mesh = ShipModelBuilder.dented(mi.mesh, hash(id))
			_hull_flats[mi] = ShipModelBuilder.flat_arrays(mi, _model_root)
			_hull_dirty = true
	if _hull_dirty:
		_hull_dirty = false
		_hull_batch.mesh = ShipModelBuilder.mesh_from_flats(_hull_pieces, _hull_flats)


func _break_off(mi: MeshInstance3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mi.name) + _broken.size()
	var size := mi.get_aabb().size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.33, 0.35)
	mat.metallic = 0.6
	mat.roughness = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in BREAK_PIECES:
		var box := BoxMesh.new()
		box.size = Vector3(size.x * rng.randf_range(0.25, 0.5), maxf(size.y * 0.08, 0.12), size.z * rng.randf_range(0.25, 0.5))
		var piece := MeshInstance3D.new()
		piece.mesh = box
		piece.material_override = mat
		var out := (mi.position + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		piece.position = mi.position + out * size.length() * 0.3
		add_child(piece)
		_pieces.append({"node": piece, "mat": mat, "velocity": out * rng.randf_range(1.5, 5.0),
			"spin": Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2)), "age": 0.0})


func _drift_pieces(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for p in _pieces:
		p.age += delta
		var node: MeshInstance3D = p.node
		if p.age >= BREAK_LIFETIME_S:
			node.queue_free()
			continue
		node.position += (p.velocity as Vector3) * delta
		node.rotation += (p.spin as Vector3) * delta
		(p.mat as StandardMaterial3D).albedo_color.a = clampf((BREAK_LIFETIME_S - p.age) / 3.0, 0.0, 1.0)
		alive.append(p)
	_pieces = alive


## Pieces a wrecked module sheds, and how long they stay in view (s).
const BREAK_PIECES := 4
const BREAK_LIFETIME_S := 12.0
var _broken := {}
var _pieces: Array[Dictionary] = []
var _plume_normals: Array[Vector3] = []
var _spinners: Array[Dictionary] = []
var _windows: Array[Dictionary] = []
var _nav_lights: Array[Node3D] = []
var _lights_check := 0.0
const RADAR_RPM := 12.0
var _plates: Dictionary = {}
## Hull modules and armour plates, drawn merged as _hull_batch (a ship is a
## hundred-odd of them, each a draw call otherwise). The pieces stay, hidden,
## as what wear and wrecks edit; the batch is rebuilt after they change.
var _hull_pieces: Array = []
var _hull_flats: Dictionary = {}  # piece -> ShipModelBuilder.flat_arrays()
var _hull_batch: MeshInstance3D
var _hull_dirty := false
var _model_root: Node3D


func _bake_hull(model: ShipModelBuilder.Model) -> void:
	_model_root = model.root
	for m in blueprint.modules:
		var mi := model.parts.get(m.id) as MeshInstance3D
		if mi != null:
			_hull_pieces.append(mi)
	_hull_pieces.append_array(model.plates.values())
	_hull_batch = MeshInstance3D.new()
	_hull_batch.name = "Hull"
	for piece: MeshInstance3D in _hull_pieces:
		_hull_flats[piece] = ShipModelBuilder.flat_arrays(piece, _model_root)
	_hull_batch.mesh = ShipModelBuilder.mesh_from_flats(_hull_pieces, _hull_flats)
	_model_root.add_child(_hull_batch)
	for piece: MeshInstance3D in _hull_pieces:
		piece.visible = false
var _plate_level: Dictionary = {}
var _char_mats: Dictionary = {}
var _wear_check := 0.0


## One additive cone per main engine, out along its face; length ∝ thrust.
func _build_plumes(nozzles: Array[Vector3], normals: Array[Vector3]) -> void:
	_plume_normals = normals
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
	for k in nozzles.size():
		var nozzle := nozzles[k]
		# Pivot at the nozzle so scaling along Z keeps the plume attached;
		# its +Z runs out along the engine's face.
		var pivot := Node3D.new()
		pivot.position = nozzle
		var out := normals[k] if k < normals.size() else Vector3.BACK
		if out.z < 0.99:
			pivot.basis = Basis.looking_at(-out, Vector3.UP if absf(out.y) < 0.9 else Vector3.BACK)
		pivot.visible = false
		add_child(pivot)
		var plume := MeshInstance3D.new()
		plume.mesh = cone
		plume.material_override = _plume_material
		plume.rotation_degrees = Vector3(90, 0, 0)  # cylinder +Y → +Z (aft)
		plume.position = Vector3(0, 0, cone.height * 0.5)
		pivot.add_child(plume)
		_plumes.append(pivot)
