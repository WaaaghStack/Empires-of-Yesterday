class_name BattleTileFluidField
extends RefCounted

const BattleTileControlLib := preload("res://BattleTileControl.gd")

const DIFFUSE_PASSES := 5
const PRESSURE_UNIT_PULSE := 0.85
const PRESSURE_CREEP := 0.55
const FRONTIER_BLEND := 0.42
## v2 tape codec tops out near MAX_PRESSURE_V2; keep display reference aligned.
const FLUID_ALPHA_PRESSURE_MAX := 100000.0
const DISPLAY_PRESSURE_REFERENCE := 10000.0
const FLUID_ALPHA_EXPONENT := 0.48
const INTERIOR_FILL_ALPHA := 0.5
const FRONT_LINE_ALPHA := 1.0
const FRONT_RGB_BOOST := 1.35
const DISPLAY_MIN_INTENSITY := 0.22
const DISPLAY_NORMALIZE_PER_FRAME := true

const _TEAM_NONE := 0
const _TEAM_FRIENDLY := 1
const _TEAM_HOSTILE := 2
const _TEAM_TIE := 3


## Build a smooth Creeper-style influence image from discrete tile owners.
## Rect battle maps only — sphere WC fluid is owned by EarthGlobeMap.
static func build_fluid_image(map_data, owners: PackedByteArray, diffuse_passes: int = DIFFUSE_PASSES, power_scale: float = 1.0) -> Image:
	if map_data == null or owners.is_empty():
		return null
	if map_data.sphere_mode:
		push_warning(
			"BattleTileFluidField.build_fluid_image: rect fluid bake skipped in sphere WC "
			+ "(EarthGlobeMap owns fluid)."
		)
		return null
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	var friendly: PackedFloat32Array = PackedFloat32Array()
	var hostile: PackedFloat32Array = PackedFloat32Array()
	friendly.resize(n)
	hostile.resize(n)
	friendly.fill(0.0)
	hostile.fill(0.0)
	for idx in range(mini(n, owners.size())):
		match int(owners[idx]):
			BattleTileControlLib.OWNER_FRIENDLY:
				friendly[idx] = 1.0
			BattleTileControlLib.OWNER_HOSTILE:
				hostile[idx] = 1.0
			BattleTileControlLib.OWNER_CONTESTED:
				friendly[idx] = FRONTIER_BLEND
				hostile[idx] = FRONTIER_BLEND
			_:
				pass
	var passes: int = maxi(1, diffuse_passes)
	for _pass in range(passes):
		friendly = _diffuse_layer(map_data, friendly)
		hostile = _diffuse_layer(map_data, hostile)
	return _pressures_to_image(map_data, friendly, hostile, power_scale)


static func blend_owner_frames(
	map_data,
	owners_a: PackedByteArray,
	owners_b: PackedByteArray,
	blend: float,
) -> PackedByteArray:
	if map_data == null:
		return owners_a
	var t: float = clampf(blend, 0.0, 1.0)
	if t <= 0.001:
		return owners_a
	if t >= 0.999:
		return owners_b
	var pa: PackedFloat32Array = PackedFloat32Array()
	var pb: PackedFloat32Array = PackedFloat32Array()
	var ha: PackedFloat32Array = PackedFloat32Array()
	var hb: PackedFloat32Array = PackedFloat32Array()
	_owners_to_pressures(map_data, owners_a, pa, ha)
	_owners_to_pressures(map_data, owners_b, pb, hb)
	var n: int = pa.size()
	for i in range(n):
		pa[i] = lerpf(pa[i], pb[i], t)
		ha[i] = lerpf(ha[i], hb[i], t)
	return _pressures_to_owners(map_data, pa, ha)


