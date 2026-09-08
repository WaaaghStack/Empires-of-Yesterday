extends Control

## HD-2D battle viewer. Plays a baked battle (from TwoWorldsEngine) as a 3D diorama: a themed
## ground plane with GPU-instanced Y-axis billboards, traveling shot streaks from baked fire ticks,
## brief hit flashes, and a free orbit camera. Soldiers use an 8-frame run/shoot sheet driven by
## baked ST_MARCH / ST_ROUT / ST_FIRE. Godot interpolates the bake — it does not pick targets or
## apply damage. Emits `finished` when the viewer is dismissed.

signal finished

const UiTheme := preload("res://GameTheme.gd")
const BillboardShaderPath := "res://shaders/battle_billboard.gdshader"
const DioramaShaderPath := "res://shaders/battle_diorama.gdshader"
const TracerShaderPath := "res://shaders/battle_tracer.gdshader"
const FxShaderPath := "res://shaders/battle_fx.gdshader"
const FxMuzzlePath := "res://assets/fx/battle/muzzle.png"
const FxSparkPath := "res://assets/fx/battle/spark.png"
const FxBombPath := "res://assets/fx/battle/bomb.png"
const FxTracerPath := "res://assets/fx/battle/tracer.png"
const MAX_MUZZLES := 96
const MAX_SPARKS := 96
# Bucket order: 0 = friendly soldier, 1 = hostile soldier, 2 = friendly bomber, 3 = hostile bomber.
const TEX := [
	preload("res://assets/units/soldier_friendly.png"),
	preload("res://assets/units/soldier_hostile.png"),
	preload("res://assets/units/bomber_friendly.png"),
	preload("res://assets/units/bomber_hostile.png"),
]
const SOLDIER_SHEET := [
	"res://assets/units/soldier_friendly_sheet.png",
	"res://assets/units/soldier_hostile_sheet.png",
]
const SOLDIER_SHEET_COLS := 8
const SCALE := 1.0
const SPRITE_SIZE := 3.2
const BOMBER_SIZE := 5.2
const GROUND_Y := 0.0
const BUF_STRIDE := 16
const ST_IDLE := 0
const ST_MARCH := 1
const ST_AIM := 2
const ST_FIRE := 3
const ST_DEAD := 4
const ST_ROUT := 5
const ST_FLED := 6
const ST_HIT := 7
const MAX_TRACERS := 160
const MAX_PUFFS := 72
const XFORM_STRIDE := 12
const HIT_FLASH := 0.10
const HIT_GAP := 0.18
const SHOT_SPEED := 160.0
const BOMB_SPEED := 58.0
const STREAK_LEN := 1.55
const MUZZLE_LIFE := 0.055

var _engine: Object
var _index: int = 0
var _w: float = 200.0
var _h: float = 120.0
var _elev: float = 30.0
var _river_x: float = 100.0
var _hill_x: float = 52.0
var _hill_y: float = 92.0
var _hill_r: float = 28.0
var _hill_block_r: float = 28.0 * 0.92
var _frame_count: int = 0
var _unit_count: int = 0
var _fac := PackedByteArray()
var _kind := PackedByteArray()
var _summary: Dictionary = {}

var _frame_pos: float = 0.0
var _play_fps: float = 3.0
var _speed: float = 1.0
var _playing: bool = true
var _done: bool = false
var _cache := {}

var _sub: SubViewport
var _cam: Camera3D
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _props: Node3D
var _mmi := [null, null, null, null]
var _buf0 := PackedFloat32Array()
var _buf1 := PackedFloat32Array()
var _buf2 := PackedFloat32Array()
var _buf3 := PackedFloat32Array()
var _bkt := PackedByteArray()
var _off := PackedInt32Array()
var _tracer_mmi: MultiMeshInstance3D
var _tracer_buf := PackedFloat32Array()
var _puff_mmi: MultiMeshInstance3D
var _puff_buf := PackedFloat32Array()
var _muzzle_mmi: MultiMeshInstance3D
var _muzzle_buf := PackedFloat32Array()
var _spark_mmi: MultiMeshInstance3D
var _spark_buf := PackedFloat32Array()
var _sheet_cols := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var _yaw := 0.42
var _pitch := 0.52
var _dist := 175.0
var _look := Vector3.ZERO
var _orbit := false

var _header: Label
var _progress: Label
var _back_btn: Button
var _speed_btns := []
var _audio_fire: AudioStreamPlayer
var _audio_hit: AudioStreamPlayer
var _audio_rout: AudioStreamPlayer
var _snd_cool: float = 0.0
var _rout_played: bool = false
var _shots: Array = []
var _shot_cd := PackedFloat32Array()
var _hit_t := PackedFloat32Array()
var _hit_gap := PackedFloat32Array()


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(true)
	_build_3d()
	_build_hud()
	_build_audio()


