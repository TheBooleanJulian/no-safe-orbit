// The central body (Earth, the Moon…), its atmosphere's limb, one other
// body far off in the sky (the Moon from Earth orbit, Earth from lunar
// orbit; lit by the Sun, so it shows its phase) and the Sun, ray-traced per
// pixel.
// A real-scale planet cannot be a mesh (the limb would need thousands of
// segments and the sphere sits far beyond any depth range). Drawn as the sky
// it is always behind ships, which is correct: nothing in play is ever below
// the entry interface. Stars are drawn separately (stars.gdshader).
// Driven by scripts/presentation/planet_sky.gd.
shader_type sky;
render_mode use_debanding;

// Planet centre in render space (m); updated every frame.
uniform vec3 planet_center = vec3(0.0, -6771000.0, 0.0);
uniform float planet_radius = 6371000.0;
// Entry interface (Kármán line): the visible top of the atmosphere glow.
uniform float entry_radius = 6471000.0;
// 1 with an atmosphere (limb glow, haze, clouds, sea glint), 0 airless.
uniform float has_air = 1.0;
// Angle subtended by one screen pixel (rad), for anti-aliasing.
uniform float pixel_angle = 0.0013;
// PCI → body-fixed rotation (turns with the body; CelestialFrame.pci_to_body_fixed).
uniform mat3 pci_to_body = mat3(1.0);
// Real geography: equirectangular, left edge 180° W, top edge 90° N.
uniform sampler2D surface_map : source_color, filter_linear_mipmap, repeat_enable;
// The far body: centre relative to the render origin (m), radius, map,
// rotation (PCI → its fixed axes), air; far_radius 0 = none.
uniform vec3 far_center = vec3(0.0, 0.0, -384400000.0);
uniform float far_radius = 0.0;
uniform sampler2D far_map : source_color, filter_linear_mipmap, repeat_enable;
uniform mat3 far_to_body = mat3(1.0);
uniform float far_has_air = 0.0;
// Simulation time (s), drifts the clouds.
uniform float cloud_time = 0.0;

uniform vec3 cloud_color : source_color = vec3(0.93, 0.95, 0.98);
uniform vec3 air_color : source_color = vec3(0.32, 0.56, 1.0);
// Scale height of the visible limb glow (m).
uniform float air_scale_height = 9000.0;

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

// Gradient (Perlin-style) noise, roughly in [-1, 1].
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

// A body's lit surface at unit normal `n` (PCI), seen along `view`:
// `map` sampled through `to_body` (PCI → body-fixed), `radius` (m), `air`
// 1 for clouds, sea glint and haze. Shared by the central and far body.
vec3 surface(vec3 n, vec3 view, vec3 sun, float footprint_m, sampler2D map_tex, mat3 to_body, float radius, float air) {
	vec3 e = to_body * n;  // body-fixed: z = north pole, x = prime meridian
	vec2 uv = vec2(atan(e.y, e.x) / TAU + 0.5, 0.5 - asin(clamp(e.z, -1.0, 1.0)) / PI);
	// Explicit LOD from the pixel footprint: no mip seam at the date line.
	float texel_m = TAU * radius / float(textureSize(map_tex, 0).x);
	vec3 map = textureLod(map_tex, uv, max(log2(footprint_m / texel_m), 0.0)).rgb;
	vec3 srgb = pow(map, vec3(1.0 / 2.2));
	float water = smoothstep(0.06, 0.14, srgb.b - srgb.r) * step(srgb.g, srgb.b + 0.02) * air;
	// Fine detail below the map's ~20 km texels (modulates brightness only).
	float detail = fbm(e * (radius / 40000.0), 5, 40000.0, footprint_m);
	vec3 albedo = map * mix(0.8 + 0.4 * detail, 1.0, water);
	// Clouds: body-fixed noise that slowly drifts.
	vec3 cp = e * vec3(4.0, 4.0, 7.0) + vec3(37.0 + cloud_time * 2.0e-5, 11.0, cloud_time * 1.0e-5);
	float cloud = 0.0;
	if (air > 0.5) {
		// From far off (a whole planet in a few hundred pixels) only the
		// coarse octaves remain: warp them into swirls, band them by latitude
		// (cloudier ITCZ and 50–60° storm belts, clear ~25° subtropics) and
		// soften and raise the edge so the cover stays near 30 %. Up close
		// (far = 0) the clouds are unchanged.
		float far = clamp((footprint_m - 5000.0) / 20000.0, 0.0, 1.0);
		cp += far * 0.55 * vec3(gnoise(cp * 0.8), gnoise(cp * 0.8 + vec3(5.2, 1.3, 7.7)), gnoise(cp * 0.8 + vec3(9.1, 3.4, 2.6)));
		float band = far * (0.04 * cos(6.0 * asin(clamp(e.z, -1.0, 1.0))) - 0.025);
		float f = fbm(cp, 9, radius / 5.0, footprint_m) + band;
		cloud = smoothstep(0.47 + 0.04 * far, 0.62 + 0.06 * far, f);  // ≈30 % cover
	}
	albedo = mix(albedo, cloud_color, cloud * 0.9);

	float ndl = dot(n, sun);
	float day = smoothstep(-0.06, 0.1, ndl);
	vec3 col = albedo * max(ndl, 0.0) * 1.7;
	vec3 h = normalize(sun + view);
	col += vec3(1.0, 0.92, 0.8) * pow(max(dot(n, h), 0.0), 220.0) * water * (1.0 - cloud) * day * 1.5;
	// Looking obliquely through more air: haze towards the limb.
	float grazing = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);
	col = mix(col, air_color * 0.9 * day, grazing * 0.5 * air);
	return col + albedo * 0.006;  // faint night side
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
			COLOR = surface(n, -dir, sun, footprint, surface_map, pci_to_body, planet_radius, has_air);
		} else {
			vec3 col = vec3(0.0);
			// Limb glow: brightness from the ray's closest approach altitude.
			if (b < 0.0 && has_air > 0.5) {
				float r_min = sqrt(max(dot(oc, oc) - b * b, 0.0));
				float h = r_min - planet_radius;
				float top = entry_radius - planet_radius;
				if (h < top) {
					vec3 m = normalize(oc - dir * b);
					float day = smoothstep(-0.25, 0.3, dot(m, sun));
					float glow = exp(-h / air_scale_height) * (1.0 - smoothstep(top * 0.5, top, h)) * day;
					col += air_color * glow * 1.4 + vec3(0.9, 0.95, 1.0) * glow * glow * 0.5;
				}
			}
			// The far body, in units of its radius (metres would lose the
			// disc to float precision at 384,000 km).
			bool far_hit = false;
			if (far_radius > 0.0) {
				vec3 fo = (POSITION - far_center) / far_radius;
				float fb = dot(fo, dir);
				float fd = fb * fb - (dot(fo, fo) - 1.0);
				if (fd > 0.0 && -fb - sqrt(fd) > 0.0) {
					float ft = -fb - sqrt(fd);
					vec3 fn = normalize(fo + dir * ft);
					float ffoot = ft * far_radius * pixel_angle / max(dot(fn, -dir), 0.05);
					col += surface(fn, -dir, sun, ffoot, far_map, far_to_body, far_radius, far_has_air);
					far_hit = true;
				}
			}
			float d = dot(dir, sun);
			if (!far_hit) {
				col += vec3(1.0, 0.97, 0.9) * (smoothstep(0.999984, 0.999990, d) * 30.0 + pow(max(d, 0.0), 900.0) * 0.8);
			}
			COLOR = col;
		}
	}
}
