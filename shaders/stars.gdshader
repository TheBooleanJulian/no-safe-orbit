// Real stars (scripts/presentation/starfield.gd): one camera-facing quad per
// catalogue star, a constant few pixels wide whatever the distance.
// Stars behind the planet (or the far body) are discarded and stars seen
// through the limb glow are dimmed, using the same geometry as
// planet_sky.gdshader.
// INSTANCE_CUSTOM: r = quad size (px), g = intensity.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

uniform vec3 planet_center = vec3(0.0, -6771000.0, 0.0);
uniform float planet_radius = 6371000.0;
uniform float entry_radius = 6471000.0;
uniform float pixel_angle = 0.0013;
uniform float exposure = 1.0;
// The far body in the sky (planet_sky.gdshader): stars behind it are hidden.
uniform vec3 far_center = vec3(0.0, 0.0, -384400000.0);
uniform float far_radius = 0.0;

varying vec3 view_ray_world;
varying float intensity;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float size = INSTANCE_CUSTOM.r * pixel_angle * length(center.xyz);
	VERTEX = center.xyz + vec3(VERTEX.xy * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	view_ray_world = (INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz;
	intensity = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float glow = exp(-dot(d, d) * 5.0);
	vec3 dir = normalize(view_ray_world);
	vec3 oc = CAMERA_POSITION_WORLD - planet_center;
	float b = dot(oc, dir);
	float c = dot(oc, oc) - planet_radius * planet_radius;
	if (far_radius > 0.0) {
		vec3 fo = (CAMERA_POSITION_WORLD - far_center) / far_radius;
		float fb = dot(fo, dir);
		if (fb < 0.0 && fb * fb - (dot(fo, fo) - 1.0) > 0.0) {
			discard;  // behind the far body
		}
	}
	float dim = 1.0;
	if (b < 0.0) {
		if (b * b - c > 0.0) {
			discard;  // the planet is in front of this star
		}
		float h = sqrt(max(dot(oc, oc) - b * b, 0.0)) - planet_radius;
		dim = smoothstep(0.0, 0.45 * (entry_radius - planet_radius), h);
	}
	ALBEDO = COLOR.rgb * glow * intensity * dim * exposure;
}
