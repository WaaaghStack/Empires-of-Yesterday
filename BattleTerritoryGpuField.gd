class_name BattleTerritoryGpuField
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

const LOCAL_SIZE := 16
const MAX_INJECT_POINTS := 128
const INJECT_STRUCT_SIZE := 12  # ivec3

const SHADER_INJECT := "res://shaders/territory/inject.glsl"
const SHADER_FLOW := "res://shaders/territory/flow.glsl"
const SHADER_CANCEL := "res://shaders/territory/cancel.glsl"
const SHADER_OWNER := "res://shaders/territory/owner.glsl"
const SHADER_PACK := "res://shaders/territory/pack_display.glsl"

var ready: bool = false
var grid_w: int = 0
var grid_h: int = 0
var tile_count: int = 0

var friendly_tiles: int = 0
var hostile_tiles: int = 0
var frame_peak: float = 1.0

var _rd: RenderingDevice
var _pf_tex: Array[RID] = []
var _ph_tex: Array[RID] = []
var _pf_idx: int = 0
var _ph_idx: int = 0
var _claimable_tex: RID
var _elevation_tex: RID
var _flow_mult_tex: RID
var _claim_mult_tex: RID
var _owner_tex: RID
var _disp_owner_tex: RID
var _disp_pf_tex: RID
var _disp_ph_tex: RID
var _disp_owner_rd: RID
var _disp_pf_rd: RID
var _disp_ph_rd: RID
var _display_uses_rd: bool = false
var _owns_local_rd: bool = false

var _pipelines: Dictionary = {}
var _shaders: Dictionary = {}
var _tile_control: BattleTileControlLib

var _inject_params_buf: RID
var _flow_params_buf: RID
var _cancel_params_buf: RID
var _owner_params_buf: RID
var _pack_params_buf: RID
var _inject_points_buf: RID

var _friendly_rate: float = 1.0
var _hostile_rate: float = 1.0
var _player_home: Vector2i = Vector2i(-1, -1)
var _enemy_home: Vector2i = Vector2i(-1, -1)
var _inject_points: PackedInt32Array = PackedInt32Array()
var _territory_round_index: int = 0
var _pressure_inject_interval: int = 10

var _groups_x: int = 1
var _groups_y: int = 1


static func default_live_backend_enabled() -> bool:
	var env: String = OS.get_environment("BATTLE_TERRITORY_BACKEND").to_lower()
	return env != "cpu"


static func compare_enabled() -> bool:
	return OS.get_environment("BATTLE_GPU_COMPARE") == "1"


func setup_from_tile_control(map_data, tile_control: BattleTileControlLib) -> bool:
	_free_gpu()
	if map_data == null or tile_control == null:
		return false
	grid_w = map_data.grid_width
	grid_h = map_data.grid_height
	tile_count = grid_w * grid_h
	if tile_count <= 0:
		return false
	# Compute submit/sync requires a local RenderingDevice (not the main device).
	_rd = RenderingServer.create_local_rendering_device()
	_owns_local_rd = true
	if _rd == null:
		return false
	if not _load_pipelines():
		_free_gpu()
		return false
	_groups_x = int(ceil(float(grid_w) / float(LOCAL_SIZE)))
	_groups_y = int(ceil(float(grid_h) / float(LOCAL_SIZE)))
	_create_textures()
	_upload_static_from_tile_control(map_data, tile_control)
	_upload_pressure_from_cpu(tile_control.pressure_friendly, tile_control.pressure_hostile)
	_upload_owners_from_cpu(tile_control.owners)
	_friendly_rate = tile_control._friendly_spawn_rate
	_hostile_rate = tile_control._hostile_spawn_rate
	_player_home = map_data.player_home_grid
	_enemy_home = map_data.enemy_home_grid
	_pressure_inject_interval = maxi(1, WorldConquestConfigLib.PRESSURE_INJECT_INTERVAL_ROUNDS)
	_territory_round_index = 0
	_sync_inject_points_from_tile_control(tile_control)
	_create_param_buffers()
	_update_tile_counts_from_owners_cpu(tile_control.owners)
	_tile_control = tile_control
	if not _validate_sim_textures():
		_free_gpu()
		return false
	_dispatch_pack_display()
	if not _bind_display_textures():
		_free_gpu()
		return false
	readback_owners()
	copy_owners_to_cpu_buffer(tile_control.owners)
	if friendly_tiles < 1 and hostile_tiles < 1:
		_free_gpu()
		return false
	ready = true
	return true


