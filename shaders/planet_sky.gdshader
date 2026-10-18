// Central body, entry-interface limb, sun and stars, ray-traced per pixel.
// A real-scale planet cannot be a mesh (the limb would need thousands of
// segments and the sphere sits far beyond any depth range). Drawn as the sky
// it is always behind ships, which is correct: nothing in play is ever below
// the entry interface. Driven by scripts/presentation/planet_sky.gd.
shader_type sky;
render_mode use_debanding;

// Planet centre in render space (m); updated every frame.
uniform vec3 planet_center = vec3(0.0, -6771000.0, 0.0);
uniform float planet_radius = 6371000.0;
// Entry interface (Kármán line): the visible top of the atmosphere glow.
uniform float entry_radius = 6471000.0;
// Angle subtended by one screen pixel (rad), for anti-aliasing.
uniform float pixel_angle = 0.0013;

uniform vec3 ocean_color : source_color = vec3(0.012, 0.05, 0.14);
uniform vec3 land_color : source_color = vec3(0.22, 0.26, 0.13);
uniform vec3 arid_color : source_color = vec3(0.52, 0.43, 0.29);
uniform vec3 ice_color : source_color = vec3(0.85, 0.9, 0.95);
uniform vec3 cloud_color : source_color = vec3(0.93, 0.95, 0.98);
uniform vec3 air_color : source_color = vec3(0.32, 0.56, 1.0);
// Scale height of the visible limb glow (m).
uniform float air_scale_height = 9000.0;
// Picks which procedural "Earth" is drawn (noise-space offset).
uniform vec3 surface_offset = vec3(0.0);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// PCG3D integer hash. Lattice gradients must be bit-identical whichever
// neighbouring cell evaluates them; a float hash is not (the compiler may
// reassociate (i + 1) * c), which shows up as block seams in the clouds.
uvec3 pcg3d(uvec3 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return v;
}

// Pseudo-random gradient in [-1, 1]³ for an integer lattice point.
vec3 hash33(vec3 lattice) {
	uvec3 h = pcg3d(uvec3(ivec3(lattice)));
	return vec3(h) * (2.0 / 4294967295.0) - 1.0;
}

