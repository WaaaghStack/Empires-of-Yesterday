#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict readonly image2D pressure_f;
layout(set = 0, binding = 1, r32f) uniform restrict readonly image2D pressure_h;
layout(set = 0, binding = 2, r32f) uniform restrict readonly image2D claim_mult;
layout(set = 0, binding = 3, r8) uniform restrict writeonly image2D owner_out;
layout(set = 0, binding = 4, r8) uniform restrict readonly image2D claimable;

layout(set = 1, binding = 0, std140) uniform Params {
	float min_claim_pressure;
	float dominance_ratio;
	int player_home_x;
	int player_home_y;
	int enemy_home_x;
	int enemy_home_y;
	int map_w;
	int map_h;
} params;

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= params.map_w || gid.y >= params.map_h) {
		return;
	}
	if (imageLoad(claimable, gid).r < 0.5) {
		imageStore(owner_out, gid, vec4(0.0));
		return;
	}
	if (gid.x == params.player_home_x && gid.y == params.player_home_y) {
		imageStore(owner_out, gid, vec4(128.0 / 255.0));
		return;
	}
	if (gid.x == params.enemy_home_x && gid.y == params.enemy_home_y) {
		imageStore(owner_out, gid, vec4(192.0 / 255.0));
		return;
	}
	float pf = imageLoad(pressure_f, gid).r;
	float ph = imageLoad(pressure_h, gid).r;
	float tile_ratio = params.dominance_ratio * imageLoad(claim_mult, gid).r;
	float o = 64.0 / 255.0;
	if (pf < params.min_claim_pressure && ph < params.min_claim_pressure) {
		o = 64.0 / 255.0;
	} else if (pf > ph * tile_ratio) {
		o = 128.0 / 255.0;
	} else if (ph > pf * tile_ratio) {
		o = 192.0 / 255.0;
	} else if (pf > 0.05 && ph > 0.05) {
		o = 1.0;
	}
	imageStore(owner_out, gid, vec4(o));
}
