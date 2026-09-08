// Camera-up billboard for muzzle / spark / bomb sheets. Empty PNG pixels are discarded
// so the quad never shows as a cardboard card.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_never;

uniform sampler2D tex : source_color, filter_nearest;
uniform float cutoff : hint_range(0.0, 1.0) = 0.2;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	if (length(to_cam) < 0.001) {
		to_cam = vec3(0.0, 0.0, 1.0);
	}
	vec3 fwd = normalize(to_cam);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	mat4 cyl = mat4(
		vec4(right, 0.0),
		vec4(vec3(0.0, 1.0, 0.0), 0.0),
		vec4(fwd, 0.0),
		vec4(origin, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * cyl * mat4(
		vec4(sx, 0.0, 0.0, 0.0),
		vec4(0.0, sy, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 c = texture(tex, v_uv);
	if (c.a < cutoff) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