static func soften_owners_for_display(map_data, owners: PackedByteArray) -> PackedByteArray:
	if map_data == null or owners.is_empty():
		return owners
	var out: PackedByteArray = owners.duplicate()
	var n: int = out.size()
	# Creep: neutral cells adopt neighbor majority (organic spread, kills column artifacts).
	for _iter in range(2):
		var next: PackedByteArray = out.duplicate()
		for gy in range(map_data.grid_height):
			for gx in range(map_data.grid_width):
				var idx: int = map_data.cell_index(gx, gy)
				if idx < 0 or idx >= n:
					continue
				if int(out[idx]) == BattleTileControlLib.OWNER_UNCLAIMABLE:
					continue
				if int(out[idx]) != BattleTileControlLib.OWNER_NEUTRAL:
					continue
				var f_n: int = 0
				var h_n: int = 0
				for d in _NEIGHBOR_DIRS:
					var nx: int = gx + d.x
					var ny: int = gy + d.y
					if nx < 0 or ny < 0 or nx >= map_data.grid_width or ny >= map_data.grid_height:
						continue
					var ni: int = map_data.cell_index(nx, ny)
					match int(out[ni]):
						BattleTileControlLib.OWNER_FRIENDLY:
							f_n += 1
						BattleTileControlLib.OWNER_HOSTILE:
							h_n += 1
						BattleTileControlLib.OWNER_CONTESTED:
							f_n += 1
							h_n += 1
				if f_n > h_n and f_n >= 2:
					next[idx] = BattleTileControlLib.OWNER_FRIENDLY
				elif h_n > f_n and h_n >= 2:
					next[idx] = BattleTileControlLib.OWNER_HOSTILE
		out = next
	# Collapse contested stripes into soft frontier ownership.
	for idx in range(n):
		if int(out[idx]) != BattleTileControlLib.OWNER_CONTESTED:
			continue
		var gx: int = idx % map_data.grid_width
		var gy: int = idx / map_data.grid_width
		var f_n: int = 0
		var h_n: int = 0
		for d in _NEIGHBOR_DIRS:
			var ni: int = map_data.cell_index(gx + d.x, gy + d.y)
			if ni < 0 or ni >= n:
				continue
			match int(out[ni]):
				BattleTileControlLib.OWNER_FRIENDLY:
					f_n += 1
				BattleTileControlLib.OWNER_HOSTILE:
					h_n += 1
		if f_n >= h_n:
			out[idx] = BattleTileControlLib.OWNER_FRIENDLY
		else:
			out[idx] = BattleTileControlLib.OWNER_HOSTILE
	return out


const _NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


static func _owners_to_pressures(
	map_data,
	owners: PackedByteArray,
	out_friendly: PackedFloat32Array,
	out_hostile: PackedFloat32Array,
) -> void:
	var n: int = map_data.grid_width * map_data.grid_height
	out_friendly.resize(n)
	out_hostile.resize(n)
	out_friendly.fill(0.0)
	out_hostile.fill(0.0)
	for idx in range(mini(n, owners.size())):
		match int(owners[idx]):
			BattleTileControlLib.OWNER_FRIENDLY:
				out_friendly[idx] = 1.0
			BattleTileControlLib.OWNER_HOSTILE:
				out_hostile[idx] = 1.0
			BattleTileControlLib.OWNER_CONTESTED:
				out_friendly[idx] = FRONTIER_BLEND
				out_hostile[idx] = FRONTIER_BLEND
			_:
				pass


static func _pressures_to_owners(
	map_data,
	friendly: PackedFloat32Array,
	hostile: PackedFloat32Array,
) -> PackedByteArray:
	var n: int = map_data.grid_width * map_data.grid_height
	var out: PackedByteArray = PackedByteArray()
	out.resize(n)
	out.fill(BattleTileControlLib.OWNER_NEUTRAL)
	for idx in range(n):
		var gx: int = idx % map_data.grid_width
		var gy: int = idx / map_data.grid_width
		if not map_data.is_land_cell(gx, gy):
			out[idx] = BattleTileControlLib.OWNER_UNCLAIMABLE
			continue
		var f: float = friendly[idx] if idx < friendly.size() else 0.0
		var h: float = hostile[idx] if idx < hostile.size() else 0.0
		if f < 0.12 and h < 0.12:
			out[idx] = BattleTileControlLib.OWNER_NEUTRAL
		elif f > h * 1.15:
			out[idx] = BattleTileControlLib.OWNER_FRIENDLY
		elif h > f * 1.15:
			out[idx] = BattleTileControlLib.OWNER_HOSTILE
		else:
			out[idx] = BattleTileControlLib.OWNER_CONTESTED
	return out


