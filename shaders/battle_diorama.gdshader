shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform vec3 grass : source_color = vec3(0.23, 0.34, 0.16);
uniform vec3 dirt : source_color = vec3(0.34, 0.26, 0.14);
uniform vec3 river : source_color = vec3(0.16, 0.28, 0.34);
uniform vec3 rock : source_color = vec3(0.38, 0.36, 0.32);
uniform float width = 200.0;
uniform float height = 120.0;
uniform float elevation = 30.0;
uniform float river_x = 100.0;
uniform float hill_x = 52.0;
uniform float hill_y = 92.0;
uniform float hill_r = 28.0;

void fragment() {
	vec2 world_xz = (UV - vec2(0.5)) * vec2(width * 1.35, height * 1.7);
	float bx = world_xz.x + width * 0.5;
	float by = world_xz.y + height * 0.5;
	float nx = abs(bx - river_x);
	vec3 albedo = mix(grass, dirt, smoothstep(22.0, 7.0, nx));
	if (nx < 5.5) {
		albedo = mix(albedo, river, 0.72);
	}
	float hd = length(vec2(bx - hill_x, by - hill_y));
	if (hd < hill_r) {
		float k = 1.0 - clamp(hd / hill_r, 0.0, 1.0);
		albedo = mix(albedo, rock, k * 0.55);
	}
	float road = abs(by - height * 0.5);
	if (road < 2.2 && nx > 6.0) {
		albedo = mix(albedo, dirt * 0.78, 0.7);
	}
	float elev_k = clamp(elevation / 100.0, 0.0, 1.0);
	albedo = mix(albedo, rock, elev_k * 0.18);
	ALBEDO = albedo;
	ROUGHNESS = 0.92;
	SPECULAR = 0.0;
}
