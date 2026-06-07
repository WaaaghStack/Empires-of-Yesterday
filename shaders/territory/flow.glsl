#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict readonly image2D src_pressure;
layout(set = 0, binding = 1, r32f) uniform restrict writeonly image2D dst_pressure;
layout(set = 0, binding = 2, r32f) uniform restrict readonly image2D elevation;
layout(set = 0, binding = 3, r32f) uniform restrict readonly image2D flow_mult;
layout(set = 0, binding = 4, r8) uniform restrict readonly image2D claimable;

layout(set = 1, binding = 0, std140) uniform Params {
	float flow_conductivity;
	float min_flow_delta;
	float max_outflow_frac;
	int map_w;
	int map_h;
} params;

float sample_p(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= params.map_w || c.y >= params.map_h) {
		return 0.0;
	}
	if (imageLoad(claimable, c).r < 0.5) {
		return 0.0;
	}
	return imageLoad(src_pressure, c).r;
}

float sample_elev(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= params.map_w || c.y >= params.map_h) {
		return 0.0;
	}
	return imageLoad(elevation, c).r;
}

float sample_flow(ivec2 c) {
	if (c.x < 0 || c.y < 0 || c.x >= params.map_w || c.y >= params.map_h) {
		return 0.0;
	}
	return imageLoad(flow_mult, c).r;
}

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= params.map_w || gid.y >= params.map_h) {
		return;
	}
	if (imageLoad(claimable, gid).r < 0.5) {
		imageStore(dst_pressure, gid, vec4(0.0));
		return;
	}
	float p = sample_p(gid);
	float elev_s = sample_elev(gid);
	float h_src = p + elev_s;
	float mult_s = sample_flow(gid);
	float outflow = 0.0;
	float inflow = 0.0;
	const ivec2 dirs[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
	for (int i = 0; i < 4; i++) {
		ivec2 nc = gid + dirs[i];
		float p_n = sample_p(nc);
		float elev_n = sample_elev(nc);
		float h_n = p_n + elev_n;
		float mult_n = sample_flow(nc);
		float edge = sqrt(max(mult_s * mult_n, 0.0));
		float dh_out = h_src - h_n;
		if (dh_out > params.min_flow_delta) {
			outflow += dh_out * params.flow_conductivity * edge;
		}
		float dh_in = h_n - h_src;
		if (dh_in > params.min_flow_delta) {
			inflow += dh_in * params.flow_conductivity * edge;
		}
	}
	float cap = min(p * params.max_outflow_frac, outflow);
	float new_p = max(0.0, p - cap + inflow);
	imageStore(dst_pressure, gid, vec4(new_p, 0.0, 0.0, 0.0));
}
