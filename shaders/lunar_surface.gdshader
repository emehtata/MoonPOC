// Lunar surface: Lommel-Seeliger reflectance with the offline ENU normal map
// (spec: docs/specs/visual-quality-milestone-3.md, REQ-1 to REQ-3 and REQ-16).
shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : filter_linear_mipmap, repeat_enable;
// Set by moon.gd only when the PNG matches moon_data.json (REQ-17).
uniform bool use_normal_map = false;

// Position in the Moon's frame (the chunks sit at the Moon node's origin).
varying vec3 moon_pos;

void vertex() {
	moon_pos = VERTEX;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
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
}

void light() {
	float cos_i = dot(NORMAL, LIGHT);
	float cos_e = dot(NORMAL, VIEW);
	if (cos_i > 0.0 && cos_e > 0.0) {
		// Divided by PI as in Godot's own Lambert term, so the law equals Lambert at i = e = 0.
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (2.0 * cos_i / (cos_i + cos_e)) / PI;
	}
}
