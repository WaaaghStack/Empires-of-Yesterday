shader_type canvas_item;

// R channel encodes discrete owner (see BattleTileOwnershipOverlay._owner_byte).
uniform sampler2D owner_map : filter_nearest;
uniform sampler2D friendly_pressure : filter_nearest;
uniform sampler2D hostile_pressure : filter_nearest;
uniform float frame_peak = 1.0;
uniform float interior_alpha : hint_range(0.0, 1.0) = 0.48;
uniform float front_alpha : hint_range(0.0, 1.0) = 0.98;
uniform float alpha_exponent : hint_range(0.1, 2.0) = 0.48;

const vec3 COL_BLUE = vec3(0.18, 0.55, 0.95);
const vec3 COL_RED = vec3(0.95, 0.32, 0.22);
const vec3 COL_CONTEST = vec3(1.0, 0.85, 0.35);

float owner_kind(float ow) {
	if (ow > 0.92) {
		return 3.0; // contested
	}
	if (ow > 0.62) {
		return 2.0; // hostile
	}
	if (ow > 0.32) {
		return 1.0; // friendly
	}
	if (ow > 0.08) {
		return 0.0; // neutral
	}
	return -1.0;
}

void fragment() {
	float ow = texture(owner_map, UV).r;
	float kind = owner_kind(ow);
	if (kind < -0.5) {
		COLOR = vec4(0.0);
	} else {
		vec3 col = COL_BLUE;
		float alpha = interior_alpha * 0.35;
		if (kind > 2.5) {
			col = COL_CONTEST;
			alpha = interior_alpha * 0.65;
		} else if (kind > 1.5) {
			col = COL_RED;
			alpha = interior_alpha;
		} else if (kind > 0.5) {
			col = COL_BLUE;
			alpha = interior_alpha;
		} else {
			col = mix(COL_BLUE, COL_RED, 0.5);
			alpha = interior_alpha * 0.2;
		}

		vec2 px = TEXTURE_PIXEL_SIZE;
		float ow_r = texture(owner_map, UV + vec2(px.x, 0.0)).r;
		float ow_l = texture(owner_map, UV + vec2(-px.x, 0.0)).r;
		float ow_u = texture(owner_map, UV + vec2(0.0, -px.y)).r;
		float ow_d = texture(owner_map, UV + vec2(0.0, px.y)).r;
		bool is_front = (
			abs(owner_kind(ow_r) - kind) > 0.5
			|| abs(owner_kind(ow_l) - kind) > 0.5
			|| abs(owner_kind(ow_u) - kind) > 0.5
			|| abs(owner_kind(ow_d) - kind) > 0.5
		);

		float pf = texture(friendly_pressure, UV).r;
		float ph = texture(hostile_pressure, UV).r;
		float peak = max(frame_peak, 0.001);
		float nf = pow(clamp(pf / peak, 0.0, 1.0), alpha_exponent);
		float nh = pow(clamp(ph / peak, 0.0, 1.0), alpha_exponent);
		float pglow = max(nf, nh);

		if (is_front) {
			alpha = front_alpha;
			col *= 1.32;
			if (nf > 0.08 && nh > 0.08) {
				col = COL_CONTEST;
			} else if (nh > nf) {
				col = COL_RED;
			} else {
				col = COL_BLUE;
			}
		} else if (pglow > 0.05) {
			alpha = max(alpha, pglow * 0.55);
		}

		COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
	}
}
