extends Control

## HD-2D battle viewer. Plays a baked battle (from TwoWorldsEngine) as a 3D diorama: a ground plane
## with GPU-instanced billboard sprites (MultiMesh) for up to thousands of units, a free orbit
## camera, and smooth frame interpolation for ~60fps playback regardless of unit count (all sim is
## precomputed). Emits `finished` when the viewer is dismissed.

signal finished

const BillboardShaderPath := "res://shaders/battle_billboard.gdshader"
# Bucket order: 0 = friendly soldier, 1 = hostile soldier, 2 = friendly bomber, 3 = hostile bomber.
# Bucket id = faction + kind * 2, so a unit's (faction, kind) maps to a fixed MultiMesh/texture.
const TEX := [
	preload("res://assets/units/soldier_friendly.png"),
	preload("res://assets/units/soldier_hostile.png"),
	preload("res://assets/units/bomber_friendly.png"),
	preload("res://assets/units/bomber_hostile.png"),
]
const SCALE := 1.0          # 1 battle unit = 1 world unit
const SPRITE_SIZE := 3.2    # world-units tall per unit sprite
const BOMBER_SIZE := 5.2    # bombers read larger
const GROUND_Y := 0.0

var _engine: Object
var _index: int = 0
var _w: float = 200.0
var _h: float = 120.0
var _frame_count: int = 0
var _unit_count: int = 0
var _fac := PackedByteArray()
var _kind := PackedByteArray()
var _summary: Dictionary = {}

# Playback.
var _frame_pos: float = 0.0
var _play_fps: float = 3.0
var _speed: float = 1.0
var _playing: bool = true
var _done: bool = false
# Streamed frame cache (a few adjacent frames).
var _cache := {}   # frame_idx -> {x,y,alive}

# 3D nodes.
var _sub: SubViewport
var _cam: Camera3D
# One MultiMesh per bucket (fixed instance_count = units of that bucket). Dead units are hidden by
# writing a zero-scale instance transform, so buffers never reallocate during playback.
var _mmi := [null, null, null, null]        # Array[MultiMeshInstance3D]
var _buf0 := PackedFloat32Array()
var _buf1 := PackedFloat32Array()
var _buf2 := PackedFloat32Array()
var _buf3 := PackedFloat32Array()
var _bkt := PackedByteArray()                # per-unit bucket id (0..3)
var _off := PackedInt32Array()               # per-unit float offset (slot * 12) into its bucket buffer
var _yaw := 0.7
var _pitch := 0.92                # strategic near-overhead tilt keeps the whole field framed
var _dist := 190.0
var _orbit := false
var _auto_rotate := true
const AUTO_ROTATE_SPEED := 0.02   # gentle turntable so the action stays in view during playback

# HUD.
var _header: Label
var _progress: Label
var _back_btn: Button
var _speed_btns := []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(true)
	_build_3d()
	_build_hud()


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
	env.background_color = Color(0.10, 0.12, 0.16)
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.12, 0.16)
	env.fog_density = 0.0012
	_cam.environment = env
	_sub.add_child(_cam)

	# Ground diorama plane.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(_w * SCALE * 1.35, _h * SCALE * 1.7)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.17, 0.23, 0.14)
	gmat.roughness = 1.0
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.set_surface_override_material(0, gmat)
	_sub.add_child(ground)

	# One MultiMesh per bucket so each carries its own sprite texture. Unit quad (size 1) scaled by
	# the per-instance transform; the billboard shader keeps it camera-facing.
	var shader: Shader = load(BillboardShaderPath)
	for id in range(4):
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		mm.mesh = quad
		mm.instance_count = 0
		mmi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("tex", TEX[id])
		mmi.material_override = mat
		# Draw sprites after the ground; keep them from z-fighting the plane.
		mmi.position = Vector3(0.0, 0.02, 0.0)
		_sub.add_child(mmi)
		_mmi[id] = mmi

	_apply_camera()


