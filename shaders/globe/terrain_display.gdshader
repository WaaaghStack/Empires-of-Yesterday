shader_type spatial;
// Mesh vertices already include elevation (EarthGlobeMesh); height_map is shading only.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear, repeat_enable;
uniform sampler2D height_map : filter_linear, repeat_enable;
uniform float height_scale = 7.0;
uniform float ambient_boost = 0.25;

void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	float h = texture(height_map, UV).r;
	ALBEDO *= mix(0.88, 1.08, h);
	ALBEDO = clamp(ALBEDO + vec3(ambient_boost * 0.1), 0.0, 1.0);

	float land_factor = step(0.01, h);
	ROUGHNESS = mix(0.92, 0.55, land_factor * (1.0 - h * 0.3));
	if (h < 0.01) {
		ROUGHNESS = 0.35;
	}
}