func _build_3d() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_sub = SubViewport.new()
	_sub.own_world_3d = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_sub)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.46, 0.58, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.62, 0.78)
	env.ambient_light_energy = 0.38
	env.fog_enabled = true
	env.fog_light_color = Color(0.50, 0.60, 0.68)
	env.fog_density = 0.0010
	_cam.environment = env
	_sub.add_child(_cam)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 42.0, 0.0)
	sun.light_energy = 1.22
	sun.light_color = Color(1.0, 0.90, 0.74)
	sun.shadow_enabled = false
	_sub.add_child(sun)

	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(_w * SCALE * 1.35, _h * SCALE * 1.7)
	_ground.mesh = pm
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load(DioramaShaderPath)
	_ground.set_surface_override_material(0, _ground_mat)
	_sub.add_child(_ground)

	var shader: Shader = load(BillboardShaderPath)
	for id in range(4):
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mm.mesh = quad
		mm.instance_count = 0
		mmi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var tex: Texture2D = TEX[id]
		var cols := 1.0
		if id < 2:
			var sheet := _load_tex(SOLDIER_SHEET[id])
			if sheet != null:
				tex = sheet
				cols = float(SOLDIER_SHEET_COLS)
		_sheet_cols[id] = cols
		mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("sheet_cols", cols)
		mat.set_shader_parameter("sheet_rows", 1.0)
		mmi.material_override = mat
		mmi.position = Vector3(0.0, 0.02, 0.0)
		_sub.add_child(mmi)
		_mmi[id] = mmi

	_tracer_mmi = _make_fx_mmi(load(TracerShaderPath), Vector2(1.0, 1.0), MAX_TRACERS, false)
	var tracer_tex := _load_tex(FxTracerPath)
	if _tracer_mmi.material_override is ShaderMaterial and tracer_tex != null:
		(_tracer_mmi.material_override as ShaderMaterial).set_shader_parameter("streak", tracer_tex)
	_puff_mmi = _make_tex_mmi(_load_tex(FxBombPath), Vector2(1.0, 1.0), MAX_PUFFS)
	_muzzle_mmi = _make_tex_mmi(_load_tex(FxMuzzlePath), Vector2(1.0, 1.0), MAX_MUZZLES)
	_spark_mmi = _make_tex_mmi(_load_tex(FxSparkPath), Vector2(1.0, 1.0), MAX_SPARKS)

	_props = Node3D.new()
	_sub.add_child(_props)
	_apply_camera()


func _make_fx_mmi(shader: Shader, quad_size: Vector2, count: int, puff: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = quad_size
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mmi.material_override = mat
	else:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.82, 0.35, 0.55) if puff else Color(0.92, 0.88, 0.55)
		mmi.material_override = mat
	_sub.add_child(mmi)
	return mmi


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null


func _make_tex_mmi(tex: Texture2D, quad_size: Vector2, count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = quad_size
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load(FxShaderPath)
	if tex != null:
		mat.set_shader_parameter("tex", tex)
	mmi.material_override = mat
	_sub.add_child(mmi)
	return mmi


func _build_hud() -> void:
	_header = Label.new()
	_header.position = Vector2(24, 18)
	_header.add_theme_font_size_override("font_size", 18)
	_header.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	add_child(_header)

	_progress = Label.new()
	_progress.position = Vector2(24, 46)
	_progress.add_theme_font_size_override("font_size", 13)
	_progress.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	add_child(_progress)

	var speeds := [["Pause", 0.0], ["0.25x", 0.25], ["0.5x", 0.5], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0], ["8x", 8.0]]
	var x := 24.0
	for sp in speeds:
		var b := Button.new()
		b.text = sp[0]
		b.position = Vector2(x, 74)
		b.size = Vector2(72, 32)
		var v: float = sp[1]
		b.set_meta("rate", v)
		b.pressed.connect(func(): _set_speed(v))
		UiTheme.apply_ghost_button(b)
		add_child(b)
		_speed_btns.append(b)
		x += 78.0
	_set_speed(1.0)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.anchor_left = 1.0
	_back_btn.anchor_top = 1.0
	_back_btn.anchor_right = 1.0
	_back_btn.anchor_bottom = 1.0
	_back_btn.offset_left = -184.0
	_back_btn.offset_top = -64.0
	_back_btn.offset_right = -24.0
	_back_btn.offset_bottom = -16.0
	_back_btn.pressed.connect(_on_back)
	UiTheme.apply_primary_button(_back_btn)
	add_child(_back_btn)


