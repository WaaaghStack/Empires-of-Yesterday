// Camera-facing billboard for MultiMesh unit sprites (HD-2D battle viewer).
// Each instance transform carries a world position + uniform scale; this shader rebuilds the
// model-view basis to face the camera (spherical billboard) so thousands of instanced quads render
// as upright sprites in one draw call. Unshaded + alpha-discard for crisp pixel-art sprites.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	// Keep instance translation (MODEL_MATRIX[3]) but take the rotation basis from the camera
	// (INV_VIEW_MATRIX), then reapply the instance's uniform scale.
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
	vec4 c = texture(tex, UV);
	if (c.a < alpha_threshold) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
