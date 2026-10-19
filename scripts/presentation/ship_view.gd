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
var _hole_material: StandardMaterial3D
var _scorch_material: StandardMaterial3D


func _ready() -> void:
	var model := ShipModelBuilder.build(blueprint, grid, stats.center_of_mass_m, tint, hull_name)
	add_child(model.root)
	_parts = model.parts
	_beacons = model.beacons
	_turrets = model.turrets
	_build_plumes(model.engine_nozzles)
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
	for pivot in _plumes:
		pivot.visible = fwd_fraction > 0.01
		pivot.scale = Vector3(1.0, 1.0, lerpf(0.2, 1.0, fwd_fraction))
	_plume_material.albedo_color.a = 0.15 + 0.4 * fwd_fraction
	if state.systems != null:
		_show_damage(state.systems)
	_train_turrets(state)
	_update_jets(state)
	_clock += get_process_delta_time()
	var on := fmod(_clock, BEACON_PERIOD_S) < 0.25
	for b in _beacons:
		b.visible = on and b.get_parent().visible


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
func _train_turrets(state: ShipState) -> void:
	var ids := state.config.cannon_mount_ids
	for t in _turrets:
		var k := ids.find(t.id)
		if k < 0 or k >= state.turret_dirs.size():
			continue
		var dir := state.turret_dirs[k]
		var pivot: Node3D = t.pivot
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.BACK
		pivot.basis = Basis.looking_at(dir, up)


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
