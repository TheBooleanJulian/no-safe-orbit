class_name ShipPreview3D
extends SubViewportContainer
## 3D view of the design, built with the same ShipModelBuilder as the flight
## view. Perspective (the small inspection pane): drag to orbit; it turns
## slowly on its own when idle. Isometric (the main view's alternative to
## the top-down deck editor): an orthographic camera at the true isometric
## angle, turned in quarter steps; decks above the one being edited are cut
## away, its rooms and systems are shown, and — when `editable` — it takes
## the same clicks and drags as the deck editor, picked on the deck's plane.

signal cell_pressed(cell: Vector3i, face: StringName, button: MouseButton, shift: bool)
signal room_dragged(deck: int, rect: Rect2i)
signal hover_changed(cell: Vector3i, face: StringName, shift: bool)

const IDLE_TURN_RATE := 0.25  # rad/s
## Isometric elevation: atan(1 / √2).
const ISO_PITCH := -0.6154797
## Pointer within this fraction of a cell edge picks that edge's face.
const EDGE_ZONE := 0.28

var isometric: bool = false
## Middle of a cell open both ways picks the underside (shipyard [V]).
var prefer_underside: bool = false
var editable: bool = false
var deck: int = 0
## Room, armour and bus tools: left-drag draws a rectangle.
var drag_rooms: bool = false
var ghost_cells: Array[Vector3i] = []
var ghost_ok: bool = true
## The station's berth (play-test batch 6): the ship sits in a docking bay —
## a deck plate with guide lines below it, gantry towers on either beam with
## clamp arms reaching in, work lights. Set before show_design.
var berth: bool = false
var _berth: Node3D

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _model: Node3D
var _parts: Dictionary = {}
var _overlay: Node3D
var _editor: ShipEditor
var _com: MeshInstance3D
var _show_com := false
var _center := Vector3.ZERO
var _yaw := 2.4
var _pitch := -0.45
var _distance := 90.0
var _extent := 40.0
var _iso_turn := 0
var _idle := true
var _drag_start: Variant = null
var _hover := Vector3i(1 << 20, 0, 0)
var _hover_face: StringName = &""


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var light := DirectionalLight3D.new()
	light.light_energy = 1.3
	_viewport.add_child(light)
	light.look_at_from_position(Vector3.ZERO, Vector3(-0.5, -1.0, -0.3), Vector3.UP)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_overlay = Node3D.new()
	_pivot.add_child(_overlay)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.far = 2000.0
	_viewport.add_child(_camera)
	_update_camera()


func show_design(editor: ShipEditor) -> void:
	_editor = editor
	if _model != null:
		_model.queue_free()
		_model = null
	_parts = {}
	if editor.blueprint.modules.is_empty():
		_refresh_overlay()
		return
	_center = editor.grid.hull_bounds_m().get_center()
	var model := ShipModelBuilder.build(editor.blueprint, editor.grid, _center)
	_model = model.root
	_parts = model.parts
	_pivot.add_child(_model)
	_distance = maxf(editor.grid.hull_bounds_m().size.length() * 1.6, 30.0)
	_extent = maxf(editor.grid.hull_bounds_m().size.length(), 20.0)
	if berth:
		_build_berth(editor.grid.hull_bounds_m().size * 0.5)
	_apply_cutaway()
	_refresh_overlay()
	_update_com()
	_update_camera()


## The docking bay around a hull of half-size `half` (m), centred on it.
func _build_berth(half: Vector3) -> void:
	if _berth != null:
		_berth.queue_free()
	_berth = Node3D.new()
	_berth.name = "Berth"
	_pivot.add_child(_berth)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.11, 0.12, 0.14)
	steel.metallic = 0.6
	steel.roughness = 0.45
	var floor_y := -half.y - 5.0
	var reach := half.x + 14.0
	_berth_box(Vector3(reach * 2.0 + 24.0, 0.6, half.z * 2.0 + 36.0), Vector3(0, floor_y, 0), steel)
	# Guide lines along the berth, a hazard bar across its head.
	var guide := _glow(CyberTheme.CYAN * 0.5, 0.5)
	for side: float in [-1.0, 1.0]:
		_berth_box(Vector3(0.25, 0.1, half.z * 2.0 + 30.0), Vector3(side * (half.x + 3.0), floor_y + 0.35, 0), guide)
	_berth_box(Vector3(half.x * 2.0 + 6.0, 0.1, 0.35), Vector3(0, floor_y + 0.35, -half.z - 8.0), _glow(CyberTheme.AMBER * 0.6, 0.5))
	# Gantry towers on either beam, a clamp arm from each to the hull side.
	var towers := maxi(2, ceili(half.z * 2.0 / 60.0))
	for side: float in [-1.0, 1.0]:
		for k in towers:
			var z := lerpf(-half.z * 0.7, half.z * 0.7, float(k) / float(towers - 1))
			var height := half.y * 2.0 + 6.0
			_berth_box(Vector3(2.4, height, 2.4), Vector3(side * reach, floor_y + height * 0.5, z), steel)
			_berth_box(Vector3(reach - half.x, 1.0, 1.4), Vector3(side * (half.x + (reach - half.x) * 0.5), 0.0, z), steel)
			_berth_box(Vector3(0.5, 0.5, 0.5), Vector3(side * reach, floor_y + height + 0.4, z), _glow(CyberTheme.AMBER, 2.0))
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.92, 0.8)
			lamp.light_energy = 1.2
			lamp.omni_range = maxf(half.length(), 30.0)
			lamp.position = Vector3(side * (reach - 1.5), floor_y + height, z)
			_berth.add_child(lamp)


