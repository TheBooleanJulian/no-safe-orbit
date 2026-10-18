class_name HitCam
extends PanelContainer
## Hit replay ("hit cam"): when one of your rounds strikes a ship, a small
## X-ray view replays the round's path through the hull — armour, bulkheads,
## the systems it damaged or destroyed, the rooms it breached — from the
## damage report's recorded path. A more severe hit replaces the one playing;
## a lesser one waits until the current replay has had its time.

const REPLAY_S := 2.2      # tracer flight from entry to end of path
const HOLD_S := 3.0        # then the result stays up
const MIN_SHOW_S := 1.2    # a replay plays at least this long before a lesser one may replace it
const COLOR_HULL := Color(0.35, 0.65, 0.9, 0.10)
const COLOR_EDGE := Color(0.45, 0.75, 1.0, 0.55)
const COLOR_INTACT := Color(0.45, 0.55, 0.5)
const COLOR_DAMAGED := Color(1.0, 0.75, 0.25)
const COLOR_DESTROYED := Color(1.0, 0.25, 0.2)
const COLOR_DEAD := Color(0.18, 0.18, 0.2)
const COLOR_BREACH := Color(1.0, 0.3, 0.25, 0.22)
const COLOR_TRACER := Color(1.0, 0.85, 0.5)
const EVENT_COLORS := {
	&"armor_pen": Color(1.0, 0.6, 0.2), &"armor_stop": Color(0.9, 0.9, 1.0),
	&"system_damaged": COLOR_DAMAGED, &"system_destroyed": COLOR_DESTROYED,
	&"breach": Color(1.0, 0.4, 0.35), &"hatch": Color(1.0, 0.85, 0.35),
	&"bulkhead_stop": Color(0.9, 0.9, 1.0), &"exit": Color(0.6, 0.9, 1.0),
	&"spent": Color(0.9, 0.9, 1.0), &"wrecked": COLOR_DESTROYED,
}

var _title: Label
var _caption: Label
var _viewport: SubViewport
var _camera: Camera3D
var _root: Node3D
var _tracer: MeshInstance3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _markers: Array[Dictionary] = []  # {node, distance}
var _path: PackedVector3Array = PackedVector3Array()
var _path_length := 0.0
var _age := 0.0
var _severity := -1
var _orbit_axis := Vector3.UP
var _cam_offset := Vector3.ZERO
var _focus := Vector3.ZERO


## Should a hit of `new_severity` replace the replay currently showing?
static func should_replace(showing: bool, age_s: float, current_severity: int, new_severity: int) -> bool:
	if not showing:
		return true
	if new_severity > current_severity:
		return true
	return age_s >= MIN_SHOW_S + REPLAY_S and new_severity >= current_severity - 1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	box.add_child(_title)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(400, 220)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_camera.far = 2000.0
	_viewport.add_child(_camera)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 12)
	_caption.custom_minimum_size = Vector2(400, 0)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_caption)


## Replay a hit. `design` = {blueprint, grid, stats} of the struck ship.
func show_hit(ev: HitEvent, design: Dictionary, systems: ShipSystems, target_name: String) -> void:
	var report := ev.report
	if report == null or report.path_body.size() < 1:
		return
	if not should_replace(visible, _age, _severity, report.severity()):
		return
	_severity = report.severity()
	_age = 0.0
	visible = true
	_title.text = "HIT CAM — %s · %s" % [target_name, report.headline().to_upper()]
	_caption.text = _caption_for(report)
	_build_scene(report, design, systems)


func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	var k := clampf(_age / REPLAY_S, 0.0, 1.0)
	var travelled := _path_length * _ease(k)
	_draw_trail(travelled)
	for m in _markers:
		(m.node as Node3D).visible = travelled >= m.distance - 0.01
	if _camera != null:
		var spin := Basis(_orbit_axis, 0.12 * _age)
		_camera.look_at_from_position(_focus + spin * _cam_offset, _focus, _orbit_axis)
	if _age > REPLAY_S + HOLD_S:
		visible = false
		_severity = -1


func _ease(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)


func _caption_for(report: DamageReport) -> String:
	var lines := PackedStringArray()
	for e in report.events:
		if e.kind in [&"system_destroyed", &"system_damaged", &"breach", &"wrecked"]:
			lines.append(e.text)
	if lines.is_empty():
		for e in report.events:
			lines.append(e.text)
	return "\n".join(lines.slice(0, 4))


