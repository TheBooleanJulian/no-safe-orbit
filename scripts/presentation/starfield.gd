class_name Starfield
extends MultiMeshInstance3D
## The real night sky: every naked-eye star of the Yale Bright Star Catalogue
## (data/stars/bright_stars.txt, J2000 positions) placed by CelestialFrame, so
## constellations, the celestial pole and the Sun agree with the real sky as
## seen from the Solar System. Stars are the cue for rotation: translation
## never moves them. Size and brightness follow visual magnitude; colour
## follows B−V. See shaders/stars.gdshader for occlusion by the planet.

const CATALOG := "res://data/stars/bright_stars.txt"
const SHADER: Shader = preload("res://shaders/stars.gdshader")
## Distance the quads are drawn at (inside the camera's 120 km far plane).
const RADIUS_M := 100_000.0

var star_count: int = 0
var _material: ShaderMaterial


func build(frame: CelestialFrame) -> void:
	var stars := load_catalog(CATALOG)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	quad.material = _material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = stars.size()
	for i in stars.size():
		var s: Vector4 = stars[i]  # ra, dec, vmag, b-v
		var dir := frame.icrs_to_pci(CelestialFrame.radec_to_icrs(s.x, s.y))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, dir * RADIUS_M))
		mm.set_instance_color(i, color_from_bv(s.w))
		mm.set_instance_custom_data(i, Color(size_px(s.z), intensity(s.z), 0, 0))
	multimesh = mm
	star_count = stars.size()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Never cull: the quads move with the camera and are sized in the shader.
	custom_aabb = AABB(Vector3.ONE * -RADIUS_M * 2.0, Vector3.ONE * RADIUS_M * 4.0)


## Keep the sphere of stars centred on the camera; pass planet geometry.
func update_view(camera: Camera3D, planet_center: Vector3, body: OrbitalBody) -> void:
	global_position = camera.global_position
	var height := maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
	_material.set_shader_parameter("pixel_angle", deg_to_rad(camera.fov) / height)
	_material.set_shader_parameter("planet_center", planet_center)
	_material.set_shader_parameter("planet_radius", body.radius_m)
	_material.set_shader_parameter("entry_radius", body.entry_radius_m())


## Rows of Vector4(ra_deg, dec_deg, vmag, b_minus_v).
static func load_catalog(path: String) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n", false):
		if line.begins_with("#"):
			continue
		var f := line.split(" ", false)
		if f.size() >= 5:
			out.append(Vector4(f[1].to_float(), f[2].to_float(), f[3].to_float(), f[4].to_float()))
	return out


## Quad size in pixels; the visible core is about a third of it.
static func size_px(vmag: float) -> float:
	return clampf(6.5 - 0.7 * vmag, 2.4, 8.0)


## Linear brightness: flux relative to a magnitude-1 star, square-root
## compressed so faint stars stay visible and the brightest (> ~1.5) bloom.
static func intensity(vmag: float) -> float:
	var flux := pow(10.0, -0.4 * (vmag - 1.0))
	return clampf(sqrt(flux) * 2.0, 0.12, 6.0)


## Approximate star colour from B−V (Ballesteros 2012 temperature, then a
## black-body RGB fit), softened towards white as the eye sees it.
static func color_from_bv(bv: float) -> Color:
	var b := clampf(bv, -0.4, 2.0)
	var t := 4600.0 * (1.0 / (0.92 * b + 1.7) + 1.0 / (0.92 * b + 0.62))
	var k := t / 100.0
	var r := 1.0 if k <= 66.0 else clampf(1.292936 * pow(k - 60.0, -0.1332047), 0.0, 1.0)
	var g := clampf(0.3900816 * log(k) - 0.6318414, 0.0, 1.0) if k <= 66.0 else clampf(1.129891 * pow(k - 60.0, -0.0755148), 0.0, 1.0)
	var bl := 1.0 if k >= 66.0 else (0.0 if k <= 19.0 else clampf(0.5432068 * log(k - 10.0) - 1.1962541, 0.0, 1.0))
	return Color(r, g, bl).lerp(Color.WHITE, 0.35)
