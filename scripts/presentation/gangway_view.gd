class_name GangwayView
extends Node3D
## Draws each active gangway as a tube from our collar towards the target
## port: growing while it extends, full length once sealed. Reads simulation
## state only.

const RADIUS_M := 1.2
const COLOR_EXTENDING := Color(0.96, 0.78, 0.26)
const COLOR_SEALED := Color(0.75, 0.8, 0.86)
## Octagonal like the collars it joins — a square with its corners cut
## short (play-test batch 11) — and ribbed every RIB_SPACING_M.
const RIB_SPACING_M := 2.0
static var _ribs: ImageTexture

var _tubes: Dictionary = {}  # DockingLink -> MeshInstance3D


func sync(world: WorldSimulation, alpha: float, render_origin: Vector3) -> void:
	var seen := {}
	for link in world.links:
		if not link.active():
			continue
		var a := world.get_ship(link.attacker_id)
		var b := world.get_ship(link.target_id)
		if a == null or b == null:
			continue
		seen[link] = true
		var tube: MeshInstance3D = _tubes.get(link)
		if tube == null:
			tube = _make_tube()
			add_child(tube)
			_tubes[link] = tube
		var pa := a.interpolated_position(alpha) + a.interpolated_orientation(alpha) * link.a_port.position_body - render_origin
		var pb := b.interpolated_position(alpha) + b.interpolated_orientation(alpha) * link.b_port.position_body - render_origin
		var reach := 1.0 if link.sealed() else clampf(link.progress_s / link.required_s, 0.05, 1.0)
		var end := pa.lerp(pb, reach)
		var length := maxf(pa.distance_to(end), 0.01)
		var dir := (end - pa) / length
		var up := Vector3.RIGHT if absf(dir.dot(Vector3.UP)) > 0.95 else Vector3.UP
		# The tube runs along +Y: point Y along the gangway.
		var x := up.cross(dir).normalized()
		# Columns: X and Z across the tube, Y along it, stretched to length.
		tube.transform = Transform3D(Basis(x, dir * length, x.cross(dir)), (pa + end) * 0.5)
		var mat := tube.material_override as StandardMaterial3D
		mat.albedo_color = COLOR_SEALED if link.sealed() else COLOR_EXTENDING
		mat.uv1_scale = Vector3(1.0, length / RIB_SPACING_M, 1.0)
	for link in _tubes.keys():
		if not seen.has(link):
			(_tubes[link] as Node).queue_free()
			_tubes.erase(link)


## A dark band in eight: the ribs, repeated along the tube.
static func rib_texture() -> ImageTexture:
	if _ribs == null:
		var img := Image.create(1, 8, false, Image.FORMAT_RGB8)
		for y in 8:
			img.set_pixel(0, y, Color(0.45, 0.45, 0.45) if y == 0 else Color.WHITE)
		_ribs = ImageTexture.create_from_image(img)
	return _ribs


## The tube's cross-section: the collar's octagon.
static func outline() -> PackedVector2Array:
	return ShipModelBuilder.octagon(RADIUS_M, ShipModelBuilder.COLLAR_CHAMFER)


func _make_tube() -> MeshInstance3D:
	var tube := MeshInstance3D.new()
	tube.mesh = ShipModelBuilder.prism_mesh(outline(), 1.0, false)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.6
	mat.metallic = 0.3
	mat.albedo_texture = rib_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tube.material_override = mat
	return tube
