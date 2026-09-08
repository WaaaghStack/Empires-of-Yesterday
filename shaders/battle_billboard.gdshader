// Y-axis (cylindrical) billboard for MultiMesh unit sprites.
// Keeps world-up so 8-way facing / left-right flip reads on a free camera.
// Transform = position + scale.
// INSTANCE_CUSTOM.x = frame * 2 + flip (0/1). Bombers stay frame 0 (just flip).
// INSTANCE_CUSTOM.y = 0 idle, brief hit flash (~0.28–0.60), >0.65 unused muzzle tint
// INSTANCE_CUSTOM.z = corpse
// INSTANCE_CUSTOM.w = fade (1 visible, 0 fled)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, blend_mix;

uniform sampler2D tex : source_color, filter_nearest;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.35;
uniform float sheet_cols = 1.0;
uniform float sheet_rows = 1.0;

varying vec2 v_uv;
varying float v_fire;
varying float v_dead;
varying float v_fade;

void vertex() {
	int packed = int(INSTANCE_CUSTOM.x + 0.5);
	int flip_bit = packed % 2;
	int frame = packed / 2;
	int cols = max(int(sheet_cols + 0.5), 1);
	int rows = max(int(sheet_rows + 0.5), 1);
	int col = frame % cols;
	int row = (frame / cols) % rows;
	vec2 cell = vec2(1.0 / float(cols), 1.0 / float(rows));
	vec2 local = UV;
	if (flip_bit == 1) {
		local.x = 1.0 - UV.x;
	}
	v_uv = vec2(float(col), float(row)) * cell + local * cell;
	v_fire = INSTANCE_CUSTOM.y;
	v_dead = INSTANCE_CUSTOM.z;
	v_fade = INSTANCE_CUSTOM.w;
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
	vec3 up = vec3(0.0, 1.0, 0.0);
	mat4 cyl = mat4(
		vec4(right, 0.0),
		vec4(up, 0.0),
		vec4(fwd, 0.0),
		vec4(origin, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * cyl * mat4(
		vec4(sx, 0.0, 0.0, 0.0),
		vec4(0.0, sy, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
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
	} else if (v_fire > 0.65) {
		rgb = mix(rgb, vec3(1.0, 0.86, 0.32), 0.48);
	} else if (v_fire > 0.2) {
		rgb = mix(rgb, vec3(1.0, 0.38, 0.22), 0.32);
	}
	ALBEDO = rgb;
	ALPHA = c.a * v_fade;
}