// Gradient (Perlin-style) noise, roughly in [-1, 1]. Unlike value noise its
// contours do not follow the lattice, so thresholded coastlines stay organic.
float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = dot(hash33(i), f);
	float n100 = dot(hash33(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
	float n010 = dot(hash33(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
	float n110 = dot(hash33(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
	float n001 = dot(hash33(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
	float n101 = dot(hash33(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
	float n011 = dot(hash33(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
	float n111 = dot(hash33(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));
	return 1.7 * mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

// Fractal noise in [0, 1], mean 0.5. Octaves whose features are smaller than
// a few pixels (`footprint_m` = surface metres per pixel) fade to the mean.
float fbm(vec3 p, int octaves, float wavelength_m, float footprint_m) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		float w = clamp(wavelength_m / (footprint_m * 6.0) - 0.5, 0.0, 1.0);
		sum += amp * w * gnoise(p);
		norm += amp;
		p = p * 2.03 + vec3(17.1, 3.7, 9.2);
		wavelength_m *= 0.4926;
		amp *= 0.55;
	}
	return 0.5 + 0.5 * sum / norm;
}

vec3 surface(vec3 n, vec3 view, vec3 sun, float footprint_m) {
	// Domain warp: bends continent outlines so no coastline runs straight.
	vec3 q = n * 2.2 + surface_offset;
	vec3 warp = vec3(gnoise(q * 0.8 + 3.1), gnoise(q * 0.8 + 7.7), gnoise(q * 0.8 + 12.9));
	float continents = fbm(q + warp * 0.6, 10, planet_radius / 2.2, footprint_m);
	// Coastline softness grows with pixel footprint (anti-aliasing at range).
	float coast = 0.006 + 0.05 * clamp(footprint_m / 40000.0, 0.0, 1.0);
	float land = smoothstep(0.54 - coast, 0.54 + coast, continents);
	float aridity = fbm(n * 5.0 + 11.0, 6, planet_radius / 5.0, footprint_m);
	vec3 ground = mix(land_color, arid_color, smoothstep(0.45, 0.7, aridity));
	// Pole on the PCI +X axis; the sandbox orbit is equatorial.
	float ice = smoothstep(0.86, 0.9, abs(n.x) + 0.05 * aridity);
	vec3 albedo = mix(ocean_color, ground, land);
	albedo = mix(albedo, ice_color, ice);
	float cloud_noise = fbm(n * vec3(4.0, 7.0, 4.0) + 37.0 + surface_offset, 9, planet_radius / 5.0, footprint_m);
	float cloud = smoothstep(0.47, 0.62, cloud_noise);  // ≈30 % cover
	albedo = mix(albedo, cloud_color, cloud * 0.9);

	float ndl = dot(n, sun);
	float day = smoothstep(-0.06, 0.1, ndl);
	vec3 col = albedo * max(ndl, 0.0) * 1.6;
	vec3 h = normalize(sun + view);
	float water = (1.0 - land) * (1.0 - ice) * (1.0 - cloud);
	col += vec3(1.0, 0.92, 0.8) * pow(max(dot(n, h), 0.0), 220.0) * water * day * 1.5;
	// Looking obliquely through more air: haze towards the limb.
	float grazing = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);
	col = mix(col, air_color * 0.9 * day, grazing * 0.5);
	return col + albedo * 0.008;  // faint night side
}

vec3 star_field(vec3 dir) {
	vec3 a = abs(dir);
	vec2 uv;
	vec3 face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = dir.yz / a.x;
		face = vec3(sign(dir.x), 0.0, 0.0);
	} else if (a.y >= a.z) {
		uv = dir.xz / a.y;
		face = vec3(0.0, sign(dir.y), 0.0);
	} else {
		uv = dir.xy / a.z;
		face = vec3(0.0, 0.0, sign(dir.z));
	}
	const float CELLS = 64.0;
	vec2 g = (uv * 0.5 + 0.5) * CELLS;
	vec2 cell = floor(g);
	vec3 seed = vec3(cell, 0.0) + face * 131.0;
	if (hash13(seed) > 0.11) {  // ~11 % of cells hold a star → ≈2,700 stars
		return vec3(0.0);
	}
	vec2 centre = vec2(hash13(seed + 1.7), hash13(seed + 9.1)) * 0.7 + 0.15;
	float d_rad = length(g - cell - centre) * (2.0 / CELLS) * 0.8 / (1.0 + 0.5 * dot(uv, uv));
	float radius = pixel_angle * 0.9;
	float b = hash13(seed + 4.4);
	float brightness = 0.25 + 2.5 * b * b * b;
	float warmth = hash13(seed + 6.6);
	vec3 tint = vec3(0.85 + 0.15 * warmth, 0.88, 1.0 - 0.25 * warmth);
	return tint * brightness * exp(-(d_rad * d_rad) / (radius * radius));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = vec3(0.0);  // the sky is not used for lighting
	} else {
		vec3 dir = EYEDIR;
		vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
		vec3 oc = POSITION - planet_center;
		float b = dot(oc, dir);
		float c = dot(oc, oc) - planet_radius * planet_radius;
		float disc = b * b - c;
		if (disc > 0.0 && -b - sqrt(disc) > 0.0) {
			float t = -b - sqrt(disc);
			vec3 n = normalize(oc + dir * t);
			float footprint = t * pixel_angle / max(dot(n, -dir), 0.05);
			COLOR = surface(n, -dir, sun, footprint);
		} else {
			vec3 col = star_field(dir);
			// Limb glow: brightness from the ray's closest approach altitude.
			float glow = 0.0;
			if (b < 0.0) {
				float r_min = sqrt(max(dot(oc, oc) - b * b, 0.0));
				float h = r_min - planet_radius;
				float top = entry_radius - planet_radius;
				if (h < top) {
					vec3 m = normalize(oc - dir * b);
					float day = smoothstep(-0.25, 0.3, dot(m, sun));
					glow = exp(-h / air_scale_height) * (1.0 - smoothstep(top * 0.5, top, h)) * day;
				}
			}
			col *= 1.0 - clamp(glow * 6.0, 0.0, 1.0);
			col += air_color * glow * 1.4 + vec3(0.9, 0.95, 1.0) * glow * glow * 0.5;
			float d = dot(dir, sun);
			col += vec3(1.0, 0.97, 0.9) * (smoothstep(0.999984, 0.999990, d) * 30.0 + pow(max(d, 0.0), 900.0) * 0.8);
			COLOR = col;
		}
	}
}
