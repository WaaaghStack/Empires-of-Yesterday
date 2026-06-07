#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict readonly image2D pressure_f;
layout(set = 0, binding = 1, r32f) uniform restrict readonly image2D pressure_h;
layout(set = 0, binding = 2, r8) uniform restrict readonly image2D owner_in;
layout(set = 0, binding = 3, r8) uniform restrict writeonly image2D disp_owner;
layout(set = 0, binding = 4, r8) uniform restrict writeonly image2D disp_pf;
layout(set = 0, binding = 5, r8) uniform restrict writeonly image2D disp_ph;
layout(set = 0, binding = 6, r8) uniform restrict readonly image2D claimable;

layout(set = 1, binding = 0, std140) uniform Params {
	float frame_peak;
	int map_w;
	int map_h;
} params;

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= params.map_w || gid.y >= params.map_h) {
		return;
	}
	if (imageLoad(claimable, gid).r < 0.5) {
		imageStore(disp_owner, gid, vec4(0.0));
		imageStore(disp_pf, gid, vec4(0.0));
		imageStore(disp_ph, gid, vec4(0.0));
		return;
	}
	float pf = imageLoad(pressure_f, gid).r;
	float ph = imageLoad(pressure_h, gid).r;
	float peak = max(params.frame_peak, 0.001);
	float ob = imageLoad(owner_in, gid).r;
	imageStore(disp_owner, gid, vec4(ob));
	float nf = clamp(pf / peak, 0.0, 1.0);
	float nh = clamp(ph / peak, 0.0, 1.0);
	imageStore(disp_pf, gid, vec4(nf));
	imageStore(disp_ph, gid, vec4(nh));
}
