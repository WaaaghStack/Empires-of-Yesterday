shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D land_mask : filter_linear, repeat_enable;
uniform float land_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float mountain_bias : hint_range(-1.0, 1.0) = 0.0;
uniform float resource_density : hint_range(0.25, 2.0) = 1.0;
/// 0 = Earth mask, 1 = Pangea-style noise, 2 = Archipelago-style noise.
uniform float theater_mode : hint_range(0.0, 2.0) = 0.0;
/// 0 = none, 1 = west (dim east), 2 = east (dim west).
uniform float meridian_mode : hint_range(0.0, 2.0) = 0.0;
uniform vec3 ocean_col = vec3(0.05, 0.18, 0.42);
uniform vec3 land_col = vec3(0.34, 0.52, 0.28);
uniform vec3 mountain_col = vec3(0.48, 0.44, 0.38);
uniform vec3 sand_col = vec3(0.72, 0.64, 0.38);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise21(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float land;
	if (theater_mode < 0.5) {
		land = texture(land_mask, uv).r;
		land = step(0.42 - land_bias * 0.22, land);
	} else {
		float n = fbm(uv * vec2(6.0, 3.2) + vec2(1.7, 0.4));
		float thresh = 0.52 - land_bias * 0.28;
		if (theater_mode > 1.5) {
			thresh = 0.62 - land_bias * 0.22;
		}
		land = step(thresh, n);
	}
	float elev = fbm(uv * vec2(14.0, 7.0) + 3.1) * 0.65 + mountain_bias * 0.25;
	vec3 col = ocean_col;
	if (land > 0.5) {
		float shelf = (theater_mode > 0.5)
			? smoothstep(0.35, 0.55, elev)
			: smoothstep(0.42, 0.52, texture(land_mask, uv).r);
		col = mix(sand_col * 1.12, land_col, 0.62 + shelf * 0.2);
		if (elev > 0.58) {
			col = mix(col, mountain_col * vec3(0.82, 0.88, 1.02), clamp((elev - 0.58) * 3.2, 0.0, 1.0));
		}
		float sparkle = step(1.0 - clamp(resource_density * 0.08, 0.02, 0.18), hash21(floor(uv * vec2(90.0, 45.0))));
		col = mix(col, vec3(0.98, 0.86, 0.22), sparkle * 0.85);
	} else {
		float deep = 0.72 + 0.22 * fbm(uv * 3.0);
		col *= deep;
	}
	if (meridian_mode > 0.5) {
		float east = smoothstep(0.48, 0.52, uv.x);
		float dim = (meridian_mode < 1.5) ? mix(1.0, 0.38, east) : mix(0.38, 1.0, east);
		col *= dim;
		float line = 1.0 - smoothstep(0.0, 0.0035, abs(uv.x - 0.5));
		col = mix(col, vec3(0.92, 0.90, 0.78), line * 0.85);
	}
	float rim = pow(1.0 - abs(NORMAL.z), 2.4);
	col += vec3(0.12, 0.22, 0.38) * rim * 0.35;
	ALBEDO = col;
	ALPHA = 1.0;
}
