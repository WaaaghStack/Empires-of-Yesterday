shader_type spatial;
// Mesh vertices already include elevation (EarthGlobeMesh); height_map is shading only.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear, repeat_enable;
uniform sampler2D height_map : filter_linear, repeat_enable;
uniform float height_scale = 7.0;
uniform float ambient_boost = 0.25;
/// 0 = none, 1 = west (dim east), 2 = east (dim west). Deploy pick only.
uniform float hemisphere_mode : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	float h = texture(height_map, UV).r;
	if (h < 0.01) {
		ALBEDO *= 0.82;
	} else if (h < 0.18) {
		ALBEDO *= mix(1.12, 1.0, h / 0.18);
	} else if (h > 0.62) {
		ALBEDO *= mix(vec3(1.0), vec3(0.82, 0.88, 1.04), smoothstep(0.62, 0.92, h));
	} else {
		ALBEDO *= mix(0.96, 1.06, (h - 0.18) / 0.44);
	}
	ALBEDO = clamp(ALBEDO + vec3(ambient_boost * 0.1), 0.0, 1.0);
	if (hemisphere_mode > 0.5) {
		float east = smoothstep(0.48, 0.52, UV.x);
		float dim = (hemisphere_mode < 1.5) ? mix(1.0, 0.38, east) : mix(0.38, 1.0, east);
		ALBEDO *= dim;
	}

	float land_factor = step(0.01, h);
	ROUGHNESS = mix(0.92, 0.55, land_factor * (1.0 - h * 0.3));
	if (h < 0.01) {
		ROUGHNESS = 0.35;
	}
}
