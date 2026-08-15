shader_type spatial;
// Opaque overlay on land shell; depth-tested so far-side borders do not punch through ocean.
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D owner_map : filter_nearest, repeat_enable;
uniform sampler2D border_map : filter_nearest, repeat_enable;
uniform sampler2D depth_map : filter_nearest, repeat_enable;
uniform sampler2D land_mask : filter_nearest, repeat_enable;
uniform sampler2D road_map : filter_nearest, repeat_enable;
uniform sampler2D paint_map : filter_nearest, repeat_enable;
uniform float interior_alpha : hint_range(0.0, 1.0) = 0.58;
uniform float border_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float inspect_boost : hint_range(0.0, 1.0) = 0.0;

const vec3 COL_FRIENDLY = vec3(0.18, 0.55, 0.95);
const vec3 COL_HOSTILE = vec3(0.95, 0.32, 0.22);
const vec3 COL_CONTEST = vec3(1.0, 0.85, 0.35);
const vec3 COL_ROAD_SHOULDER = vec3(0.06, 0.06, 0.07);
const vec3 COL_ROAD_SHOULDER_PLANNED = vec3(0.16, 0.16, 0.17);
const vec3 COL_ROAD_CENTER = vec3(0.92, 0.92, 0.94);
const vec3 COL_ROAD_CENTER_PLANNED = vec3(0.55, 0.55, 0.58);
const vec3 COL_ROAD_BRIDGE = vec3(0.88, 0.90, 0.95);

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

// Center = white, shoulders = black. Planned variants are dimmer.
vec3 road_color(float rw) {
	if (rw > 0.70) {
		return COL_ROAD_CENTER;
	}
	if (rw > 0.32) {
		return COL_ROAD_CENTER_PLANNED;
	}
	if (rw > 0.22) {
		return COL_ROAD_SHOULDER;
	}
	if (rw > 0.10) {
		return COL_ROAD_SHOULDER_PLANNED;
	}
	return vec3(0.0);
}

float road_mix(float rw) {
	if (rw > 0.70) {
		return 0.98;
	}
	if (rw > 0.32) {
		return 0.85;
	}
	if (rw > 0.22) {
		return 0.95;
	}
	if (rw > 0.10) {
		return 0.70;
	}
	return 0.0;
}

void fragment() {
	// Ownership overlay only — roads are MultiMesh ribbons (not equirect paint).
	if (texture(land_mask, UV).r < 0.5) {
		discard;
	}
	float ow = texture(owner_map, UV).r;
	float kind = owner_kind(ow);
	float paint = texture(paint_map, UV).r;
	bool painted = paint > 0.05;
	if (kind < 0.5 && !painted) {
		discard;
	}

	vec3 col = base_color(kind);
	bool is_border = texture(border_map, UV).r > 0.5;
	if (kind >= 0.5) {
		if (is_border) {
			ALBEDO = border_color(kind, col);
		} else {
			float depth = texture(depth_map, UV).r;
			if (depth < 0.01) {
				depth = 0.7;
			}
			float tint = mix(0.55, 1.15, depth);
			float boost = mix(1.0, 1.38, inspect_boost);
			ALBEDO = col * tint * boost;
		}
	} else {
		ALBEDO = vec3(0.0);
	}
	if (painted) {
		vec2 px = vec2(1.0) / vec2(textureSize(paint_map, 0));
		float n0 = texture(paint_map, UV + vec2(px.x, 0.0)).r;
		float n1 = texture(paint_map, UV - vec2(px.x, 0.0)).r;
		float n2 = texture(paint_map, UV + vec2(0.0, px.y)).r;
		float n3 = texture(paint_map, UV - vec2(0.0, px.y)).r;
		float edge = max(max(abs(paint - n0), abs(paint - n1)), max(abs(paint - n2), abs(paint - n3)));
		float dash = step(0.42, fract(UV.x * 64.0 + UV.y * 32.0 + TIME * 0.45));
		float pulse = 0.55 + 0.45 * sin(TIME * 3.2);
		vec3 glow = mix(vec3(0.95, 0.92, 0.72), vec3(0.22, 0.95, 0.82), 0.4) * pulse;
		glow = mix(glow, vec3(0.95, 0.95, 0.88), dash * 0.4);
		float stroke = smoothstep(0.04, 0.18, edge);
		if (kind < 0.5) {
			if (stroke < 0.12) {
				discard;
			}
			ALBEDO = glow * stroke;
		} else {
			ALBEDO = mix(ALBEDO, glow, stroke * 0.72);
		}
	}
	ALPHA = 1.0;
}