func step_round(tile_control: BattleTileControlLib = null) -> void:
	if not ready:
		return
	if tile_control != null:
		_tile_control = tile_control
	_territory_round_index += 1
	_sync_inject_points_from_tile_control(_tile_control)
	_dispatch_inject()
	_dispatch_flow(true)
	_dispatch_flow(false)
	_dispatch_cancel()
	_dispatch_owner()
	frame_peak = maxf(frame_peak, maxf(_friendly_rate, _hostile_rate))
	if not WorldConquestConfigLib.OVERLAY_OWNERS_ONLY:
		_dispatch_pack_display()


func readback_owners_if_due(round_index: int) -> bool:
	if not ready:
		return false
	var interval: int = 1 if tile_count <= 96 * 72 else 4
	if round_index > 0 and round_index % interval != 0:
		return false
	return readback_owners()


func readback_owners() -> bool:
	if not ready or not _owner_tex.is_valid():
		return false
	var raw: PackedByteArray = _rd.texture_get_data(_owner_tex, 0)
	var data: PackedByteArray = _r8_bytes_from_readback(raw, tile_count)
	if data.size() != tile_count:
		return false
	_update_tile_counts_from_owner_bytes(data)
	return true


func get_display_texture_rids() -> Dictionary:
	return {
		"owner": _disp_owner_rd,
		"friendly_pressure": _disp_pf_rd,
		"hostile_pressure": _disp_ph_rd,
	}


func uses_rd_display() -> bool:
	return _display_uses_rd


func bind_display_to_material(mat: ShaderMaterial) -> void:
	if mat == null or not ready:
		return
	if _display_uses_rd:
		mat.set_shader_parameter("owner_map", _disp_owner_rd)
		mat.set_shader_parameter("friendly_pressure", _disp_pf_rd)
		mat.set_shader_parameter("hostile_pressure", _disp_ph_rd)
	else:
		_apply_display_images_to_material(mat)
	mat.set_shader_parameter("frame_peak", maxf(frame_peak, 1.0))


func sync_display_images_to_material(mat: ShaderMaterial) -> void:
	if not ready or mat == null:
		return
	_dispatch_pack_display()
	_apply_display_images_to_material(mat)


func export_state_to_tile_control(tile_control: BattleTileControlLib) -> bool:
	if not ready or tile_control == null:
		return false
	var raw: PackedByteArray = _rd.texture_get_data(_owner_tex, 0)
	var owner_bytes: PackedByteArray = _r8_bytes_from_readback(raw, tile_count)
	if not _owner_readback_looks_valid(owner_bytes):
		return false
	copy_owners_to_cpu_buffer(tile_control.owners)
	var pf: PackedFloat32Array = _read_r32_texture(_pf_tex[_pf_idx])
	var ph: PackedFloat32Array = _read_r32_texture(_ph_tex[_ph_idx])
	if pf.size() != tile_count or ph.size() != tile_count:
		return false
	tile_control.pressure_friendly = pf
	tile_control.pressure_hostile = ph
	readback_owners()
	tile_control.friendly_tiles = friendly_tiles
	tile_control.hostile_tiles = hostile_tiles
	var peak: float = 0.01
	for i in range(tile_count):
		peak = maxf(peak, tile_control.pressure_friendly[i])
		peak = maxf(peak, tile_control.pressure_hostile[i])
	frame_peak = maxf(peak, 1.0)
	return true


func copy_owners_to_cpu_buffer(out_owners: PackedByteArray) -> void:
	if not ready or out_owners.size() != tile_count:
		return
	var raw: PackedByteArray = _rd.texture_get_data(_owner_tex, 0)
	var data: PackedByteArray = _r8_bytes_from_readback(raw, tile_count)
	if data.size() != tile_count:
		return
	for i in range(tile_count):
		out_owners[i] = _owner_byte_to_sim(int(data[i]) & 0xFF)


