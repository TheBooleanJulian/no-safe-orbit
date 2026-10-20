class_name PlanetSky
extends WorldEnvironment
## Shows the central body (real geography, turning with the body), its
## atmosphere's limb (if it has one) and the Sun as a ray-traced sky
## (shaders/planet_sky.gdshader). The planet's surface scrolling past is the
## cue for orbital motion; the stars (Starfield) are the cue for rotation.

const SKY_SHADER: Shader = preload("res://shaders/planet_sky.gdshader")

var _material: ShaderMaterial
## The other body in the sky (Location.sky_body), or null.
var sky_body: OrbitalBody
## Its centre relative to the render origin (m), from the last update_view.
var sky_body_center := Vector3.ZERO


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


## `other`: the far body drawn in the sky (null for none).
func configure(body: OrbitalBody, other: OrbitalBody = null) -> void:
	sky_body = other
	_material.set_shader_parameter("far_radius", other.radius_m if other != null else 0.0)
	if other != null:
		_material.set_shader_parameter("far_map", other.surface_map)
		_material.set_shader_parameter("far_has_air", 1.0 if other.has_atmosphere else 0.0)
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
	if sky_body != null:
		sky_body_center = planet_center_render + frame.position_of(sky_body, sim_time)
		_material.set_shader_parameter("far_center", sky_body_center)
		_material.set_shader_parameter("far_to_body", frame.body_fixed_of(sky_body, sim_time))
