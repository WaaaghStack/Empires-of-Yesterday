## res://shaders/globe/road_ribbon.gdshader
shader_type spatial;
// Flat road ribbon: instance COLOR drives black | white | black lanes.
render_mode unshaded, cull_disabled, depth_draw_opaque;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
}