func get_pressure_cpu_snapshot() -> Dictionary:
	var pf: PackedFloat32Array = _read_r32_texture(_pf_tex[_pf_idx])
	var ph: PackedFloat32Array = _read_r32_texture(_ph_tex[_ph_idx])
	return {"friendly": pf, "hostile": ph}


func _free_gpu() -> void:
	ready = false
	if _rd == null:
		return
	for key in _pipelines.keys():
		var pipe: RID = _pipelines[key]
		if pipe.is_valid():
			_rd.free_rid(pipe)
	_pipelines.clear()
	for key in _shaders.keys():
		var sh: RID = _shaders[key]
		if sh.is_valid():
			_rd.free_rid(sh)
	_shaders.clear()
	for tex in _pf_tex + _ph_tex:
		if tex.is_valid():
			_rd.free_rid(tex)
	_pf_tex.clear()
	_ph_tex.clear()
	_free_display_rd_bindings()
	for rid in [
		_claimable_tex, _elevation_tex, _flow_mult_tex, _claim_mult_tex, _owner_tex,
		_disp_owner_tex, _disp_pf_tex, _disp_ph_tex,
		_inject_params_buf, _flow_params_buf, _cancel_params_buf,
		_owner_params_buf, _pack_params_buf, _inject_points_buf,
	]:
		if rid.is_valid():
			_rd.free_rid(rid)
	if _owns_local_rd and _rd.is_valid():
		_rd.free()
	_rd = null
	_owns_local_rd = false
	_display_uses_rd = false


func _load_pipelines() -> bool:
	for path in [SHADER_INJECT, SHADER_FLOW, SHADER_CANCEL, SHADER_OWNER, SHADER_PACK]:
		var shader_file: RDShaderFile = load(path) as RDShaderFile
		if shader_file == null:
			push_error("BattleTerritoryGpuField: failed to load %s" % path)
			return false
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		var shader: RID = _rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			push_error("BattleTerritoryGpuField: shader compile failed %s" % path)
			return false
		_shaders[path] = shader
		_pipelines[path] = _rd.compute_pipeline_create(shader)
	return true


func _tex_format_r32() -> RDTextureFormat:
	var fmt := RDTextureFormat.new()
	fmt.width = grid_w
	fmt.height = grid_h
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)
	return fmt


func _tex_format_r8() -> RDTextureFormat:
	var fmt := RDTextureFormat.new()
	fmt.width = grid_w
	fmt.height = grid_h
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	)
	return fmt


func _create_tex(fmt: RDTextureFormat, data: PackedByteArray = PackedByteArray()) -> RID:
	var view := RDTextureView.new()
	if data.is_empty():
		return _rd.texture_create(fmt, view)
	return _rd.texture_create(fmt, view, [data])


func _create_textures() -> void:
	var r32 := _tex_format_r32()
	var r8 := _tex_format_r8()
	_pf_tex = [_create_tex(r32), _create_tex(r32)]
	_ph_tex = [_create_tex(r32), _create_tex(r32)]
	_claimable_tex = _create_tex(r8)
	_elevation_tex = _create_tex(r32)
	_flow_mult_tex = _create_tex(r32)
	_claim_mult_tex = _create_tex(r32)
	_owner_tex = _create_tex(r8)
	_disp_owner_tex = _create_tex(r8)
	_disp_pf_tex = _create_tex(r8)
	_disp_ph_tex = _create_tex(r8)


func _validate_sim_textures() -> bool:
	for tex in _pf_tex + _ph_tex:
		if not tex.is_valid():
			return false
	return (
		_claimable_tex.is_valid()
		and _elevation_tex.is_valid()
		and _owner_tex.is_valid()
		and _disp_owner_tex.is_valid()
	)


func _free_display_rd_bindings() -> void:
	if _disp_owner_rd.is_valid():
		RenderingServer.free_rid(_disp_owner_rd)
		_disp_owner_rd = RID()
	if _disp_pf_rd.is_valid():
		RenderingServer.free_rid(_disp_pf_rd)
		_disp_pf_rd = RID()
	if _disp_ph_rd.is_valid():
		RenderingServer.free_rid(_disp_ph_rd)
		_disp_ph_rd = RID()


