shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;

uniform vec3 color : source_color = vec3(1.0, 0.92, 0.45);
uniform sampler2D streak : source_color, filter_nearest;
uniform float cutoff : hint_range(0.0, 1.0) = 0.2;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec4 sheet = texture(streak, v_uv);
	if (sheet.a >= cutoff) {
		ALBEDO = sheet.rgb;
		ALPHA = sheet.a;
	} else {
		// No sheet (or empty texel): a thin core only, never the whole quad.
		float edge = 1.0 - abs(v_uv.y - 0.5) * 2.0;
		if (edge < 0.72) {
			discard;
		}
		ALBEDO = color;
		ALPHA = edge;
	}
}
