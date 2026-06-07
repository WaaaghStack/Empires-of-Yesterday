#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict image2D pressure_f;
layout(set = 0, binding = 1, r32f) uniform restrict image2D pressure_h;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D claimable;

layout(set = 1, binding = 0, std140) uniform Params {
	int map_w;
	int map_h;
} params;

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= params.map_w || gid.y >= params.map_h) {
		return;
	}
	if (imageLoad(claimable, gid).r < 0.5) {
		imageStore(pressure_f, gid, vec4(0.0));
		imageStore(pressure_h, gid, vec4(0.0));
		return;
	}
	float pf = imageLoad(pressure_f, gid).r;
	float ph = imageLoad(pressure_h, gid).r;
	if (pf > 0.0 && ph > 0.0) {
		float c = min(pf, ph);
		pf -= c;
		ph -= c;
	}
	imageStore(pressure_f, gid, vec4(pf, 0.0, 0.0, 0.0));
	imageStore(pressure_h, gid, vec4(ph, 0.0, 0.0, 0.0));
}
