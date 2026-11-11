// Procedural cloud shell (spec: docs/specs/earth-milestone-2-clouds.md, REQ-5, REQ-6, REQ-8, REQ-11 to REQ-14).
// Opacity is 3D value noise (fBm) sampled from the Earth-fixed direction; UV is never read.
shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled, ambient_light_disabled;

uniform float coverage : hint_range(0.0, 1.0) = 0.55;
uniform float density : hint_range(0.0, 1.0) = 1.0;
// Maximum alpha at density 1 (REQ-4).
uniform float cap = 0.85;
// Noise cells per unit-sphere radius: sets the cloud size.
uniform float frequency = 4.0;
// Drift about Earth-fixed +z, radians, eastward positive (set by cloud_layer.gd from the streamed UTC).
uniform float drift_rad = 0.0;
// Shape change along the time axis: integer time cell (exact in float32) and the fraction inside it.
uniform float time_cell = 0.0;
uniform float time_frac = 0.0;
// Logistic scale that turns the noise value into an approximately uniform rank (calibrated per layer).
uniform float spread = 0.13;
// Width of the soft edge in rank units.
uniform float softness = 0.25;

varying vec3 mesh_dir;

void vertex() {
	mesh_dir = VERTEX;
}

vec3 hash3(ivec3 c, uint salt) {
	uvec3 v = uvec3(c) * 1664525u + 1013904223u + uvec3(salt);
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return vec3(v) * 2.3283064e-10;
}

float vnoise(vec3 p, uint salt) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	ivec3 c = ivec3(i);
	float x00 = mix(hash3(c, salt).x, hash3(c + ivec3(1, 0, 0), salt).x, f.x);
	float x10 = mix(hash3(c + ivec3(0, 1, 0), salt).x, hash3(c + ivec3(1, 1, 0), salt).x, f.x);
	float x01 = mix(hash3(c + ivec3(0, 0, 1), salt).x, hash3(c + ivec3(1, 0, 1), salt).x, f.x);
	float x11 = mix(hash3(c + ivec3(0, 1, 1), salt).x, hash3(c + ivec3(1, 1, 1), salt).x, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 1.0;
	for (int k = 0; k < 4; k++) {
		sum += amp * (vnoise(p, 7u) - 0.5);
		p = p * 2.03 + vec3(17.1, 31.7, 5.3);
		amp *= 0.5;
	}
	return sum;
}

vec3 time_offset(float cell) {
	return hash3(ivec3(int(cell), 11, 23), 99u) * 64.0;
}

void fragment() {
	vec3 m = normalize(mesh_dir);
	// Mesh frame (pole +Y) to Earth-fixed frame (pole +z): the fixed rotation of EarthSurface in main.tscn.
	vec3 ef = vec3(-m.z, -m.x, m.y);
	float c = cos(drift_rad);
	float s = sin(drift_rad);
	vec3 p = vec3(c * ef.x + s * ef.y, -s * ef.x + c * ef.y, ef.z) * frequency;
	float a = cos(1.5707963 * time_frac);
	float b = sin(1.5707963 * time_frac);
	// Cross-fade of two independent noise fields keeps the variance (a^2 + b^2 = 1).
	float n = a * fbm(p + time_offset(time_cell)) + b * fbm(p + time_offset(time_cell + 1.0));
	float u = 1.0 / (1.0 + exp(-clamp(n / spread, -30.0, 30.0)));
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	// The threshold sits 0.05 softness below 1 - coverage so that alpha > 0.05 cap on a fraction equal to coverage.
	float edge = (u - (1.0 - clamp(coverage, 0.0, 1.0)) + 0.05 * softness) / softness;
	ALPHA = cap * clamp(density, 0.0, 1.0) * clamp(edge, 0.0, 1.0) * step(0.001, coverage);
}
