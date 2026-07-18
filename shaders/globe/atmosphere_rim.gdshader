shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never;

uniform vec3 atmosphere_color : source_color = vec3(0.35, 0.55, 0.95);
uniform float intensity = 0.42;
uniform float power = 2.4;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = atmosphere_color;
	ALPHA = fresnel * intensity;
}