func _bind_display_textures() -> bool:
	_free_display_rd_bindings()
	# Local RD textures cannot use RenderingServer.texture_rd_create; display via Image readback.
	_display_uses_rd = false
	return _disp_owner_tex.is_valid()


func _apply_display_images_to_material(mat: ShaderMaterial) -> void:
	var o_img: Image = _rd_texture_to_r8_image(_disp_owner_tex)
	var f_img: Image = _rd_texture_to_r8_image(_disp_pf_tex)
	var h_img: Image = _rd_texture_to_r8_image(_disp_ph_tex)
	if o_img == null or f_img == null or h_img == null:
		return
	var o_tex := ImageTexture.create_from_image(o_img)
	var f_tex := ImageTexture.create_from_image(f_img)
	var h_tex := ImageTexture.create_from_image(h_img)
	mat.set_shader_parameter("owner_map", o_tex)
	mat.set_shader_parameter("friendly_pressure", f_tex)
	mat.set_shader_parameter("hostile_pressure", h_tex)


static func _owner_readback_looks_valid(owner_bytes: PackedByteArray) -> bool:
	if owner_bytes.is_empty():
		return false
	var owned: int = 0
	for i in range(owner_bytes.size()):
		var b: int = int(owner_bytes[i]) & 0xFF
		if b >= 96 and b < 240:
			owned += 1
	return owned > 0


static func _r8_bytes_from_readback(raw: PackedByteArray, pixel_count: int) -> PackedByteArray:
	if raw.is_empty() or pixel_count <= 0:
		return PackedByteArray()
	if raw.size() == pixel_count:
		return raw
	var out := PackedByteArray()
	out.resize(pixel_count)
	if raw.size() >= pixel_count * 4:
		for i in range(pixel_count):
			out[i] = raw[i * 4] & 0xFF
		return out
	return PackedByteArray()


func _rd_texture_to_r8_image(tex: RID) -> Image:
	if not tex.is_valid():
		return null
	var raw: PackedByteArray = _rd.texture_get_data(tex, 0)
	var data: PackedByteArray = _r8_bytes_from_readback(raw, tile_count)
	if data.size() != tile_count:
		return null
	return Image.create_from_data(grid_w, grid_h, false, Image.FORMAT_R8, data)


func refresh_claimable_from(map_data, tile_control: BattleTileControlLib) -> void:
	if not ready or map_data == null or tile_control == null:
		return
	_upload_static_from_tile_control(map_data, tile_control)
	_upload_owners_from_cpu(tile_control.owners)
	_update_tile_counts_from_owners_cpu(tile_control.owners)
	_sync_inject_points_from_tile_control(tile_control)


func _upload_static_from_tile_control(map_data, tile_control: BattleTileControlLib) -> void:
	var n: int = tile_count
	var claim := PackedByteArray()
	claim.resize(n)
	var elev := PackedByteArray()
	elev.resize(n * 4)
	var flow := PackedByteArray()
	flow.resize(n * 4)
	var claim_m := PackedByteArray()
	claim_m.resize(n * 4)
	for idx in range(n):
		claim[idx] = tile_control.claimable_mask[idx]
		var e: float = tile_control._elevation[idx] if idx < tile_control._elevation.size() else 0.0
		var f: float = (
			tile_control._terrain_flow_mult[idx]
			if idx < tile_control._terrain_flow_mult.size()
			else 1.0
		)
		var c: float = (
			tile_control._claim_ratio_mult[idx]
			if idx < tile_control._claim_ratio_mult.size()
			else 1.0
		)
		elev.encode_float(idx * 4, e)
		flow.encode_float(idx * 4, f)
		claim_m.encode_float(idx * 4, c)
	_rd.texture_update(_claimable_tex, 0, claim)
	_rd.texture_update(_elevation_tex, 0, elev)
	_rd.texture_update(_flow_mult_tex, 0, flow)
	_rd.texture_update(_claim_mult_tex, 0, claim_m)