func _build_scene(report: DamageReport, design: Dictionary, systems: ShipSystems) -> void:
	if _root != null:
		_root.queue_free()
	_markers.clear()
	_root = Node3D.new()
	_viewport.add_child(_root)
	var light := DirectionalLight3D.new()
	_root.add_child(light)
	light.look_at_from_position(Vector3.ZERO, Vector3(-0.4, -1.0, -0.5), Vector3.UP)
	var bp: ShipBlueprint = design.blueprint
	var grid: ShipGrid = design.grid
	var stats: ShipStats = design.stats
	var com := stats.center_of_mass_m
	var c := ShipGrid.CELL_SIZE_M
	var hull_mat := _flat(COLOR_HULL, true)
	var edges := ImmediateMesh.new()
	edges.surface_begin(Mesh.PRIMITIVE_LINES, _flat(COLOR_EDGE, true))
	for i in bp.modules.size():
		if grid.module_def(i) == null:
			continue
		var size := Vector3(grid.module_size(i)) * c
		var center := Vector3(bp.modules[i].position) * c + size * 0.5 - com
		_box(size, center, hull_mat)
		_box_edges(edges, center, size * 0.5)
	edges.surface_end()
	var edge_node := MeshInstance3D.new()
	edge_node.mesh = edges
	_root.add_child(edge_node)
	# Systems coloured by condition.
	for e in systems.equipment:
		var color := COLOR_INTACT
		if report.destroyed_ids.has(e.id):
			color = COLOR_DESTROYED
		elif report.damaged_ids.has(e.id):
			color = COLOR_DAMAGED
		elif e.destroyed():
			color = COLOR_DEAD
		var size: Vector3
		if e.def.is_external():
			size = Vector3.ONE * 1.2
		else:
			var fp := grid.equipment_footprint(e.index)
			size = Vector3(fp.x, 1, fp.y) * c * 0.8
		_box(size, e.body_position, _flat(color, false))
	# Rooms breached by this hit.
	for room_id in report.breached_rooms:
		for r in bp.rooms:
			if r.id == room_id:
				var size := Vector3(r.rect.size.x, 1, r.rect.size.y) * c
				var corner := Vector3(r.rect.position.x, r.deck, r.rect.position.y) * c
				_box(size * 0.98, corner + size * 0.5 - com, _flat(COLOR_BREACH, true))
	# The round's path: an incoming lead-in, then the recorded points.
	var dir := (report.path_body[-1] - report.path_body[0]).normalized() if report.path_body.size() > 1 else Vector3.FORWARD
	_path = PackedVector3Array([report.path_body[0] - dir * 25.0])
	_path.append_array(report.path_body)
	_path_length = 0.0
	var distance_at: Array[float] = [0.0]
	for i in range(1, _path.size()):
		_path_length += _path[i].distance_to(_path[i - 1])
		distance_at.append(_path_length)
	for e in report.events:
		var d := _distance_along(e.pos)
		var marker := _sphere(0.9, e.pos, _flat(EVENT_COLORS.get(e.kind, Color.WHITE), false, 3.0))
		marker.visible = false
		_markers.append({"node": marker, "distance": d})
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.mesh = _trail_mesh
	_root.add_child(_trail)
	_tracer = _sphere(0.6, _path[0], _flat(COLOR_TRACER, false, 3.0))
	# Camera: beside the path, looking at its middle; slowly orbits.
	_focus = (report.path_body[0] + report.path_body[-1]) * 0.5
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.1:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	_orbit_axis = side.cross(dir).normalized()
	var reach := maxf(stats.hull_bounds_m.size.length() * 0.62, 30.0)
	_cam_offset = (side * 0.85 + _orbit_axis * 0.45 - dir * 0.25).normalized() * reach
	_camera.look_at_from_position(_focus + _cam_offset, _focus, _orbit_axis)


func _distance_along(p: Vector3) -> float:
	var best := 0.0
	var best_err := INF
	var run := 0.0
	for i in range(1, _path.size()):
		var a := _path[i - 1]
		var b := _path[i]
		var seg := b - a
		var t := clampf((p - a).dot(seg) / maxf(seg.length_squared(), 1e-9), 0.0, 1.0)
		var err := (a + seg * t).distance_to(p)
		if err < best_err:
			best_err = err
			best = run + seg.length() * t
		run += seg.length()
	return best


func _draw_trail(travelled: float) -> void:
	if _trail_mesh == null:
		return
	_trail_mesh.clear_surfaces()
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _flat(COLOR_TRACER, false, 3.0))
	var run := 0.0
	var head := _path[0]
	_trail_mesh.surface_add_vertex(_path[0])
	for i in range(1, _path.size()):
		var seg := _path[i].distance_to(_path[i - 1])
		if run + seg >= travelled:
			head = _path[i - 1].lerp(_path[i], (travelled - run) / maxf(seg, 1e-6))
			_trail_mesh.surface_add_vertex(head)
			break
		run += seg
		head = _path[i]
		_trail_mesh.surface_add_vertex(head)
	_trail_mesh.surface_end()
	_tracer.position = head


func _flat(color: Color, transparent: bool, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if transparent or emission > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.albedo_color = color * (Color(emission, emission, emission, 1.0) if emission > 0.0 else Color.WHITE)
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_root.add_child(mi)
	return mi


func _sphere(radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_root.add_child(mi)
	return mi


static func _box_edges(im: ImmediateMesh, c: Vector3, h: Vector3) -> void:
	var corners: Array[Vector3] = []
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				corners.append(c + Vector3(x * h.x, y * h.y, z * h.z))
	for i in 8:
		for j in range(i + 1, 8):
			var d := corners[i] - corners[j]
			# Edges join corners differing in exactly one axis.
			var diffs := int(absf(d.x) > 1e-4) + int(absf(d.y) > 1e-4) + int(absf(d.z) > 1e-4)
			if diffs == 1:
				im.surface_add_vertex(corners[i])
				im.surface_add_vertex(corners[j])
