// Lunar surface: Lommel-Seeliger reflectance with the offline ENU normal map
// (spec: docs/specs/visual-quality-milestone-3.md, REQ-1 to REQ-3 and REQ-16).
shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

uniform sampler2D albedo_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : filter_linear_mipmap, repeat_enable;
// Set by moon.gd only when the PNG matches moon_data.json (REQ-17).
uniform bool use_normal_map = false;
// Added to VERTEX for nodes whose vertices are stored relative to their own centre (D6); 0 for the Moon chunks.
instance uniform vec3 moon_offset = vec3(0.0);
// Geomorph weight (REQ-30): 0 = the node's own height, 1 = the parent-interpolated height (CUSTOM0 holds the
// position difference). Set per quadtree node by terrain_quadtree.gd; 0 for the M2 root chunks.
instance uniform float morph = 0.0;

// Position in the Moon's frame (the chunks sit at the Moon node's origin).
varying vec3 moon_pos;
// Position in metres relative to the chunk's own origin (REQ-24): float32-exact to well under 0.1 mm for
// chunks up to a few hundred metres across. Only used within 20 m of the camera.
varying vec3 local_m;

// 3D value noise on an integer hash, in [-1, 1]. Cells are (cell) metres wide.
float hash13(uvec3 p) {
	p = p * uvec3(1597334673u, 3812015801u, 2798796415u);
	uint h = (p.x ^ p.y ^ p.z) * 1597334673u;
	h ^= h >> 15u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h) * (2.0 / 4294967295.0) - 1.0;
}

vec3 hash33(uvec3 p) {
	return vec3(hash13(p), hash13(p + uvec3(101u, 17u, 5u)), hash13(p + uvec3(31u, 211u, 71u)));
}

// Smooth noise with cells of `cell` metres (negative cell indices wrap through int to uint).
float vnoise(vec3 x, float cell) {
	vec3 q = x / cell;
	vec3 i = floor(q);
	vec3 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	uvec3 u = uvec3(ivec3(i));
	float r = 0.0;
	for (int k = 0; k < 8; k++) {
		uvec3 o = uvec3(uint(k & 1), uint((k >> 1) & 1), uint((k >> 2) & 1));
		vec3 w = mix(1.0 - f, f, vec3(o));
		r += w.x * w.y * w.z * hash13(u + o);
	}
	return r;
}

vec3 vnoise3(vec3 x, float cell) {
	vec3 q = x / cell;
	vec3 i = floor(q);
	vec3 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	uvec3 u = uvec3(ivec3(i));
	vec3 r = vec3(0.0);
	for (int k = 0; k < 8; k++) {
		uvec3 o = uvec3(uint(k & 1), uint((k >> 1) & 1), uint((k >> 2) & 1));
		vec3 w = mix(1.0 - f, f, vec3(o));
		r += w.x * w.y * w.z * hash33(u + o);
	}
	return r;
}

void vertex() {
	if (morph != 0.0) {
		VERTEX += CUSTOM0.xyz * morph;
	}
	moon_pos = VERTEX + moon_offset;
	local_m = VERTEX * 1000.0;
}

void fragment() {
	// Distance to the camera in metres (VERTEX is in view space, 1 unit = 1 km).
	float dist_m = length(VERTEX) * 1000.0;
	vec3 albedo = texture(albedo_texture, UV).rgb;
	// D8 / REQ-22: multiplicative detail albedo, at most +-5 %, zero-mean noise with cells of 0.1 m and 0.03 m
	// (the mean over any 1 m patch is within 0.01 of 1), faded out by 200 m to avoid shimmer.
	if (dist_m < 200.0) {
		float a = 0.6 * vnoise(local_m, 0.1) + 0.4 * vnoise(local_m + 7.3, 0.03);
		albedo *= 1.0 + 0.05 * clamp(a, -1.0, 1.0) * (1.0 - smoothstep(100.0, 200.0, dist_m));
	}
	ALBEDO = albedo;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	vec3 up = normalize(moon_pos);
	float cos_lat = length(up.xz);
	// At a pole the ENU basis is undefined: keep the interpolated vertex normal.
	if (use_normal_map && cos_lat >= 1e-6) {
		vec3 east = vec3(up.z, 0.0, -up.x) / cos_lat;
		vec3 north = cross(up, east);
		vec3 enu = normalize(texture(normal_texture, UV).rgb * 2.0 - 1.0);
		vec3 n_moon = enu.x * east + enu.y * north + enu.z * up;
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(n_moon, 0.0)).xyz);
	}
	// REQ-24: grain normal, wavelengths 1 mm to 2 cm, faded to zero by 20 m. A vector-noise bump added to
	// the normal in view space; no texture is sampled.
	float grain_fade = 1.0 - smoothstep(8.0, 20.0, dist_m);
	if (grain_fade > 0.0) {
		vec3 g = 0.5 * vnoise3(local_m, 0.01) + 0.3 * vnoise3(local_m + 3.1, 0.004) + 0.2 * vnoise3(local_m + 9.7, 0.0015);
		vec3 bump = (VIEW_MATRIX * MODEL_MATRIX * vec4(g, 0.0)).xyz;
		bump -= dot(bump, NORMAL) * NORMAL;
		NORMAL = normalize(NORMAL + 0.5 * grain_fade * bump);
	}
}

void light() {
	float cos_i = dot(NORMAL, LIGHT);
	float cos_e = dot(NORMAL, VIEW);
	if (cos_i > 0.0 && cos_e > 0.0) {
		// Divided by PI as in Godot's own Lambert term, so the law equals Lambert at i = e = 0.
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (2.0 * cos_i / (cos_i + cos_e)) / PI;
	}
}