func _build_hud() -> void:
	_header = Label.new()
	_header.position = Vector2(24, 18)
	_header.add_theme_font_size_override("font_size", 20)
	add_child(_header)

	_progress = Label.new()
	_progress.position = Vector2(24, 50)
	_progress.add_theme_font_size_override("font_size", 14)
	add_child(_progress)

	var speeds := [["Pause", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0], ["8x", 8.0]]
	var x := 24.0
	for sp in speeds:
		var b := Button.new()
		b.text = sp[0]
		b.position = Vector2(x, 78)
		b.size = Vector2(64, 34)
		var v: float = sp[1]
		b.pressed.connect(func(): _set_speed(v))
		add_child(b)
		_speed_btns.append(b)
		x += 70.0

	# Anchor Back to the bottom-right so it is correctly placed regardless of layout timing
	# (manual positioning from size.x runs before the first layout pass and lands off-screen).
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
	add_child(_back_btn)


func _set_speed(v: float) -> void:
	if v <= 0.0:
		_playing = false
	else:
		_playing = true
		_speed = v


func _notification(_what: int) -> void:
	pass  # Back button is anchored to the bottom-right; no manual repositioning needed.


func play_engine_battle(engine: Object, index: int, summary: Dictionary = {}) -> void:
	_engine = engine
	_index = index
	_summary = summary
	var meta: Dictionary = engine.get_last_battle_meta(index)
	_w = float(meta.get("width", 200.0))
	_h = float(meta.get("height", 120.0))
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
		}
	_cache.clear()
	_frame_pos = 0.0
	_speed = 1.0
	_playing = true
	_done = false
	# Resize the ground plane to the actual battlefield.
	if _sub:
		for c in _sub.get_children():
			if c is MeshInstance3D and c.mesh is PlaneMesh:
				(c.mesh as PlaneMesh).size = Vector2(_w * SCALE * 1.35, _h * SCALE * 1.7)
	_dist = clampf(maxf(_w, _h) * 0.95, 90.0, 320.0)
	# Target watch time: between Total War and Dominions — 1..8 min, ~0.35s per recorded frame.
	var duration: float = clampf(float(_frame_count) * 0.35, 60.0, 480.0)
	_play_fps = float(maxi(_frame_count, 1)) / duration
	_prepare_buckets()
	_apply_camera()
	visible = true
	_render_frame()
	_update_header()


func _prepare_buckets() -> void:
	# Assign each unit to a fixed bucket + slot; pre-size the per-bucket transform buffers and fill
	# the diagonal scale so playback only rewrites the translation (and hides the dead).
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
		_off[i] = counts[id] * 12
		counts[id] += 1
	_buf0 = _make_buf(counts[0], SPRITE_SIZE)
	_buf1 = _make_buf(counts[1], SPRITE_SIZE)
	_buf2 = _make_buf(counts[2], BOMBER_SIZE)
	_buf3 = _make_buf(counts[3], BOMBER_SIZE)
	for id in range(4):
		(_mmi[id].multimesh as MultiMesh).instance_count = counts[id]


