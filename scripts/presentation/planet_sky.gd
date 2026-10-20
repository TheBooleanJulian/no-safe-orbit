class_name PlanetSky
extends WorldEnvironment
## Shows the central body (real geography, turning with the body), its
## atmosphere's limb (if it has one) and the Sun as a ray-traced sky
## (shaders/planet_sky.gdshader). The planet's surface scrolling past is the
## cue for orbital motion; the stars (Starfield) are the cue for rotation.

const SKY_SHADER: Shader = preload("res://shaders/planet_sky.gdshader")

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = _material
	# Real-time radiance at the fast-filter size; the shader returns black for
	# the radiance pass, so the per-frame uniform updates stay cheap.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED


func configure(body: OrbitalBody) -> void:
	_material.set_shader_parameter("planet_radius", body.radius_m)
	_material.set_shader_parameter("entry_radius", body.entry_radius_m())
	_material.set_shader_parameter("has_air", 1.0 if body.has_atmosphere else 0.0)
	_material.set_shader_parameter("surface_map", body.surface_map)


## `planet_center_render`: body centre relative to the render origin (m).
func update_view(planet_center_render: Vector3, camera: Camera3D, frame: CelestialFrame, sim_time: float) -> void:
	_material.set_shader_parameter("planet_center", planet_center_render)
	var height := maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
	_material.set_shader_parameter("pixel_angle", deg_to_rad(camera.fov) / height)
	_material.set_shader_parameter("pci_to_body", frame.pci_to_body_fixed(sim_time))
	_material.set_shader_parameter("cloud_time", sim_time)
