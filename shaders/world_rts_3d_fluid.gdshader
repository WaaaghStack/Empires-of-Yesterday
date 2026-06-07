shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D owner_map : filter_nearest, repeat_disable;
uniform sampler2D friendly_pressure : filter_nearest, repeat_disable;
uniform sampler2D hostile_pressure : filter_nearest, repeat_disable;
uniform float frame_peak = 10000.0;
uniform float interior_alpha : hint_range(0.0, 1.0) = 0.72;
uniform float front_alpha : hint_range(0.0, 1.0) = 0.98;
uniform float alpha_exponent : hint_range(0.1, 2.0) = 0.48;

const vec3 COL_BLUE = vec3(0.18, 0.55, 0.95);
const vec3 COL_RED = vec3(0.95, 0.32, 0.22);
const vec3 COL_CONTEST = vec3(1.0, 0.85, 0.35);

float owner_kind(float ow) {
	if (ow > 0.92) {
		return 3.0;
	}
	if (ow > 0.62) {
		return 2.0;
	}
	if (ow > 0.32) {
		return 1.0;
	}
	if (ow > 0.08) {
		return 0.0;
	}
	return -1.0;
}

void fragment() {
	vec2 uv = UV;
	float ow = texture(owner_map, uv).r;
	float kind = owner_kind(ow);
	vec4 out_col = vec4(0.0);
	if (kind >= -0.5) {
		vec3 col = COL_BLUE;
		float alpha = interior_alpha * 0.4;
		if (kind > 2.5) {
			col = COL_CONTEST;
			alpha = interior_alpha * 0.75;
		} else if (kind > 1.5) {
			col = COL_RED;
			alpha = interior_alpha;
		} else if (kind > 0.5) {
			col = COL_BLUE;
			alpha = interior_alpha;
		} else {
			col = mix(COL_BLUE, COL_RED, 0.5);
			alpha = interior_alpha * 0.25;
		}
		vec2 px = vec2(1.0) / vec2(textureSize(owner_map, 0));
		float ow_r = texture(owner_map, uv + vec2(px.x, 0.0)).r;
		float ow_l = texture(owner_map, uv + vec2(-px.x, 0.0)).r;
		float ow_u = texture(owner_map, uv + vec2(0.0, px.y)).r;
		float ow_d = texture(owner_map, uv + vec2(0.0, -px.y)).r;
		bool is_front = (
			abs(owner_kind(ow_r) - kind) > 0.5
			|| abs(owner_kind(ow_l) - kind) > 0.5
			|| abs(owner_kind(ow_u) - kind) > 0.5
			|| abs(owner_kind(ow_d) - kind) > 0.5
		);
		float pf = texture(friendly_pressure, uv).r;
		float ph = texture(hostile_pressure, uv).r;
		float peak = max(frame_peak, 1.0);
		float nf = pow(clamp(pf / peak, 0.0, 1.0), alpha_exponent);
		float nh = pow(clamp(ph / peak, 0.0, 1.0), alpha_exponent);
		float pglow = max(nf, nh);
		if (is_front) {
			alpha = front_alpha;
			col *= 1.35;
			if (nf > 0.04 && ph > 0.04) {
				col = COL_CONTEST;
			} else if (nh > nf) {
				col = COL_RED;
			} else {
				col = COL_BLUE;
			}
		} else if (pglow > 0.02) {
			alpha = max(alpha, pglow * 0.65);
			if (nf > nh) {
				col = mix(col, COL_BLUE, clamp(nf * 1.2, 0.0, 1.0));
			} else if (nh > nf) {
				col = mix(col, COL_RED, clamp(nh * 1.2, 0.0, 1.0));
			}
		}
		out_col = vec4(col, clamp(alpha, 0.0, 1.0));
	}
	ALBEDO = out_col.rgb;
	ALPHA = out_col.a;
	EMISSION = out_col.rgb * out_col.a * 0.4;
}
