// The station's docking hall seen from the berth (play-test batch 9): a
// minimal interior drawn as the sky — ribbed walls with two catwalks and
// their amber running lights, a gridded deck below with teal guide lines,
// light strips across the ceiling. No geometry: it is all from the view
// direction, so it costs nothing to keep in view.
shader_type sky;

uniform vec3 wall_color : source_color = vec3(0.050, 0.060, 0.080);
uniform vec3 deck_color : source_color = vec3(0.018, 0.022, 0.030);
uniform vec3 line_color : source_color = vec3(0.17, 0.20, 0.25);
uniform vec3 teal : source_color = vec3(0.0, 0.83, 0.78);
uniform vec3 gold : source_color = vec3(0.96, 0.78, 0.26);
uniform float ribs = 24.0;

float band(float x, float width) {
	return 1.0 - smoothstep(width * 0.5, width, abs(x));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float az = atan(d.x, d.z);
	float el = asin(clamp(d.y, -1.0, 1.0));
	float u = az / TAU * ribs;
	vec3 col = wall_color;
	// Wall ribs and two catwalks with running lights.
	float rib = band(fract(u) - 0.5, 0.04);
	col += line_color * 0.5 * rib;
	for (int k = 0; k < 2; k++) {
		float h = k == 0 ? 0.10 : 0.30;
		float walk = band(el - h, 0.010);
		col += line_color * walk;
		float lamp = band(el - h - 0.012, 0.006) * band(fract(u * 2.0) - 0.5, 0.05);
		col += gold * lamp * 0.9;
	}
	// The deck below: a grid on the floor plane, teal guide lines either side.
	if (d.y < -0.02) {
		vec2 p = d.xz / -d.y;
		float fade = clamp(1.0 / (1.0 + length(p) * 0.35), 0.0, 1.0);
		vec2 g = abs(fract(p * 2.0) - 0.5);
		float grid = max(band(g.x, 0.03), band(g.y, 0.03));
		vec3 deck = deck_color + line_color * grid * 0.7 * fade;
		deck += teal * 0.35 * fade * (band(abs(p.x) - 1.6, 0.03));
		col = mix(col, deck, smoothstep(-0.02, -0.08, d.y));
	}
	// The ceiling: light strips across it.
	if (d.y > 0.35) {
		vec2 q = d.xz / d.y;
		float strip = band(fract(q.x * 0.6) - 0.5, 0.05) * band(q.y, 2.2);
		vec3 ceiling = wall_color * 0.8 + vec3(0.55, 0.65, 0.75) * strip * 0.6;
		col = mix(col, ceiling, smoothstep(0.35, 0.5, d.y));
	}
	COLOR = col;
}