func _make_buf(count: int, sz: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(count * 12)
	for k in range(count):
		var o := k * 12
		buf[o + 0] = sz
		buf[o + 5] = sz
		buf[o + 10] = sz
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


func _process(delta: float) -> void:
	if not visible:
		return
	if _auto_rotate and not _orbit:
		_yaw += delta * AUTO_ROTATE_SPEED
		_apply_camera()
	if _playing and not _done:
		_frame_pos += _play_fps * _speed * delta
		if _frame_pos >= float(_frame_count - 1):
			_frame_pos = float(maxi(_frame_count - 1, 0))
			_done = true
	_render_frame()
	_update_header()


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
	var aa: PackedByteArray = fa.get("alive", PackedByteArray())
	var xb: PackedFloat32Array = fb.get("x", PackedFloat32Array())
	var yb: PackedFloat32Array = fb.get("y", PackedFloat32Array())
	var ab: PackedByteArray = fb.get("alive", PackedByteArray())

	var n := mini(_unit_count, xa.size())
	var hw := _w * 0.5
	var hh := _h * 0.5
	for i in range(n):
		var id := _bkt[i]
		var o := _off[i]
		var alive := i < aa.size() and aa[i] != 0
		var sz := 0.0
		var wx := 0.0
		var wz := 0.0
		var yc := 0.0
		if alive:
			sz = BOMBER_SIZE if id >= 2 else SPRITE_SIZE
			var ax := xa[i]
			var ay := ya[i]
			var bx := ax
			var by := ay
			if i < xb.size() and i < ab.size() and ab[i] != 0:
				bx = xb[i]
				by = yb[i]
			var px: float = lerpf(ax, bx, alpha)
			var py: float = lerpf(ay, by, alpha)
			# Routed survivors flee toward (and past) their baseline in the sim; clamp the rendered
			# position to the battlefield so they visibly gather at the rear edge instead of
			# streaming off the diorama. Presentational only — the sim positions are untouched.
			wx = (clampf(px, 0.0, _w) - hw) * SCALE
			wz = (clampf(py, 0.0, _h) - hh) * SCALE
			yc = GROUND_Y + sz * 0.5
		# Write the diagonal-scale + translation transform in place (o..o+11).
		match id:
			0:
				_buf0[o + 0] = sz; _buf0[o + 5] = sz; _buf0[o + 10] = sz
				_buf0[o + 3] = wx; _buf0[o + 7] = yc; _buf0[o + 11] = wz
			1:
				_buf1[o + 0] = sz; _buf1[o + 5] = sz; _buf1[o + 10] = sz
				_buf1[o + 3] = wx; _buf1[o + 7] = yc; _buf1[o + 11] = wz
			2:
				_buf2[o + 0] = sz; _buf2[o + 5] = sz; _buf2[o + 10] = sz
				_buf2[o + 3] = wx; _buf2[o + 7] = yc; _buf2[o + 11] = wz
			_:
				_buf3[o + 0] = sz; _buf3[o + 5] = sz; _buf3[o + 10] = sz
				_buf3[o + 3] = wx; _buf3[o + 7] = yc; _buf3[o + 11] = wz
	var mm0: MultiMesh = _mmi[0].multimesh
	var mm1: MultiMesh = _mmi[1].multimesh
	var mm2: MultiMesh = _mmi[2].multimesh
	var mm3: MultiMesh = _mmi[3].multimesh
	if mm0.instance_count > 0:
		mm0.buffer = _buf0
	if mm1.instance_count > 0:
		mm1.buffer = _buf1
	if mm2.instance_count > 0:
		mm2.buffer = _buf2
	if mm3.instance_count > 0:
		mm3.buffer = _buf3


func _update_header() -> void:
	var winner := int(_summary.get("winner", -1))
	_header.text = "Battle — F%d vs F%d — %s%s" % [
		int(_summary.get("attacker", 0)),
		int(_summary.get("defender", 1)),
		("winner F%d" % winner) if winner >= 0 else "draw",
		"   [RESOLVED]" if _done else "",
	]
	_progress.text = "units %d   frame %d / %d   %s   — right-drag to orbit, wheel to zoom" % [
		_unit_count, int(_frame_pos) + 1, _frame_count,
		("speed %.0fx" % _speed) if _playing else "paused",
	]


func _apply_camera() -> void:
	var cp := cos(_pitch)
	_cam.position = Vector3(_dist * cp * sin(_yaw), _dist * sin(_pitch), _dist * cp * cos(_yaw))
	_cam.look_at(Vector3.ZERO, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist = clampf(_dist / 1.1, 50.0, 340.0)
			_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist = clampf(_dist * 1.1, 50.0, 340.0)
			_apply_camera()
	elif event is InputEventMouseMotion and _orbit:
		_yaw -= event.relative.x * 0.01
		_pitch = clampf(_pitch + event.relative.y * 0.01, 0.15, 1.35)
		_apply_camera()


func _on_back() -> void:
	visible = false
	finished.emit()