func _berth_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var m := MeshInstance3D.new()
	m.mesh = box
	m.material_override = mat
	m.position = pos
	_berth.add_child(m)


static func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = energy
	return mat


## Centre of mass as a gold sphere drawn over the hull (shipyard [C]).
func set_show_com(on: bool) -> void:
	_show_com = on
	_update_com()


func _update_com() -> void:
	if _com == null:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(CyberTheme.AMBER, 0.9)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.render_priority = 10
		_com = MeshInstance3D.new()
		_com.mesh = mesh
		_com.material_override = mat
		_pivot.add_child(_com)
	var ok := _editor != null and _editor.stats != null and _editor.stats.mass_kg > 0.0
	_com.visible = _show_com and ok
	if ok:
		_com.position = _editor.stats.center_of_mass_m - _center
		_com.scale = Vector3.ONE * maxf(_extent * 0.025, 0.8)


## Turn the isometric view by quarter turns.
func turn_iso(quarter_turns: int) -> void:
	_iso_turn = posmod(_iso_turn + quarter_turns, 4)
	_update_camera()


## The deck being edited changed, or the ghost did: redraw the cut and overlay.
func set_deck(d: int) -> void:
	deck = d
	_apply_cutaway()
	_refresh_overlay()


func refresh_ghost() -> void:
	_refresh_overlay()


func _process(delta: float) -> void:
	if _idle and not isometric and is_visible_in_tree():
		_yaw += IDLE_TURN_RATE * delta
		_update_camera()


func _gui_input(event: InputEvent) -> void:
	if isometric and editable:
		_edit_input(event)
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		var rel := (event as InputEventMouseMotion).relative
		_yaw -= rel.x * 0.01
		_pitch = clampf(_pitch - rel.y * 0.01, -1.4, 1.4)
		_idle = false
		_update_camera()
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance *= 0.9
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance *= 1.1
		_update_camera()


func _update_camera() -> void:
	if _camera == null:
		return
	if isometric:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = _extent * 1.1
		# From ahead and to port (front-left), like the deck editor's view
		# turned to face the nose; ⟲ / ⟳ turn it in quarter steps.
		var yaw := PI * 1.25 + _iso_turn * PI * 0.5
		var dir := Vector3(sin(yaw) * cos(ISO_PITCH), -sin(ISO_PITCH), cos(yaw) * cos(ISO_PITCH))
		_camera.position = dir * 400.0
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		return
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var d := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = d * _distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)


# --- Isometric editing ------------------------------------------------------------

## Hide everything above the deck being edited (iso only); show its hull
## see-through so its rooms show.
func _apply_cutaway() -> void:
	if _editor == null or _parts.is_empty():
		return
	var bp := _editor.blueprint
	for m in bp.modules:
		var node: Node3D = _parts.get(m.id)
		if node == null:
			continue
		node.visible = not isometric or m.position.y <= deck
		var mi := node as MeshInstance3D
		if mi != null:
			mi.transparency = 0.7 if isometric and m.position.y == deck else 0.0
	for e in bp.equipment:
		var node: Node3D = _parts.get(e.id)
		if node != null:
			node.visible = not isometric or e.cell.y <= deck
	for extra in ["armour", "lights"]:
		var node: Node3D = _parts.get(extra)
		if node != null:
			node.visible = not isometric
	_update_camera()


