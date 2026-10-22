class_name TerrainView
extends MeshInstance3D
## The ground close up (play-test batch 10): below the body's terrain
## altitude (OrbitalBody.entry_interface_altitude_m, 11 km on the Moon) a
## mesh of the real surface (WorldSimulation.terrain — NASA's LOLA heights)
## out to the horizon, or as far as the camera sees (REACH_MAX_M), centred
## under the player: rings denser close in, the body's colour map on it.
## Its heights fade to the mean radius at the edge, where the sky's flat
## sphere carries on; descending through the band below the terrain
## altitude, the heights grow in from flat (MORPH_M). Rebuilt every
## REBUILD_S. Reads simulation state only.

const RINGS := 40
const SEGMENTS := 72
const REACH_MAX_M := 115_000.0
const MORPH_M := 2000.0
const REBUILD_S := 0.4
const EDGE_FADE_FROM := 0.7
const GROUND_TONE := 0.45

var _material: StandardMaterial3D
var _clock := 0.0
## Rings and segments last built, and the height scale used (for tests).
var built_vertices := 0
var morph := 0.0
## Where the mesh is anchored: the ground point under the player when built.
var _up := Vector3.UP
var _radius := 0.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## `planet_center`: the body's centre relative to the render origin (m).
func update_view(world: WorldSimulation, player: ShipState, planet_center: Vector3, delta: float) -> void:
	var body := world.body
	if world.terrain == null or world.frame == null or player == null:
		visible = false
		return
	var altitude := world.altitude_of(player)
	var top := body.entry_interface_altitude_m
	if altitude >= top:
		visible = false
		return
	_clock -= delta
	if visible and _clock > 0.0:
		position = planet_center + _up * _radius
		return
	_clock = REBUILD_S
	morph = clampf((top - altitude) / MORPH_M, 0.0, 1.0)
	rebuild(world, world.frame.pci_position(player.position).to_vector3(), maxf(altitude, 0.0), planet_center)
	visible = true


func rebuild(world: WorldSimulation, player_pci: Vector3, altitude: float, planet_center: Vector3) -> void:
	var body := world.body
	var r := body.radius_m
	var up := player_pci.normalized()
	var t1 := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := up.cross(t1)
	# Out to the horizon (the exact angle: on Phobos, 11 km across, the
	# small-angle sqrt(2rh) overshoots), at most a right angle round.
	var horizon := acos(r / (r + maxf(altitude, 500.0)))
	var reach := minf(minf(r * horizon * 1.1, REACH_MAX_M), r * PI * 0.5)
	var centre_fixed := world.pci_to_fixed * up
	var centre_lon := rad_to_deg(atan2(centre_fixed.y, centre_fixed.x))
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = body.surface_map
		# The colour map is normalised bright; the ground in full sun is grey.
		_material.albedo_color = Color(GROUND_TONE, GROUND_TONE, GROUND_TONE)
		_material.texture_repeat = true
		_material.roughness = 1.0
		_material.metallic = 0.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material)
	for i in RINGS + 1:
		var f := float(i) / RINGS
		var s := reach * f * f
		var ang := s / r
		var fade := 1.0 - smoothstep(EDGE_FADE_FROM, 1.0, f)
		for j in SEGMENTS:
			var a := TAU * j / SEGMENTS
			var dir := up * cos(ang) + (t1 * cos(a) + t2 * sin(a)) * sin(ang)
			var fixed := world.pci_to_fixed * dir
			var h := world.terrain.height_at(fixed) * morph * fade
			var lat := rad_to_deg(asin(clampf(fixed.z, -1.0, 1.0)))
			var lon := rad_to_deg(atan2(fixed.y, fixed.x))
			lon = centre_lon + wrapf(lon - centre_lon, -180.0, 180.0)  # no seam across 180°
			st.set_uv(Vector2((lon + 180.0) / 360.0, (90.0 - lat) / 180.0))
			st.add_vertex((dir - up) * r + dir * h)
	for i in RINGS:
		for j in SEGMENTS:
			var a := i * SEGMENTS + j
			var b := i * SEGMENTS + (j + 1) % SEGMENTS
			var c := a + SEGMENTS
			var d := b + SEGMENTS
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	mesh = st.commit()
	built_vertices = (RINGS + 1) * SEGMENTS
	_up = up
	_radius = r
	position = planet_center + up * r
