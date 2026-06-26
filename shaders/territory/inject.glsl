#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict image2D pressure_f;
layout(set = 0, binding = 1, r32f) uniform restrict image2D pressure_h;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D claimable;

layout(set = 1, binding = 0, std140) uniform Params {
	float friendly_rate;
	float hostile_rate;
	int player_home_x;
	int player_home_y;
	int enemy_home_x;
	int enemy_home_y;
	int map_w;
	int map_h;
	int inject_count;
	int inject_round;
	int pressure_inject_interval;
} params;

layout(set = 1, binding = 1, std430) readonly buffer InjectPoints {
	ivec3 points[]; // x, y, team (1=friendly 2=hostile)
};

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= params.map_w || gid.y >= params.map_h) {
		return;
	}
	if (imageLoad(claimable, gid).r < 0.5) {
		return;
	}
	bool inject_tick = params.pressure_inject_interval <= 1
		|| ((params.inject_round - 1) % params.pressure_inject_interval) == 0;
	if (inject_tick) {
		for (int i = 0; i < params.inject_count; i++) {
			ivec3 pt = points[i];
			if (pt.x == gid.x && pt.y == gid.y) {
				if (pt.z == 1) {
					float p = imageLoad(pressure_f, gid).r;
					imageStore(pressure_f, gid, vec4(p + params.friendly_rate, 0.0, 0.0, 0.0));
				} else if (pt.z == 2) {
					float p = imageLoad(pressure_h, gid).r;
					imageStore(pressure_h, gid, vec4(p + params.hostile_rate, 0.0, 0.0, 0.0));
				}
			}
		}
		if (gid.x == params.player_home_x && gid.y == params.player_home_y) {
			float p = imageLoad(pressure_f, gid).r;
			imageStore(pressure_f, gid, vec4(p + params.friendly_rate, 0.0, 0.0, 0.0));
		}
		if (gid.x == params.enemy_home_x && gid.y == params.enemy_home_y) {
			float p = imageLoad(pressure_h, gid).r;
			imageStore(pressure_h, gid, vec4(p + params.hostile_rate, 0.0, 0.0, 0.0));
		}
	}
}