## The current deck's rooms and internal systems, the placement ghost and a
## grid plane at deck level (iso only).
func _refresh_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()
	if not isometric or _editor == null:
		return
	var cs := ShipGrid.CELL_SIZE_M
	var grid := _editor.grid
	var bp := _editor.blueprint
	for r in bp.rooms:
		var def: RoomDefinition = grid.catalog.rooms.get(r.def_id)
		if def == null or r.deck != deck:
			continue
		var size := Vector3(r.rect.size.x, 0.25, r.rect.size.y) * cs
		var corner := Vector3(r.rect.position.x, deck, r.rect.position.y) * cs
		_overlay_box(corner + Vector3(size.x * 0.5, 0.15, size.z * 0.5) - _center, size - Vector3(0.2, 0, 0.2), Color(def.color, 0.75))
	for i in bp.equipment.size():
		var def := grid.equipment_def(i)
		if def == null or def.is_external() or bp.equipment[i].cell.y != deck:
			continue
		var fp := grid.equipment_footprint(i)
		var size := Vector3(fp.x, 0.55, fp.y) * cs - Vector3(0.5, 0, 0.5) * cs * 0.3
		var corner := Vector3(bp.equipment[i].cell) * cs
		_overlay_box(corner + Vector3(fp.x * cs * 0.5, 0.9, fp.y * cs * 0.5) - _center, size, Color(def.color, 0.95))
	for cell in ghost_cells:
		if cell.y == deck:
			_overlay_box((Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * cs - _center, Vector3.ONE * cs * 0.96,
				Color(0.4, 1.0, 0.55, 0.35) if ghost_ok else Color(1.0, 0.35, 0.3, 0.35))
	# Deck plane: a faint grid sheet across the hull bounds at deck level.
	var b := grid.hull_bounds_m()
	_overlay_box(Vector3(b.get_center().x, deck * cs + 0.02, b.get_center().z) - _center,
		Vector3(b.size.x + cs * 2.0, 0.02, b.size.z + cs * 2.0), Color(0.35, 0.65, 0.9, 0.12))


func _overlay_box(center: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = center
	_overlay.add_child(mi)


## Grid cell (on the edited deck) under a point of the view, and where in
## it (0..1 along x and z), or {} if the pointer misses the deck plane.
func pick(pos: Vector2) -> Dictionary:
	if _editor == null:
		return {}
	var o := _camera.project_ray_origin(pos)
	var d := _camera.project_ray_normal(pos)
	# The deck's floor, where its rooms and the placement ghost are drawn.
	var plane_y := deck * ShipGrid.CELL_SIZE_M + 0.15 - _center.y
	if absf(d.y) < 1e-6:
		return {}
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return {}
	var g := (o + d * t + _center) / ShipGrid.CELL_SIZE_M
	var cell := Vector3i(floori(g.x), deck, floori(g.z))
	return {"cell": cell, "u": g.x - floorf(g.x), "v": g.z - floorf(g.z)}


## Face from where in the cell the pointer is (like the deck editor).
func face_for(hit: Dictionary, shift: bool) -> StringName:
	var u: float = hit.u  # 0 = port edge
	var v: float = hit.v  # 0 = fore edge
	var d := {&"port": u, &"starboard": 1.0 - u, &"fore": v, &"aft": 1.0 - v}
	var best: StringName = &""
	var best_d := EDGE_ZONE
	for face in d:
		if d[face] < best_d:
			best = face
			best_d = d[face]
	if best != &"":
		return best
	return DeckEditor.pick_vertical(_editor, hit.cell, shift, prefer_underside)


func _edit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hit := pick(mm.position)
		if hit.is_empty():
			return
		var face := face_for(hit, mm.shift_pressed)
		if hit.cell != _hover or face != _hover_face:
			_hover = hit.cell
			_hover_face = face
			hover_changed.emit(hit.cell, face, mm.shift_pressed)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_extent *= 0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
				_update_camera()
			accept_event()
			return
		var hit := pick(mb.position)
		if hit.is_empty():
			return
		var cell: Vector3i = hit.cell
		if mb.button_index == MOUSE_BUTTON_LEFT and drag_rooms:
			if mb.pressed:
				_drag_start = cell
			elif _drag_start != null:
				var a: Vector3i = _drag_start
				_drag_start = null
				room_dragged.emit(deck, Rect2i(mini(a.x, cell.x), mini(a.z, cell.z), absi(cell.x - a.x) + 1, absi(cell.z - a.z) + 1))
			accept_event()
		elif mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			cell_pressed.emit(cell, face_for(hit, mb.shift_pressed), mb.button_index, mb.shift_pressed)
			accept_event()
