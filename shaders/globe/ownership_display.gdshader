shader_type spatial;
// Opaque overlay: avoids expensive alpha fill-rate on large owned regions.
render_mode unshaded, cull_back;

uniform sampler2D owner_map : filter_nearest, repeat_enable;
uniform sampler2D border_map : filter_nearest, repeat_enable;
uniform sampler2D land_mask : filter_nearest, repeat_enable;
uniform float interior_alpha : hint_range(0.0, 1.0) = 0.58;
uniform float border_alpha : hint_range(0.0, 1.0) = 1.0;

const vec3 COL_FRIENDLY = vec3(0.18, 0.55, 0.95);
const vec3 COL_HOSTILE = vec3(0.95, 0.32, 0.22);
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

vec3 base_color(float kind) {
	if (kind > 2.5) {
		return COL_CONTEST;
	}
	if (kind > 1.5) {
		return COL_HOSTILE;
	}
	if (kind > 0.5) {
		return COL_FRIENDLY;
	}
	return vec3(0.0);
}

vec3 border_color(float kind, vec3 base) {
	if (kind > 2.5) {
		return mix(base, vec3(1.0, 0.95, 0.7), 0.22) * 1.45;
	}
	if (kind > 1.5) {
		return mix(base, vec3(1.0, 0.85, 0.8), 0.18) * 1.55;
	}
	if (kind > 0.5) {
		return mix(base, vec3(0.85, 0.95, 1.0), 0.2) * 1.55;
	}
	return base;
}

void fragment() {
	if (texture(land_mask, UV).r < 0.5) {
		discard;
	}
	float ow = texture(owner_map, UV).r;
	float kind = owner_kind(ow);
	if (kind < 0.5) {
		discard;
	}

	vec3 col = base_color(kind);
	bool is_border = texture(border_map, UV).r > 0.5;

	if (is_border) {
		ALBEDO = border_color(kind, col);
	} else {
		ALBEDO = col;
	}
	ALPHA = 1.0;
}