func _upload_pressure_from_cpu(pf: PackedFloat32Array, ph: PackedFloat32Array) -> void:
	_rd.texture_update(_pf_tex[0], 0, _float_array_to_bytes(pf))
	_rd.texture_update(_ph_tex[0], 0, _float_array_to_bytes(ph))
	_pf_idx = 0
	_ph_idx = 0


func _upload_owners_from_cpu(owners: PackedByteArray) -> void:
	var bytes := PackedByteArray()
	bytes.resize(tile_count)
	for idx in range(tile_count):
		bytes[idx] = _sim_owner_to_display_byte(int(owners[idx]) if idx < owners.size() else 0)
	_rd.texture_update(_owner_tex, 0, bytes)


func _sync_inject_points_from_tile_control(tile_control: BattleTileControlLib) -> void:
	_inject_points.resize(MAX_INJECT_POINTS * 3)
	_inject_points.fill(0)
	var count: int = 0
	if tile_control != null:
		for sp: Dictionary in tile_control._placed_spawners:
			if count >= MAX_INJECT_POINTS:
				break
			var team: int = int(sp.get("team", BattleTileControlLib.OWNER_FRIENDLY))
			var gx: int = int(sp.get("gx", -1))
			var gy: int = int(sp.get("gy", -1))
			var team_code: int = 1 if team == BattleTileControlLib.OWNER_FRIENDLY else 2
			for d: Vector2i in BattleTileControlLib._DIRS_CARDINAL:
				if count >= MAX_INJECT_POINTS:
					break
				_inject_points[count * 3] = gx + d.x
				_inject_points[count * 3 + 1] = gy + d.y
				_inject_points[count * 3 + 2] = team_code
				count += 1
	if not _inject_points_buf.is_valid():
		return
	var byte_data := PackedByteArray()
	byte_data.resize(MAX_INJECT_POINTS * INJECT_STRUCT_SIZE)
	for i in range(MAX_INJECT_POINTS * 3):
		byte_data.encode_s32(i * 4, _inject_points[i])
	_rd.buffer_update(_inject_points_buf, 0, byte_data.size(), byte_data)


func _create_param_buffers() -> void:
	_inject_params_buf = _rd.uniform_buffer_create(48)
	_flow_params_buf = _rd.uniform_buffer_create(32)
	_cancel_params_buf = _rd.uniform_buffer_create(16)
	_owner_params_buf = _rd.uniform_buffer_create(48)
	_pack_params_buf = _rd.uniform_buffer_create(16)
	_inject_points_buf = _rd.storage_buffer_create(
		MAX_INJECT_POINTS * INJECT_STRUCT_SIZE,
		PackedByteArray(),
	)


func _dispatch_inject() -> void:
	var pb := PackedByteArray()
	pb.resize(48)
	pb.encode_float(0, _friendly_rate)
	pb.encode_float(4, _hostile_rate)
	pb.encode_s32(8, _player_home.x)
	pb.encode_s32(12, _player_home.y)
	pb.encode_s32(16, _enemy_home.x)
	pb.encode_s32(20, _enemy_home.y)
	pb.encode_s32(24, grid_w)
	pb.encode_s32(28, grid_h)
	var inject_count: int = 0
	if _tile_control != null:
		inject_count = mini(MAX_INJECT_POINTS, _tile_control._placed_spawners.size())
	pb.encode_s32(32, inject_count)
	pb.encode_s32(36, _territory_round_index)
	pb.encode_s32(40, _pressure_inject_interval)
	_rd.buffer_update(_inject_params_buf, 0, pb.size(), pb)

	var u0: Array[RDUniform] = []
	var a := RDUniform.new()
	a.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	a.binding = 0
	a.add_id(_pf_tex[_pf_idx])
	u0.append(a)
	a = RDUniform.new()
	a.binding = 1
	a.add_id(_ph_tex[_ph_idx])
	u0.append(a)
	a = RDUniform.new()
	a.binding = 2
	a.add_id(_claimable_tex)
	u0.append(a)
	var u1: Array[RDUniform] = []
	a = RDUniform.new()
	a.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	a.binding = 0
	a.add_id(_inject_params_buf)
	u1.append(a)
	a = RDUniform.new()
	a.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	a.binding = 1
	a.add_id(_inject_points_buf)
	u1.append(a)
	_dispatch_shader(SHADER_INJECT, u0, u1)