func _build_audio() -> void:
	_audio_fire = AudioStreamPlayer.new()
	_audio_fire.stream = _make_tone(1800.0, 42.0, 0.22, true)
	_audio_fire.volume_db = -14.0
	add_child(_audio_fire)
	_audio_hit = AudioStreamPlayer.new()
	_audio_hit.stream = _make_tone(140.0, 70.0, 0.28, true)
	_audio_hit.volume_db = -16.0
	add_child(_audio_hit)
	_audio_rout = AudioStreamPlayer.new()
	_audio_rout.stream = _make_tone(420.0, 220.0, 0.18, false)
	_audio_rout.volume_db = -12.0
	add_child(_audio_rout)


func _make_tone(freq: float, ms: float, vol: float, noisy: bool) -> AudioStreamWAV:
	var sr := 22050
	var n := int(sr * ms / 1000.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(sr)
		var env := 1.0 - float(i) / float(maxi(n, 1))
		var s := sin(TAU * freq * t) * env * vol
		if noisy:
			s += (randf() - 0.5) * 0.22 * env
		var v := clampi(int(s * 32767.0), -32767, 32767)
		data[i * 2] = v & 255
		data[i * 2 + 1] = (v >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sr
	stream.stereo = false
	stream.data = data
	return stream


func _set_speed(v: float) -> void:
	if v <= 0.0:
		_playing = false
	else:
		_playing = true
		_speed = v
	for b in _speed_btns:
		if not (b is Button):
			continue
		var rate := float(b.get_meta("rate", -1.0))
		if is_equal_approx(rate, v):
			UiTheme.apply_latched_button(b)
		else:
			UiTheme.apply_ghost_button(b)


func play_engine_battle(engine: Object, index: int, summary: Dictionary = {}) -> void:
	_engine = engine
	_index = index
	_summary = summary
	var meta: Dictionary = engine.get_last_battle_meta(index)
	_w = float(meta.get("width", 200.0))
	_h = float(meta.get("height", 120.0))
	_elev = float(meta.get("elevation", 30.0))
	_river_x = float(meta.get("river_x", _w * 0.5))
	_hill_x = float(meta.get("hill_x", 52.0))
	_hill_y = float(meta.get("hill_y", 92.0))
	_hill_r = float(meta.get("hill_r", 28.0))
	_hill_block_r = float(meta.get("hill_block_r", _hill_r * 0.92))
	_frame_count = int(meta.get("frame_count", 0))
	_unit_count = int(meta.get("unit_count", 0))
	_fac = meta.get("fac", PackedByteArray())
	_kind = meta.get("kind", PackedByteArray())
	if summary.is_empty():
		_summary = {
			"province": int(meta.get("province", -1)),
			"attacker": int(meta.get("attacker", 0)),
			"defender": int(meta.get("defender", 1)),
			"winner": int(meta.get("winner", -1)),
			"owner_after": int(meta.get("owner_after", -1)),
		}
	_cache.clear()
	_frame_pos = 0.0
	_speed = 1.0
	_playing = true
	_look = Vector3.ZERO
	_done = false
	_rout_played = false
	_snd_cool = 0.0
	if _ground and _ground.mesh is PlaneMesh:
		(_ground.mesh as PlaneMesh).size = Vector2(_w * SCALE * 1.35, _h * SCALE * 1.7)
	_apply_diorama_uniforms()
	_rebuild_props()
	_dist = clampf(maxf(_w, _h) * 0.95, 90.0, 2200.0)
	# 1x is the human-readable pace (what 0.5x used to look like). Buttons stay 1x / 2x / …
	var duration: float = clampf(float(_frame_count) * 0.28, 48.0, 360.0)
	_play_fps = float(maxi(_frame_count, 1)) / duration * 0.5
	_prepare_buckets()
	_apply_camera()
	visible = true
	_set_speed(1.0)
	_render_frame()
	_update_header()


func _apply_diorama_uniforms() -> void:
	if _ground_mat == null:
		return
	_ground_mat.set_shader_parameter("width", _w)
	_ground_mat.set_shader_parameter("height", _h)
	_ground_mat.set_shader_parameter("elevation", _elev)
	_ground_mat.set_shader_parameter("river_x", _river_x)
	_ground_mat.set_shader_parameter("hill_x", _hill_x)
	_ground_mat.set_shader_parameter("hill_y", _hill_y)
	_ground_mat.set_shader_parameter("hill_r", _hill_r)


func _battle_to_world(px: float, py: float) -> Vector3:
	var hw := _w * 0.5
	var hh := _h * 0.5
	return Vector3((clampf(px, 0.0, _w) - hw) * SCALE, GROUND_Y, (clampf(py, 0.0, _h) - hh) * SCALE)


func _rebuild_props() -> void:
	if _props == null:
		return
	for c in _props.get_children():
		c.queue_free()
	var hill_h := 3.2 + _elev * 0.06 + _hill_block_r * 0.045
	var hill := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.4
	hill.mesh = sm
	var wp := _battle_to_world(_hill_x, _hill_y)
	hill.position = Vector3(wp.x, hill_h * 0.35, wp.z)
	hill.scale = Vector3(_hill_block_r, hill_h, _hill_block_r)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.36, 0.34, 0.28)
	hmat.roughness = 1.0
	hill.set_surface_override_material(0, hmat)
	_props.add_child(hill)
	var ms := _w / 200.0
	_add_box(Vector3(_battle_to_world(18.0 * ms, 10.0 * ms).x, 1.1, _battle_to_world(18.0 * ms, 10.0 * ms).z), Vector3(2.2, 2.2, 1.4), Color(0.42, 0.40, 0.36))
	_add_box(Vector3(_battle_to_world(22.0 * ms, 12.0 * ms).x, 0.7, _battle_to_world(22.0 * ms, 12.0 * ms).z), Vector3(1.4, 1.4, 2.6), Color(0.38, 0.36, 0.32))
	_add_box(Vector3(_battle_to_world(_w - 16.0 * ms, _h - 12.0 * ms).x, 0.55, _battle_to_world(_w - 16.0 * ms, _h - 12.0 * ms).z), Vector3(2.4, 1.1, 1.2), Color(0.40, 0.28, 0.16))
	_add_tree(_battle_to_world(14.0 * ms, _h - 14.0 * ms))
	_add_tree(_battle_to_world(_w - 18.0 * ms, 14.0 * ms))
	_add_tree(_battle_to_world(_hill_x - 10.0 * ms, _hill_y + 8.0 * ms))


func _add_box(pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.9
	mi.set_surface_override_material(0, mat)
	_props.add_child(mi)


func _add_tree(base: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.28
	cyl.height = 2.4
	trunk.mesh = cyl
	trunk.position = base + Vector3(0.0, 1.2, 0.0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.28, 0.18, 0.10)
	trunk.set_surface_override_material(0, tmat)
	_props.add_child(trunk)
	var crown := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.15
	sph.height = 2.1
	crown.mesh = sph
	crown.position = base + Vector3(0.0, 2.8, 0.0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.16, 0.32, 0.14)
	crown.set_surface_override_material(0, cmat)
	_props.add_child(crown)


func _prepare_buckets() -> void:
	_bkt = PackedByteArray()
	_off = PackedInt32Array()
	_bkt.resize(_unit_count)
	_off.resize(_unit_count)
	var counts := [0, 0, 0, 0]
	for i in range(_unit_count):
		var fac := int(_fac[i]) if i < _fac.size() else 0
		var knd := int(_kind[i]) if i < _kind.size() else 0
		var id := (fac & 1) + (knd & 1) * 2
		_bkt[i] = id
		_off[i] = counts[id] * BUF_STRIDE
		counts[id] += 1
	_buf0 = _make_buf(counts[0], SPRITE_SIZE)
	_buf1 = _make_buf(counts[1], SPRITE_SIZE)
	_buf2 = _make_buf(counts[2], BOMBER_SIZE)
	_buf3 = _make_buf(counts[3], BOMBER_SIZE)
	for id in range(4):
		(_mmi[id].multimesh as MultiMesh).instance_count = counts[id]
	_tracer_buf = _zero_xform(MAX_TRACERS)
	_puff_buf = _zero_xform(MAX_PUFFS)
	_muzzle_buf = _zero_xform(MAX_MUZZLES)
	_spark_buf = _zero_xform(MAX_SPARKS)
	_reset_fx_state()


func _reset_fx_state() -> void:
	_shots.clear()
	_shot_cd.resize(_unit_count)
	_hit_t.resize(_unit_count)
	_hit_gap.resize(_unit_count)
	_shot_cd.fill(0.0)
	_hit_t.fill(0.0)
	_hit_gap.fill(0.0)


func _make_buf(count: int, sz: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(count * BUF_STRIDE)
	for k in range(count):
		var o := k * BUF_STRIDE
		buf[o + 0] = sz
		buf[o + 5] = sz
		buf[o + 10] = sz
	return buf


func _zero_xform(count: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(count * XFORM_STRIDE)
	return buf


func _frame(idx: int) -> Dictionary:
	idx = clampi(idx, 0, maxi(_frame_count - 1, 0))
	if _cache.has(idx):
		return _cache[idx]
	var f: Dictionary = _engine.get_last_battle_frame_xy(_index, idx)
	if _cache.size() > 6:
		_cache.clear()
	_cache[idx] = f
	return f


func _lod() -> int:
	if _dist > 1400.0:
		return 2
	if _dist > 700.0:
		return 1
	return 0


func _process(delta: float) -> void:
	if not visible:
		return
	if _playing and not _done:
		_frame_pos += _play_fps * _speed * delta
		if _frame_pos >= float(_frame_count - 1):
			_frame_pos = float(maxi(_frame_count - 1, 0))
			_done = true
	if _playing:
		_age_fx(_speed * delta)
	_snd_cool = maxf(_snd_cool - delta, 0.0)
	if _pan_camera(delta):
		_apply_camera()
	_render_frame()
	_update_header()


func _age_fx(dt: float) -> void:
	if dt <= 0.0:
		return
	var i := 0
	while i < _shots.size():
		var shot: Dictionary = _shots[i]
		shot.t = float(shot.t) + dt
		if float(shot.t) >= float(shot.life):
			_shots.remove_at(i)
		else:
			_shots[i] = shot
			i += 1
	var n := _hit_t.size()
	for u in range(n):
		if _hit_t[u] > 0.0:
			_hit_t[u] = maxf(_hit_t[u] - dt, 0.0)
			if _hit_t[u] <= 0.0:
				_hit_gap[u] = HIT_GAP
		elif _hit_gap[u] > 0.0:
			_hit_gap[u] = maxf(_hit_gap[u] - dt, 0.0)
		if u < _shot_cd.size() and _shot_cd[u] > 0.0:
			_shot_cd[u] = maxf(_shot_cd[u] - dt, 0.0)


func _render_frame() -> void:
	if _frame_count <= 0 or _unit_count <= 0:
		return
	var a := int(floor(_frame_pos))
	var b := mini(a + 1, _frame_count - 1)
	var alpha := _frame_pos - float(a)
	var fa := _frame(a)
	var fb := _frame(b)
	var xa: PackedFloat32Array = fa.get("x", PackedFloat32Array())
	var ya: PackedFloat32Array = fa.get("y", PackedFloat32Array())
	var za: PackedFloat32Array = fa.get("z", PackedFloat32Array())
	var aa: PackedByteArray = fa.get("alive", PackedByteArray())
	var fa_face: PackedByteArray = fa.get("facing", PackedByteArray())
	var fa_st: PackedByteArray = fa.get("state", PackedByteArray())
	var axa: PackedFloat32Array = fa.get("aim_x", PackedFloat32Array())
	var aya: PackedFloat32Array = fa.get("aim_y", PackedFloat32Array())
	var xb: PackedFloat32Array = fb.get("x", PackedFloat32Array())
	var yb: PackedFloat32Array = fb.get("y", PackedFloat32Array())
	var zb: PackedFloat32Array = fb.get("z", PackedFloat32Array())
	var ab: PackedByteArray = fb.get("alive", PackedByteArray())
	var fb_st: PackedByteArray = fb.get("state", PackedByteArray())
	var lod := _lod()
	var n := mini(_unit_count, xa.size())
	var hw := _w * 0.5
	var hh := _h * 0.5
	var tracer_i := 0
	var puff_i := 0
	var muzzle_i := 0
	var spark_i := 0
	var fire_n := 0
	var hit_n := 0
	var rout_n := 0
	_tracer_buf.fill(0.0)
	_puff_buf.fill(0.0)
	_muzzle_buf.fill(0.0)
	_spark_buf.fill(0.0)
	for i in range(n):
		var id := _bkt[i]
		var o := _off[i]
		var alive_a := i < aa.size() and aa[i] != 0
		var alive_b := i < ab.size() and ab[i] != 0
		var st := int(fa_st[i]) if i < fa_st.size() else 0
		var st_b := int(fb_st[i]) if i < fb_st.size() else st
		var dead := (not alive_a) or st == ST_DEAD
		var dying := alive_a and (not alive_b or st_b == ST_DEAD) and not dead
		var fled_a := st == ST_FLED
		var fled_b := st_b == ST_FLED
		var firing := (not dead) and (not fled_a) and (st == ST_FIRE or st_b == ST_FIRE)
		var hit := (not dead) and (st == ST_HIT or st_b == ST_HIT)
		if i < _hit_t.size():
			if hit:
				if _hit_t[i] <= 0.0 and _hit_gap[i] <= 0.0:
					_hit_t[i] = HIT_FLASH
			else:
				_hit_gap[i] = 0.0
		var facing := int(fa_face[i]) if i < fa_face.size() else 0
		var flip := 1.0 if (facing >= 3 and facing <= 5) else 0.0
		var ax := xa[i]
		var ay := ya[i]
		var az := za[i] if i < za.size() else 0.0
		var bx := ax
		var by := ay
		var bz := az
		if i < xb.size():
			bx = xb[i]
			by = yb[i]
			if i < zb.size():
				bz = zb[i]
		var px: float = lerpf(ax, bx, alpha)
		var py: float = lerpf(ay, by, alpha)
		var pz: float = lerpf(az, bz, alpha)
		var wx := (clampf(px, 0.0, _w) - hw) * SCALE
		var wz := (clampf(py, 0.0, _h) - hh) * SCALE
		var far := lod == 2 and id < 2
		var base_sz := BOMBER_SIZE if id >= 2 else SPRITE_SIZE
		if far:
			base_sz *= 0.82
		var szx := base_sz
		var szy := base_sz
		var fade := 1.0
		if facing == 2 or facing == 6:
			szx *= 0.72
		elif facing == 1 or facing == 3 or facing == 5 or facing == 7:
			szx *= 0.86
		if fled_a and fled_b:
			fade = 0.0
			szx = 0.0
			szy = 0.0
		elif fled_b:
			fade = 1.0 - alpha
			szx = base_sz * (0.35 + 0.65 * fade)
			szy = base_sz * (0.35 + 0.65 * fade)
		elif fled_a:
			fade = 0.0
			szx = 0.0
			szy = 0.0
		elif dying:
			if pz > 0.55:
				szx = base_sz * 0.92
				szy = base_sz * 0.92
			else:
				szx = base_sz * 0.95
				szy = lerpf(base_sz, base_sz * 0.28, alpha)
		elif dead:
			if pz > 0.55:
				szx = base_sz * 0.92
				szy = base_sz * 0.88
			else:
				szx = base_sz * 0.95
				szy = base_sz * 0.28
		elif i < _hit_t.size() and _hit_t[i] > HIT_FLASH * 0.35:
			szy = base_sz * 0.90
		elif (st == ST_MARCH or st == ST_ROUT) and _sheet_cols[id] < 2.0:
			var bob := 1.0 + 0.045 * sin(_frame_pos * 9.0 + float(i))
			szy *= bob
		var yc := GROUND_Y + szy * 0.5 + pz * SCALE
		if (dead or dying) and pz < 0.45:
			yc = GROUND_Y + szy * 0.45
		elif fled_b and not fled_a:
			yc += (1.0 - fade) * 3.2
		var fire_ch := 0.0
		if i < _hit_t.size() and _hit_t[i] > 0.0:
			fire_ch = 0.28 + 0.32 * (_hit_t[i] / HIT_FLASH)
		_write_instance(
			id, o, szx, szy, wx, yc, wz,
			flip, _pose_frame(id, i, st, firing, dead or dying), fire_ch,
			1.0 if (dead or dying) else 0.0, fade
		)
		if firing:
			fire_n += 1
		if hit:
			hit_n += 1
		if st == ST_ROUT:
			rout_n += 1
		if firing and axa.size() == n and i < _shot_cd.size() and _shot_cd[i] <= 0.0:
			if lod < 2 or (i % 2) == 0:
				var tx := axa[i]
				var ty := aya[i] if i < aya.size() else 0.0
				if absf(tx) + absf(ty) > 1.0:
					var from := Vector3(wx, yc + 0.4, wz)
					var to := _battle_to_world(tx, ty)
					to.y = GROUND_Y + 0.9 if id < 2 else (GROUND_Y + 8.0)
					if _spawn_shot(from, to, id >= 2):
						_shot_cd[i] = (0.28 if id >= 2 else 0.11) + 0.06 * float((i * 13) % 11) / 10.0
		elif (not firing) and i < _shot_cd.size():
			_shot_cd[i] = 0.0
	var flying := _draw_flying_shots(tracer_i, muzzle_i, spark_i, puff_i)
	tracer_i = int(flying[0])
	muzzle_i = int(flying[1])
	spark_i = int(flying[2])
	puff_i = int(flying[3])
	if _mmi[0].multimesh.instance_count > 0:
		_mmi[0].multimesh.buffer = _buf0
	if _mmi[1].multimesh.instance_count > 0:
		_mmi[1].multimesh.buffer = _buf1
	if _mmi[2].multimesh.instance_count > 0:
		_mmi[2].multimesh.buffer = _buf2
	if _mmi[3].multimesh.instance_count > 0:
		_mmi[3].multimesh.buffer = _buf3
	_tracer_mmi.multimesh.buffer = _tracer_buf
	_tracer_mmi.multimesh.visible_instance_count = tracer_i
	_puff_mmi.multimesh.buffer = _puff_buf
	_puff_mmi.multimesh.visible_instance_count = puff_i
	_muzzle_mmi.multimesh.buffer = _muzzle_buf
	_muzzle_mmi.multimesh.visible_instance_count = muzzle_i
	_spark_mmi.multimesh.buffer = _spark_buf
	_spark_mmi.multimesh.visible_instance_count = spark_i
	_tick_audio(fire_n, hit_n, rout_n)


func _spawn_shot(from: Vector3, to: Vector3, air: bool) -> bool:
	var dist := from.distance_to(to)
	if dist < 0.4:
		return false
	if _shots.size() >= MAX_TRACERS:
		_shots.remove_at(0)
	var speed := BOMB_SPEED if air else SHOT_SPEED
	var max_life := 0.50 if air else 0.32
	var life := clampf(dist / speed, 0.06, max_life)
	_shots.append({
		"from": from,
		"to": to,
		"t": 0.0,
		"life": life,
		"air": air,
	})
	return true


func _draw_flying_shots(tracer_i: int, muzzle_i: int, spark_i: int, puff_i: int) -> PackedInt32Array:
	for raw in _shots:
		if tracer_i >= MAX_TRACERS:
			break
		var shot: Dictionary = raw
		var from: Vector3 = shot.from
		var to: Vector3 = shot.to
		var life := maxf(float(shot.life), 0.001)
		var t := float(shot.t)
		var u := clampf(t / life, 0.0, 1.0)
		var pos: Vector3 = from.lerp(to, u)
		var d := to - from
		var length := d.length()
		if length < 0.2:
			continue
		var dir := d / length
		var half := STREAK_LEN * 0.5
		var back := minf(half, u * length)
		var fwd := minf(half, (1.0 - u) * length + 0.12)
		if _write_tracer(tracer_i, pos - dir * back, pos + dir * fwd):
			tracer_i += 1
		var air := bool(shot.air)
		if t < MUZZLE_LIFE and not air and muzzle_i < MAX_MUZZLES:
			_write_billboard(_muzzle_buf, muzzle_i, from + Vector3(0.0, 0.25, 0.0), 1.5)
			muzzle_i += 1
		if u >= 0.88 and not air and spark_i < MAX_SPARKS:
			_write_billboard(_spark_buf, spark_i, to, 1.3)
			spark_i += 1
		if air and u >= 0.82 and puff_i < MAX_PUFFS:
			_write_puff(puff_i, to)
			puff_i += 1
	return PackedInt32Array([tracer_i, muzzle_i, spark_i, puff_i])


func _pose_frame(id: int, i: int, st: int, firing: bool, dead: bool) -> int:
	if id >= 2 or _sheet_cols[id] < 2.0:
		return 0
	if dead:
		return 0
	if firing:
		return 5 + (int(_frame_pos * 12.0) + i * 2) % 3
	if st == ST_HIT:
		return 0
	if st == ST_MARCH or st == ST_ROUT:
		return 1 + (int(_frame_pos * 8.0) + i) % 4
	if st == ST_AIM:
		return 5
	return 0


func _write_tracer(slot: int, from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var length := d.length()
	if length < 0.2:
		return false
	var mid := (from + to) * 0.5
	var x_axis := d / length
	var y_axis := Vector3.UP
	if absf(x_axis.dot(y_axis)) > 0.92:
		y_axis = Vector3.RIGHT
	var z_axis := x_axis.cross(y_axis)
	if z_axis.length() < 0.001:
		return false
	z_axis = z_axis.normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	_write_basis(slot, _tracer_buf, x_axis * length, y_axis * 0.14, z_axis * 0.14, mid)
	return true


func _write_puff(slot: int, at: Vector3) -> void:
	_write_billboard(_puff_buf, slot, Vector3(at.x, GROUND_Y + 0.55, at.z), 1.8)


func _write_billboard(buf: PackedFloat32Array, slot: int, at: Vector3, size: float) -> void:
	var o := slot * XFORM_STRIDE
	buf[o + 0] = size
	buf[o + 5] = size
	buf[o + 10] = size
	buf[o + 3] = at.x
	buf[o + 7] = at.y
	buf[o + 11] = at.z


func _write_basis(slot: int, buf: PackedFloat32Array, x: Vector3, y: Vector3, z: Vector3, origin: Vector3) -> void:
	var o := slot * XFORM_STRIDE
	buf[o + 0] = x.x
	buf[o + 1] = y.x
	buf[o + 2] = z.x
	buf[o + 3] = origin.x
	buf[o + 4] = x.y
	buf[o + 5] = y.y
	buf[o + 6] = z.y
	buf[o + 7] = origin.y
	buf[o + 8] = x.z
	buf[o + 9] = y.z
	buf[o + 10] = z.z
	buf[o + 11] = origin.z


func _tick_audio(fire_n: int, hit_n: int, rout_n: int) -> void:
	if _done:
		return
	if fire_n > 0 and _snd_cool <= 0.0 and _audio_fire:
		_audio_fire.play()
		_snd_cool = 0.09
	elif hit_n > 6 and _snd_cool <= 0.0 and _audio_hit:
		_audio_hit.play()
		_snd_cool = 0.12
	if rout_n > 12 and not _rout_played and _audio_rout:
		_audio_rout.play()
		_rout_played = true


func _write_instance(
	id: int, o: int, szx: float, szy: float, wx: float, yc: float, wz: float,
	flip: float, frame: int, fire: float, dead: float, fade: float
) -> void:
	var packed := float(frame * 2 + (1 if flip > 0.5 else 0))
	match id:
		0:
			_buf0[o + 0] = szx; _buf0[o + 5] = szy; _buf0[o + 10] = szx
			_buf0[o + 3] = wx; _buf0[o + 7] = yc; _buf0[o + 11] = wz
			_buf0[o + 12] = packed; _buf0[o + 13] = fire; _buf0[o + 14] = dead; _buf0[o + 15] = fade
		1:
			_buf1[o + 0] = szx; _buf1[o + 5] = szy; _buf1[o + 10] = szx
			_buf1[o + 3] = wx; _buf1[o + 7] = yc; _buf1[o + 11] = wz
			_buf1[o + 12] = packed; _buf1[o + 13] = fire; _buf1[o + 14] = dead; _buf1[o + 15] = fade
		2:
			_buf2[o + 0] = szx; _buf2[o + 5] = szy; _buf2[o + 10] = szx
			_buf2[o + 3] = wx; _buf2[o + 7] = yc; _buf2[o + 11] = wz
			_buf2[o + 12] = packed; _buf2[o + 13] = fire; _buf2[o + 14] = dead; _buf2[o + 15] = fade
		_:
			_buf3[o + 0] = szx; _buf3[o + 5] = szy; _buf3[o + 10] = szx
			_buf3[o + 3] = wx; _buf3[o + 7] = yc; _buf3[o + 11] = wz
			_buf3[o + 12] = packed; _buf3[o + 13] = fire; _buf3[o + 14] = dead; _buf3[o + 15] = fade


func _update_header() -> void:
	var winner := int(_summary.get("winner", -1))
	var hold := "  ·  hold" if _done else ""
	_header.text = "F%d vs F%d%s" % [
		int(_summary.get("attacker", 0)),
		int(_summary.get("defender", 1)),
		("  ·  F%d holds the field" % winner) if (winner >= 0 and _done) else hold,
	]
	_progress.text = "right-drag orbit   wheel zoom   %s" % [
		_speed_label() if _playing else "paused",
	]


func _speed_label() -> String:
	if is_equal_approx(_speed, snappedf(_speed, 1.0)):
		return "%dx" % int(round(_speed))
	return "%sx" % snappedf(_speed, 0.01)


func _apply_camera() -> void:
	var cp := cos(_pitch)
	var offset := Vector3(_dist * cp * sin(_yaw), _dist * sin(_pitch), _dist * cp * cos(_yaw))
	_cam.position = _look + offset
	_cam.look_at(_look, Vector3.UP)


func _pan_camera(delta: float) -> bool:
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var want := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		want += fwd
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		want -= fwd
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		want += right
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		want -= right
	if want.length_squared() < 0.01:
		return false
	_look += want.normalized() * _dist * 0.95 * delta
	var hw := _w * 0.5 * SCALE
	var hh := _h * 0.5 * SCALE
	_look.x = clampf(_look.x, -hw - 12.0, hw + 12.0)
	_look.z = clampf(_look.z, -hh - 12.0, hh + 12.0)
	_look.y = GROUND_Y
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist = clampf(_dist / 1.1, 80.0, 2400.0)
			_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist = clampf(_dist * 1.1, 80.0, 2400.0)
			_apply_camera()
	elif event is InputEventMouseMotion and _orbit:
		_yaw -= event.relative.x * 0.01
		_pitch = clampf(_pitch + event.relative.y * 0.01, 0.15, 1.35)
		_apply_camera()


func _on_back() -> void:
	visible = false
	finished.emit()
