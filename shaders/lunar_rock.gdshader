// Rock material (spec lunar-surface-procedural REQ-21, REQ-23): same Lommel-Seeliger law as the regolith, no
// specular, no ambient. Albedo = the local texture albedo x a per-rock factor in [1.0, 1.3]; it blends back to
// the plain regolith albedo at the ground contact.
// Per-instance custom data: x = albedo factor, y/z = texture UV of the rock, w = floor(height in mm) + sink.
shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

uniform sampler2D albedo_texture : filter_linear_mipmap_anisotropic, repeat_enable;
// Moon node position in world space (= -floating origin), set by near_world.gd.
uniform vec3 moon_centre = vec3(0.0);

varying flat vec3 rock_albedo_factor;
varying flat vec2 rock_uv;
varying float contact_blend;

void vertex() {
	float height_mm = floor(INSTANCE_CUSTOM.w);
	float sink = INSTANCE_CUSTOM.w - height_mm;
	vec3 up = normalize(MODEL_MATRIX[3].xyz - moon_centre);
	// Height above the rock's lowest point in units of its height. shortcut: the lowest point is taken at
	// half a height below the mesh origin (bounding-box centre), exact only for an upright rock; upgrade by
	// passing the true lowest vertex height per instance.
	float frac = dot((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz, up) * 1e6 / max(height_mm, 1.0) + 0.5;
	contact_blend = smoothstep(sink, sink + 0.1, frac);
	rock_albedo_factor = vec3(INSTANCE_CUSTOM.x);
	rock_uv = INSTANCE_CUSTOM.yz;
}

void fragment() {
	vec3 regolith = texture(albedo_texture, rock_uv).rgb;
	ALBEDO = regolith * mix(1.0, rock_albedo_factor.x, contact_blend);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float cos_i = dot(NORMAL, LIGHT);
	float cos_e = dot(NORMAL, VIEW);
	if (cos_i > 0.0 && cos_e > 0.0) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (2.0 * cos_i / (cos_i + cos_e)) / PI;
	}
}