func _dispatch_flow(is_friendly: bool) -> void:
	var src_idx: int = _pf_idx if is_friendly else _ph_idx
	var dst_idx: int = 1 - src_idx
	var src_tex: RID = _pf_tex[src_idx] if is_friendly else _ph_tex[src_idx]
	var dst_tex: RID = _pf_tex[dst_idx] if is_friendly else _ph_tex[dst_idx]

	var pb := PackedByteArray()
	pb.resize(32)
	pb.encode_float(0, BattleTileControlLib.FLOW_CONDUCTIVITY)
	pb.encode_float(4, BattleTileControlLib.MIN_FLOW_DELTA)
	pb.encode_float(8, BattleTileControlLib.MAX_OUTFLOW_FRAC)
	pb.encode_s32(12, grid_w)
	pb.encode_s32(16, grid_h)
	_rd.buffer_update(_flow_params_buf, 0, pb.size(), pb)

	var u0: Array[RDUniform] = []
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(src_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 1
	u.add_id(dst_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 2
	u.add_id(_elevation_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 3
	u.add_id(_flow_mult_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 4
	u.add_id(_claimable_tex)
	u0.append(u)
	var u1: Array[RDUniform] = []
	u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = 0
	u.add_id(_flow_params_buf)
	u1.append(u)
	_dispatch_shader(SHADER_FLOW, u0, u1)
	if is_friendly:
		_pf_idx = dst_idx
	else:
		_ph_idx = dst_idx


func _dispatch_cancel() -> void:
	var pb := PackedByteArray()
	pb.resize(16)
	pb.encode_s32(0, grid_w)
	pb.encode_s32(4, grid_h)
	_rd.buffer_update(_cancel_params_buf, 0, pb.size(), pb)
	var u0: Array[RDUniform] = []
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(_pf_tex[_pf_idx])
	u0.append(u)
	u = RDUniform.new()
	u.binding = 1
	u.add_id(_ph_tex[_ph_idx])
	u0.append(u)
	u = RDUniform.new()
	u.binding = 2
	u.add_id(_claimable_tex)
	u0.append(u)
	var u1: Array[RDUniform] = []
	u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = 0
	u.add_id(_cancel_params_buf)
	u1.append(u)
	_dispatch_shader(SHADER_CANCEL, u0, u1)


func _dispatch_owner() -> void:
	var pb := PackedByteArray()
	pb.resize(48)
	pb.encode_float(0, BattleTileControlLib.MIN_CLAIM_PRESSURE)
	pb.encode_float(4, 1.15)
	pb.encode_s32(8, _player_home.x)
	pb.encode_s32(12, _player_home.y)
	pb.encode_s32(16, _enemy_home.x)
	pb.encode_s32(20, _enemy_home.y)
	pb.encode_s32(24, grid_w)
	pb.encode_s32(28, grid_h)
	_rd.buffer_update(_owner_params_buf, 0, pb.size(), pb)
	var u0: Array[RDUniform] = []
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(_pf_tex[_pf_idx])
	u0.append(u)
	u = RDUniform.new()
	u.binding = 1
	u.add_id(_ph_tex[_ph_idx])
	u0.append(u)
	u = RDUniform.new()
	u.binding = 2
	u.add_id(_claim_mult_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 3
	u.add_id(_owner_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 4
	u.add_id(_claimable_tex)
	u0.append(u)
	var u1: Array[RDUniform] = []
	u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = 0
	u.add_id(_owner_params_buf)
	u1.append(u)
	_dispatch_shader(SHADER_OWNER, u0, u1)


func _dispatch_pack_display() -> void:
	frame_peak = maxf(maxf(_friendly_rate, _hostile_rate), 1.0)
	var pb := PackedByteArray()
	pb.resize(16)
	pb.encode_float(0, frame_peak)
	pb.encode_s32(4, grid_w)
	pb.encode_s32(8, grid_h)
	_rd.buffer_update(_pack_params_buf, 0, pb.size(), pb)
	var u0: Array[RDUniform] = []
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = 0
	u.add_id(_pf_tex[_pf_idx])
	u0.append(u)
	u = RDUniform.new()
	u.binding = 1
	u.add_id(_ph_tex[_ph_idx])
	u0.append(u)
	u = RDUniform.new()
	u.binding = 2
	u.add_id(_owner_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 3
	u.add_id(_disp_owner_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 4
	u.add_id(_disp_pf_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 5
	u.add_id(_disp_ph_tex)
	u0.append(u)
	u = RDUniform.new()
	u.binding = 6
	u.add_id(_claimable_tex)
	u0.append(u)
	var u1: Array[RDUniform] = []
	u = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = 0
	u.add_id(_pack_params_buf)
	u1.append(u)
	_dispatch_shader(SHADER_PACK, u0, u1)


func _dispatch_shader(path: String, set0: Array, set1: Array) -> void:
	if not _owns_local_rd or _rd == null:
		return
	var pipeline: RID = _pipelines.get(path, RID())
	var shader: RID = _shaders.get(path, RID())
	if not pipeline.is_valid() or not shader.is_valid():
		return
	var us0 := _rd.uniform_set_create(set0, shader, 0)
	var us1 := _rd.uniform_set_create(set1, shader, 1)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, pipeline)
	_rd.compute_list_bind_uniform_set(cl, us0, 0)
	_rd.compute_list_bind_uniform_set(cl, us1, 1)
	_rd.compute_list_dispatch(cl, _groups_x, _groups_y, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	if us0.is_valid():
		_rd.free_rid(us0)
	if us1.is_valid():
		_rd.free_rid(us1)


func _read_r32_texture(tex: RID) -> PackedFloat32Array:
	var data: PackedByteArray = _rd.texture_get_data(tex, 0)
	var out := PackedFloat32Array()
	out.resize(tile_count)
	for i in range(mini(tile_count, data.size() / 4)):
		out[i] = data.decode_float(i * 4)
	return out


func _float_array_to_bytes(arr: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(arr.size() * 4)
	for i in range(arr.size()):
		bytes.encode_float(i * 4, arr[i])
	return bytes


func _update_tile_counts_from_owner_bytes(data: PackedByteArray) -> void:
	friendly_tiles = 0
	hostile_tiles = 0
	for i in range(mini(tile_count, data.size())):
		var b: int = int(data[i]) & 0xFF
		match _owner_byte_to_sim(b):
			BattleTileControlLib.OWNER_FRIENDLY:
				friendly_tiles += 1
			BattleTileControlLib.OWNER_HOSTILE:
				hostile_tiles += 1


func _update_tile_counts_from_owners_cpu(owners: PackedByteArray) -> void:
	friendly_tiles = 0
	hostile_tiles = 0
	for idx in range(owners.size()):
		match int(owners[idx]):
			BattleTileControlLib.OWNER_FRIENDLY:
				friendly_tiles += 1
			BattleTileControlLib.OWNER_HOSTILE:
				hostile_tiles += 1


static func _sim_owner_to_display_byte(owner: int) -> int:
	match owner:
		BattleTileControlLib.OWNER_FRIENDLY:
			return 128
		BattleTileControlLib.OWNER_HOSTILE:
			return 192
		BattleTileControlLib.OWNER_CONTESTED:
			return 255
		BattleTileControlLib.OWNER_NEUTRAL:
			return 64
		_:
			return 0


static func _owner_byte_to_sim(b: int) -> int:
	if b >= 240:
		return BattleTileControlLib.OWNER_CONTESTED
	if b >= 160:
		return BattleTileControlLib.OWNER_HOSTILE
	if b >= 96:
		return BattleTileControlLib.OWNER_FRIENDLY
	if b >= 32:
		return BattleTileControlLib.OWNER_NEUTRAL
	if b <= 0:
		return BattleTileControlLib.OWNER_UNCLAIMABLE
	return BattleTileControlLib.OWNER_NEUTRAL
