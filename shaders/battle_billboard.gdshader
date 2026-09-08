// Camera-facing billboard for MultiMesh unit sprites (HD-2D battle viewer).
// Transform = position + scale.
// INSTANCE_CUSTOM.x = left-facing flip, .y = firing, .z = corpse, .w = fade (1 visible, 0 fled).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, blend_mix;

uniform sampler2D tex : source_color, filter_nearest;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.35;

varying vec2 v_uv;
varying float v_fire;
varying float v_dead;
varying float v_fade;

void vertex() {
	v_uv = UV;
	if (INSTANCE_CUSTOM.x > 0.5) {
		v_uv.x = 1.0 - UV.x;
	}
	v_fire = INSTANCE_CUSTOM.y;
	v_dead = INSTANCE_CUSTOM.z;
	v_fade = INSTANCE_CUSTOM.w;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mat4 mv = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
	mv = mv * mat4(
		vec4(sx, 0.0, 0.0, 0.0),
		vec4(0.0, sy, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	if (v_fade < 0.02) {
		discard;
	}
	vec4 c = texture(tex, v_uv);
	if (c.a < alpha_threshold) {
		discard;
	}
	vec3 rgb = c.rgb;
	if (v_dead > 0.5) {
		rgb *= 0.42;
	} else if (v_fade < 0.999) {
		rgb = mix(rgb, vec3(0.72, 0.90, 1.0), 1.0 - v_fade);
	} else if (v_fire > 0.5) {
		rgb = mix(rgb, vec3(1.0, 0.82, 0.32), 0.38);
	}
	ALBEDO = rgb;
	ALPHA = c.a * v_fade;
}