static func _diffuse_layer(map_data, layer: PackedFloat32Array) -> PackedFloat32Array:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			if not _cell_diffuses(map_data, gx, gy):
				out[idx] = 0.0
				continue
			var sum: float = layer[idx] * 2.0
			var count: float = 2.0
			for d in _NEIGHBOR_DIRS:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if not _cell_diffuses(map_data, nx, ny):
					continue
				var ni: int = map_data.cell_index(nx, ny)
				sum += layer[ni]
				count += 1.0
			out[idx] = sum / count
	return out


static func _cell_diffuses(map_data, gx: int, gy: int) -> bool:
	if not map_data.is_passable(gx, gy):
		return false
	return map_data.is_land_cell(gx, gy)


static func _pressures_to_image(
	map_data,
	friendly: PackedFloat32Array,
	hostile: PackedFloat32Array,
	power_scale: float = 1.0,
) -> Image:
	return _image_from_peak_power_grid(map_data, friendly, hostile, power_scale, 1.0)


static func sum_pressure_array(layer: PackedFloat32Array) -> float:
	var total: float = 0.0
	for v in layer:
		total += v
	return total


static func cumulative_power_totals(
	friendly_power: PackedFloat32Array,
	hostile_power: PackedFloat32Array,
) -> Vector2:
	return Vector2(sum_pressure_array(friendly_power), sum_pressure_array(hostile_power))


static func _dominant_team(friendly_power: float, hostile_power: float, power_eps: float) -> int:
	var peak: float = maxf(friendly_power, hostile_power)
	if peak < power_eps:
		return _TEAM_NONE
	if friendly_power > hostile_power:
		return _TEAM_FRIENDLY
	if hostile_power > friendly_power:
		return _TEAM_HOSTILE
	return _TEAM_TIE


static func _team_base_color(team: int) -> Color:
	match team:
		_TEAM_FRIENDLY:
			return Color(0.18, 0.55, 0.95, 1.0)
		_TEAM_HOSTILE:
			return Color(0.95, 0.32, 0.22, 1.0)
		_TEAM_TIE:
			return Color(1.0, 0.85, 0.35, 1.0)
		_:
			return Color(0, 0, 0, 0)


static func _peak_intensity(
	peak: float,
	power_scale: float,
	pressure_max: float,
	frame_peak_max: float = -1.0,
) -> float:
	var pscale: float = clampf(power_scale, 0.01, 1.0)
	if DISPLAY_NORMALIZE_PER_FRAME and frame_peak_max > 0.01:
		var norm: float = clampf(peak / frame_peak_max, 0.0, 1.0)
		return clampf(
			pow(norm, 0.65) * pscale,
			DISPLAY_MIN_INTENSITY,
			1.0,
		)
	var denom: float = maxf(1.0, pressure_max)
	return clampf(
		pow(peak / denom, FLUID_ALPHA_EXPONENT) * pscale,
		DISPLAY_MIN_INTENSITY,
		1.0,
	)


static func _frame_peak_max_on_land(
	map_data,
	peaks: PackedFloat32Array,
) -> float:
	var frame_peak: float = 0.0
	for idx in range(peaks.size()):
		if peaks[idx] <= 0.0:
			continue
		var gx: int = idx % map_data.grid_width
		var gy: int = idx / map_data.grid_width
		if map_data.is_land_cell(gx, gy):
			frame_peak = maxf(frame_peak, peaks[idx])
	return frame_peak


