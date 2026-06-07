class_name BattleTileOwnershipOverlay
extends Node2D

const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleTilePressureCodecLib := preload("res://BattleTilePressureCodec.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryGpuFieldLib := preload("res://BattleTerritoryGpuField.gd")
const _FLUID_SHADER := preload("res://shaders/battle_territory_fluid.gdshader")

var _battle_data = null
var _sprite: Sprite2D
var _texture: ImageTexture
var _last_owners: PackedByteArray = PackedByteArray()
var _power_scale: float = 1.0  # 1.0 = full visibility; lower early in battle so emitted power starts faint (2% at low totals)
var _gpu_pressure_mode: bool = false
var _gpu_sim_mode: bool = false
var _gpu_field: BattleTerritoryGpuFieldLib
var _owner_img: Image
var _friendly_pressure_img: Image
var _hostile_pressure_img: Image
var _owner_tex: ImageTexture
var _friendly_pressure_tex: ImageTexture
var _hostile_pressure_tex: ImageTexture
var _shader_mat: ShaderMaterial
var _land_mask: PackedByteArray = PackedByteArray()
var _owner_bytes_cache: PackedByteArray = PackedByteArray()
var _friendly_bytes_cache: PackedByteArray = PackedByteArray()
var _hostile_bytes_cache: PackedByteArray = PackedByteArray()


func setup(battle_data) -> void:
	_battle_data = battle_data
	z_index = -4
	_texture = ImageTexture.new()
	_sprite = Sprite2D.new()
	_sprite.name = "FluidField"
	_sprite.texture = _texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.centered = false
	if battle_data != null:
		var half: Vector2 = battle_data.map_size * 0.5
		_sprite.position = -half
		_sprite.scale = Vector2(battle_data.cell_size, battle_data.cell_size)
	add_child(_sprite)


func enable_gpu_pressure_mode() -> void:
	if _battle_data == null or _sprite == null:
		return
	_gpu_pressure_mode = true
	var w: int = _battle_data.grid_width
	var h: int = _battle_data.grid_height
	var n: int = w * h
	_land_mask.resize(n)
	_owner_bytes_cache.resize(n)
	_friendly_bytes_cache.resize(n)
	_hostile_bytes_cache.resize(n)
	for idx in range(n):
		var gx: int = idx % w
		var gy: int = idx / w
		_land_mask[idx] = 1 if _battle_data.is_land_cell(gx, gy) else 0
	_owner_img = Image.create(w, h, false, Image.FORMAT_R8)
	_friendly_pressure_img = Image.create(w, h, false, Image.FORMAT_R8)
	_hostile_pressure_img = Image.create(w, h, false, Image.FORMAT_R8)
	_owner_img.fill(Color(0, 0, 0, 1))
	_friendly_pressure_img.fill(Color(0, 0, 0, 1))
	_hostile_pressure_img.fill(Color(0, 0, 0, 1))
	_owner_tex = ImageTexture.create_from_image(_owner_img)
	_friendly_pressure_tex = ImageTexture.create_from_image(_friendly_pressure_img)
	_hostile_pressure_tex = ImageTexture.create_from_image(_hostile_pressure_img)
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = _FLUID_SHADER
	_shader_mat.set_shader_parameter("owner_map", _owner_tex)
	_shader_mat.set_shader_parameter("friendly_pressure", _friendly_pressure_tex)
	_shader_mat.set_shader_parameter("hostile_pressure", _hostile_pressure_tex)
	_shader_mat.set_shader_parameter("frame_peak", 1.0)
	_shader_mat.set_shader_parameter("interior_alpha", BattleTileFluidFieldLib.INTERIOR_FILL_ALPHA)
	_shader_mat.set_shader_parameter("front_alpha", BattleTileFluidFieldLib.FRONT_LINE_ALPHA)
	_shader_mat.set_shader_parameter("alpha_exponent", BattleTileFluidFieldLib.FLUID_ALPHA_EXPONENT)
	_sprite.material = _shader_mat
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var blank := Image.create(w, h, false, Image.FORMAT_RGBA8)
	blank.fill(Color(1, 1, 1, 1))
	_texture = ImageTexture.create_from_image(blank)
	_sprite.texture = _texture


func enable_gpu_sim_mode(_gpu_field_ref: BattleTerritoryGpuFieldLib) -> void:
	# GPU sim runs on BattleTerritoryGpuField; overlay still uploads via apply_live_state.
	enable_gpu_pressure_mode()
	_gpu_sim_mode = false
	_gpu_field = null


func is_gpu_sim_mode() -> bool:
	return _gpu_sim_mode and _gpu_field != null and _gpu_field.ready


func refresh_gpu_sim_display() -> void:
	if not is_gpu_sim_mode() or _shader_mat == null:
		return
	if _gpu_field.uses_rd_display():
		_gpu_field.bind_display_to_material(_shader_mat)
	else:
		_gpu_field.sync_display_images_to_material(_shader_mat)


func apply_live_pressures(friendly: PackedFloat32Array, hostile: PackedFloat32Array) -> void:
	apply_live_state(PackedByteArray(), friendly, hostile)


func apply_live_state(
	owners: PackedByteArray,
	friendly: PackedFloat32Array,
	hostile: PackedFloat32Array,
) -> void:
	if not _gpu_pressure_mode or _battle_data == null:
		return
	if friendly.is_empty() or hostile.is_empty():
		return
	var w: int = _battle_data.grid_width
	var h: int = _battle_data.grid_height
	var n: int = w * h
	var frame_peak: float = _frame_peak_on_land(friendly, hostile)
	if frame_peak < 0.01:
		frame_peak = 1.0
	if _owner_bytes_cache.size() != n:
		_owner_bytes_cache.resize(n)
		_friendly_bytes_cache.resize(n)
		_hostile_bytes_cache.resize(n)
	var owner_bytes: PackedByteArray = _owner_bytes_cache
	var friendly_bytes: PackedByteArray = _friendly_bytes_cache
	var hostile_bytes: PackedByteArray = _hostile_bytes_cache
	var inv_peak: float = 1.0 / frame_peak
	for idx in range(n):
		if _land_mask.size() == n and _land_mask[idx] == 0:
			owner_bytes[idx] = 0
			friendly_bytes[idx] = 0
			hostile_bytes[idx] = 0
			continue
		var o: int = int(owners[idx]) if idx < owners.size() else 0
		owner_bytes[idx] = _owner_byte(o)
		var rf: float = friendly[idx] if idx < friendly.size() else 0.0
		var rh: float = hostile[idx] if idx < hostile.size() else 0.0
		friendly_bytes[idx] = _pressure_byte_fast(rf, inv_peak)
		hostile_bytes[idx] = _pressure_byte_fast(rh, inv_peak)
	_owner_img.set_data(w, h, false, Image.FORMAT_R8, owner_bytes)
	_friendly_pressure_img.set_data(w, h, false, Image.FORMAT_R8, friendly_bytes)
	_hostile_pressure_img.set_data(w, h, false, Image.FORMAT_R8, hostile_bytes)
	_owner_tex.update(_owner_img)
	_friendly_pressure_tex.update(_friendly_pressure_img)
	_hostile_pressure_tex.update(_hostile_pressure_img)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("frame_peak", frame_peak)


static func _owner_byte(owner: int) -> int:
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


static func _pressure_byte(raw: float, frame_peak: float) -> int:
	if raw <= 0.01:
		return 0
	return int(clampf(raw / frame_peak, 0.0, 1.0) * 255.0)


static func _pressure_byte_fast(raw: float, inv_peak: float) -> int:
	if raw <= 0.01:
		return 0
	return int(clampf(raw * inv_peak, 0.0, 1.0) * 255.0)


func _frame_peak_on_land(friendly: PackedFloat32Array, hostile: PackedFloat32Array) -> float:
	var peak: float = 0.0
	var n: int = mini(friendly.size(), hostile.size())
	for idx in range(n):
		var gx: int = idx % _battle_data.grid_width
		var gy: int = idx / _battle_data.grid_width
		if not _battle_data.is_land_cell(gx, gy):
			continue
		peak = maxf(peak, friendly[idx])
		peak = maxf(peak, hostile[idx])
	return peak


func apply_prebuilt_image(img: Image) -> void:
	if img == null or _texture == null:
		return
	if _sprite != null:
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture.set_image(img)


func apply_powers(
	friendly: PackedFloat32Array,
	hostile: PackedFloat32Array,
	blend_from_f: PackedFloat32Array = PackedFloat32Array(),
	blend_from_h: PackedFloat32Array = PackedFloat32Array(),
	blend_t: float = -1.0,
) -> void:
	if _gpu_pressure_mode and blend_t < 0.0:
		apply_live_pressures(friendly, hostile)
		return
	if _battle_data == null or friendly.is_empty() or hostile.is_empty():
		return
	var pf: PackedFloat32Array = friendly
	var ph: PackedFloat32Array = hostile
	if not blend_from_f.is_empty() and not blend_from_h.is_empty() and blend_t >= 0.0:
		pf = BattleTilePressureCodecLib.lerp_arrays(blend_from_f, friendly, blend_t)
		ph = BattleTilePressureCodecLib.lerp_arrays(blend_from_h, hostile, blend_t)
	var img: Image = BattleTileFluidFieldLib.build_fluid_image_from_powers(
		_battle_data, pf, ph, 1.0, 0
	)
	if img == null:
		return
	_texture.set_image(img)


func apply_owners(owners: PackedByteArray, blend_from: PackedByteArray = PackedByteArray(), blend_t: float = -1.0) -> void:
	if _battle_data == null or owners.is_empty():
		return
	var display_owners: PackedByteArray = owners
	if not blend_from.is_empty() and blend_t >= 0.0:
		display_owners = BattleTileFluidFieldLib.blend_owner_frames(
			_battle_data, blend_from, owners, blend_t
		)
	display_owners = BattleTileFluidFieldLib.soften_owners_for_display(_battle_data, display_owners)
	_last_owners = display_owners
	var img: Image = BattleTileFluidFieldLib.build_fluid_image(_battle_data, display_owners, BattleTileFluidFieldLib.DIFFUSE_PASSES, _power_scale)
	if img == null:
		return
	_texture.set_image(img)


func get_last_owners() -> PackedByteArray:
	return _last_owners


# Simple home base markers for the new fluid system.
# Call this after setup if you have home base positions.
var _home_bases: Array = []  # [{team: int, x: int, y: int}]

func set_home_bases(home_bases: Array) -> void:
	_home_bases = home_bases
	queue_redraw()  # Ensure custom _draw runs for the markers

func set_power_scale(scale: float) -> void:
	_power_scale = clampf(scale, 0.01, 1.0)
	# Rebuild the current fluid image with new scale if we have owners
	if _last_owners.size() > 0:
		var img: Image = BattleTileFluidFieldLib.build_fluid_image(_battle_data, _last_owners, BattleTileFluidFieldLib.DIFFUSE_PASSES, _power_scale)
		if img != null and _texture != null:
			_texture.set_image(img)


func _draw() -> void:
	# Draw simple home base markers (black dot + team-colored ring, as requested).
	for base in _home_bases:
		var team := int(base.get("team", 0))
		var gx := int(base.get("x", 0))
		var gy := int(base.get("y", 0))

		if _battle_data == null:
			continue

		# Direct property access (battle_data is a RefCounted with these vars)
		var cell_size: float = _battle_data.cell_size if _battle_data else 32.0
		var map_size: Vector2 = _battle_data.map_size if _battle_data else Vector2(3072, 2304)
		var world_pos := Vector2(gx * cell_size, gy * cell_size) - (map_size * 0.5)

		var center := world_pos + Vector2(cell_size * 0.5, cell_size * 0.5)
		var r := cell_size * 0.55

		# Solid black core dot for the home base (permanent emitter)
		draw_circle(center, r, Color(0.05, 0.05, 0.05, 1.0))
		# Bright center highlight so it pops even on dark terrain
		draw_circle(center, r * 0.45, Color(0.9, 0.9, 0.85, 0.9))

		# Team ring (blue for friendly/home1, red for hostile/home2)
		var ring_color := Color(0.25, 0.55, 0.95, 0.95) if team == 1 else Color(0.95, 0.35, 0.25, 0.95)
		draw_arc(center, r * 1.35, 0, TAU, 20, ring_color, 3.5)
		# Inner ring for definition
		draw_arc(center, r * 1.15, 0, TAU, 20, Color(1, 1, 1, 0.6), 1.5)
