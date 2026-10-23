class_name SmallBodyView
extends MeshInstance3D
## A small, lumpy central body drawn as itself (Milestone 16: Phobos and
## Deimos, OrbitalBody.shape_mesh): a closed mesh of its whole surface from
## its height map — P. C. Thomas's shape model, plus the same fine detail the
## ground collision uses (TerrainMap.height_at), so the ship lands on what it
## sees — with the body's colour map, turned with the body. The sky shader
## draws no sphere for such a body. Reads simulation state only.

## Vertices round (longitude) and pole to pole (latitude).
const SEGMENTS := 240
const RINGS := 120

static var _meshes: Dictionary = {}  # elevation map path -> ArrayMesh

## The body drawn, or null (hidden).
var body: OrbitalBody


func _ready() -> void:
	visible = false


## Draw `b` (null: nothing).
func configure(b: OrbitalBody, terrain: TerrainMap) -> void:
	body = b if b != null and b.shape_mesh and terrain != null else null
	visible = body != null
	if body == null:
		return
	mesh = build_mesh(body, terrain)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = body.surface_map
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_repeat = false
	material_override = mat


## Each frame: at the body's centre (render space), turned as it turns.
func update_view(world: WorldSimulation, planet_center: Vector3) -> void:
	if body == null:
		return
	transform = Transform3D(world.pci_to_fixed.inverse(), planet_center)


## The body's whole surface (body-fixed axes, m; cached per height map).
static func build_mesh(b: OrbitalBody, terrain: TerrainMap) -> ArrayMesh:
	if _meshes.has(b.elevation_map):
		return _meshes[b.elevation_map]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS + 1:
		var lat := 90.0 - 180.0 * i / RINGS
		for j in SEGMENTS + 1:
			var lon := -180.0 + 360.0 * j / SEGMENTS
			var dir := Vector3(cos(deg_to_rad(lat)) * cos(deg_to_rad(lon)), cos(deg_to_rad(lat)) * sin(deg_to_rad(lon)), sin(deg_to_rad(lat)))
			st.set_uv(Vector2(float(j) / SEGMENTS, float(i) / RINGS))
			st.add_vertex(dir * (b.radius_m + terrain.height_at(dir)))
	var row := SEGMENTS + 1
	for i in RINGS:
		for j in SEGMENTS:
			var a := i * row + j
			var c := a + row
			# Outward faces (Godot winds front faces clockwise).
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(c + 1)
			st.add_index(c)
	st.generate_normals()
	var m := st.commit()
	_meshes[b.elevation_map] = m
	return m