## Build directly from per-tile power values (raw accumulated power per team on each tile).
static func build_fluid_image_from_powers(
	map_data,
	friendly_power: PackedFloat32Array,
	hostile_power: PackedFloat32Array,
	power_scale: float = 1.0,
	diffuse_passes: int = 0,
) -> Image:
	if map_data == null or friendly_power.is_empty() or hostile_power.is_empty():
		return null
	if map_data.sphere_mode:
		push_warning(
			"BattleTileFluidField.build_fluid_image_from_powers: rect fluid bake skipped in sphere WC "
			+ "(EarthGlobeMap owns fluid)."
		)
		return null
	var f: PackedFloat32Array = friendly_power
	var hs: PackedFloat32Array = hostile_power
	if diffuse_passes > 0:
		f = friendly_power.duplicate()
		hs = hostile_power.duplicate()
		for _p in range(diffuse_passes):
			f = _diffuse_layer(map_data, f)
			hs = _diffuse_layer(map_data, hs)
	return _powers_to_image(map_data, f, hs, friendly_power, hostile_power, power_scale)


static func _powers_to_image(
	map_data,
	_diff_f: PackedFloat32Array,
	_diff_h: PackedFloat32Array,
	raw_f: PackedFloat32Array,
	raw_h: PackedFloat32Array,
	power_scale: float = 1.0,
) -> Image:
	return _image_from_peak_power_grid(map_data, raw_f, raw_h, power_scale)


static func _image_from_peak_power_grid(
	map_data,
	friendly_power: PackedFloat32Array,
	hostile_power: PackedFloat32Array,
	power_scale: float = 1.0,
	pressure_max: float = FLUID_ALPHA_PRESSURE_MAX,
) -> Image:
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var n: int = w * h
	var pscale: float = clampf(power_scale, 0.01, 1.0)
	const POWER_EPS := 0.01

	var teams := PackedByteArray()
	teams.resize(n)
	var peaks := PackedFloat32Array()
	peaks.resize(n)

	for gy in range(h):
		for gx in range(w):
			if not map_data.is_land_cell(gx, gy):
				continue
			var idx: int = map_data.cell_index(gx, gy)
			var raw_pf: float = friendly_power[idx] if idx < friendly_power.size() else 0.0
			var raw_ph: float = hostile_power[idx] if idx < hostile_power.size() else 0.0
			peaks[idx] = maxf(raw_pf, raw_ph)
			teams[idx] = _dominant_team(raw_pf, raw_ph, POWER_EPS)

	var frame_peak_max: float = _frame_peak_max_on_land(map_data, peaks)
	var pressure_ref: float = (
		frame_peak_max if DISPLAY_NORMALIZE_PER_FRAME and frame_peak_max > 0.01
		else DISPLAY_PRESSURE_REFERENCE
	)

	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	const CARDINAL: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]

	for gy in range(h):
		for gx in range(w):
			var idx: int = map_data.cell_index(gx, gy)
			var bi: int = (gy * w + gx) * 4
			if not map_data.is_land_cell(gx, gy):
				continue
			var team: int = int(teams[idx])
			if team == _TEAM_NONE:
				continue
			var peak: float = peaks[idx]
			var intensity: float = _peak_intensity(
				peak, pscale, pressure_ref, frame_peak_max
			)
			if intensity < 0.001:
				continue

			var is_front: bool = false
			for d in CARDINAL:
				var nx: int = gx + d.x
				var ny: int = gy + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					is_front = true
					break
				if not map_data.is_land_cell(nx, ny):
					is_front = true
					break
				var ni: int = map_data.cell_index(nx, ny)
				if int(teams[ni]) != team:
					is_front = true
					break

			var base: Color = _team_base_color(team)
			var fill_alpha: float = (
				FRONT_LINE_ALPHA if is_front else INTERIOR_FILL_ALPHA
			) * intensity
			var rgb_boost: float = FRONT_RGB_BOOST if is_front else 1.0
			bytes[bi] = int(clampf(base.r * rgb_boost, 0.0, 1.0) * 255.0)
			bytes[bi + 1] = int(clampf(base.g * rgb_boost, 0.0, 1.0) * 255.0)
			bytes[bi + 2] = int(clampf(base.b * rgb_boost, 0.0, 1.0) * 255.0)
			bytes[bi + 3] = int(fill_alpha * 255.0)

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	return img
