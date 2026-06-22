shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_test_disabled;

uniform sampler2D pressure_friendly : filter_nearest, repeat_enable;
uniform sampler2D pressure_hostile : filter_nearest, repeat_enable;
uniform sampler2D land_mask : filter_nearest, repeat_enable;
uniform float frame_peak = 10000.0;
uniform float power_scale = 1.0;

const vec3 COL_FRIENDLY = vec3(0.18, 0.55, 0.95);
const vec3 COL_HOSTILE = vec3(0.95, 0.32, 0.22);
const vec3 COL_TIE = vec3(1.0, 0.85, 0.35);

void fragment() {
	if (texture(land_mask, UV).r < 0.5) {
		discard;
	}
	float pf = texture(pressure_friendly, UV).r;
	float ph = texture(pressure_hostile, UV).r;
	float peak = max(pf, ph);
	if (peak < 0.01) {
		discard;
	}
	float ref_peak = max(frame_peak, 0.001);
	float norm = clamp(peak / ref_peak, 0.0, 1.0);
	float intensity = pow(norm, 0.65) * clamp(power_scale, 0.01, 1.0);
	intensity = clamp(intensity, 0.22, 1.0);
	vec3 col;
	float alpha;
	if (pf > ph) {
		col = COL_FRIENDLY;
	} else if (ph > pf) {
		col = COL_HOSTILE;
	} else {
		col = COL_TIE;
	}
	// Boost at local dominance (front line read).
	float dom = abs(pf - ph) / max(peak, 0.001);
	alpha = mix(0.5, 1.0, dom) * intensity;
	ALBEDO = col * mix(1.0, 1.35, dom);
	ALPHA = alpha;
}
