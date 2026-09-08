extends Control

## Two Worlds — turn-based mode on the real 3D Earth globe (Total War layout).
##
## Reuses the existing globe: EarthGlobeMesh builds the sphere; the Earth's land tiles are carved
## into a few LARGE provinces painted onto the sphere albedo; soldier billboards act as commander
## armies at province centroids. The tested eon_engine (TwoWorldsEngine) is the turn authority.

const MapGen := preload("res://WorldConquestMapGenerator.gd")
const GlobeMesh := preload("res://EarthGlobeMesh.gd")
const CFG := preload("res://WorldConquestConfig.gd")
const BattleOverlayScript := preload("res://TwoWorldsBattleOverlay.gd")
const TEX_SOLDIER_F: Texture2D = preload("res://assets/units/soldier_friendly.png")
const TEX_SOLDIER_H: Texture2D = preload("res://assets/units/soldier_hostile.png")

const N_PROV := 26
const COMMANDER_LIFT := 7.0

var _seed: int = 20260907
var _engine: Object = null
var _map = null
var _w: int = 360
var _h: int = 180

# Province partition (presentation-side).
var _prov_of := PackedInt32Array()
var _prov_centroid: Array = []       # Array[Vector2i]
var _prov_count: int = 0
var _neighbors: Array = []           # Array[PackedInt32Array]
var _capital_of := PackedInt32Array()
var _has_throne := PackedByteArray()
var _deposit := PackedInt32Array()

# Engine snapshot.
var _provinces: Array = []
var _factions: Array = []
var _armies: Array = []
var _turn: int = 0
var _outcome: String = "Ongoing"
var _done: bool = false

# 3D render.
var _sub: SubViewport
var _cam: Camera3D
var _globe_mi: MeshInstance3D
var _mat: StandardMaterial3D
var _albedo_img: Image
var _albedo_tex: ImageTexture
var _commanders: Node3D
var _cmd_pool: Array = []            # Array[Sprite3D]

# Camera orbit.
var _yaw: float = 0.5
var _pitch: float = 0.35
var _dist: float = 230.0
var _orbit_drag: bool = false

# HUD.
var _status_label: Label
var _turn_label: Label
var _victory_label: Label
var _end_btn: Button
var _menu_btn: Button
var _overlay: Control

# Battle review.
var _state: String = "map"
var _turn_battles: Array = []
var _review_ptr: int = 0

var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	set_process(true)

	_engine = _make_engine()
	if _engine == null:
		var err := Label.new()
		err.text = "TwoWorldsEngine not available — rebuild the Rust GDExtension."
		err.position = Vector2(40, 40)
		add_child(err)
		return

	var rs: Object = get_tree().root.get_node_or_null("RunState") if get_tree() else null
	if rs != null and "run_seed" in rs and int(rs.run_seed) != 0:
		_seed = int(rs.run_seed)

	_map = MapGen.generate("earth", _seed, false, {})
	_w = int(_map.grid_width)
	_h = int(_map.grid_height)
	_carve_provinces()
	_engine.begin_campaign(_seed, 2, _neighbors, _capital_of, _has_throne, _deposit, 40, 8)

	_build_globe()
	_build_hud()
	_refresh()
	_repaint_globe()
	_sync_commanders()


func _make_engine() -> Object:
	if ClassDB.class_exists("TwoWorldsEngine"):
		return ClassDB.instantiate("TwoWorldsEngine")
	return null


# ------------------------------------------------------------------ province carving

func _dir(gx: int, gy: int) -> Vector3:
	return GlobeMesh.grid_to_sphere(gx, gy, _w, _h, 1.0, 0.0)


func _carve_provinces() -> void:
	# Collect land pixels.
	var land_idx := PackedInt32Array()
	var land_dir: Array = []
	for gy in range(_h):
		for gx in range(_w):
			if _map.is_land_equirect_pixel(gx, gy):
				land_idx.append(gy * _w + gx)
				land_dir.append(_dir(gx, gy))
	var lc := land_idx.size()
	_prov_of = PackedInt32Array()
	_prov_of.resize(_w * _h)
	_prov_of.fill(-1)
	if lc == 0:
		_prov_count = 0
		return

	# Farthest-point sampling of province seeds.
	var seeds: Array = [0]
	while seeds.size() < min(N_PROV, lc):
		var best_i := -1
		var best_d := -1.0
		for i in range(lc):
			var d := INF
			for s in seeds:
				var dd: float = (land_dir[i] - land_dir[s]).length_squared()
				d = min(d, dd)
			if d > best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			break
		seeds.append(best_i)
	_prov_count = seeds.size()

	# Assign each land pixel to nearest seed.
	var sum_dir: Array = []
	var members: Array = []
	for _s in range(_prov_count):
		sum_dir.append(Vector3.ZERO)
		members.append(PackedInt32Array())
	for i in range(lc):
		var best := 0
		var best_d := INF
		for s in range(_prov_count):
			var dd: float = (land_dir[i] - land_dir[seeds[s]]).length_squared()
			if dd < best_d:
				best_d = dd
				best = s
		_prov_of[land_idx[i]] = best
		sum_dir[best] += land_dir[i]
		members[best].append(i)

	# Centroids (member pixel closest to the province mean direction).
	_prov_centroid = []
	for s in range(_prov_count):
		var mean: Vector3 = (sum_dir[s] as Vector3).normalized()
		var best_i := int(members[s][0]) if members[s].size() > 0 else 0
		var best_dot := -2.0
		for mi in members[s]:
			var dd: float = (land_dir[mi] as Vector3).dot(mean)
			if dd > best_dot:
				best_dot = dd
				best_i = mi
		var flat := land_idx[best_i]
		_prov_centroid.append(Vector2i(flat % _w, flat / _w))

	# Adjacency (share a 4-neighbor border between different provinces).
	var nbsets: Array = []
	for _s in range(_prov_count):
		nbsets.append({})
	for gy in range(_h):
		for gx in range(_w):
			var p := _prov_of[gy * _w + gx]
			if p < 0:
				continue
			var rx := (gx + 1) % _w
			var pr := _prov_of[gy * _w + rx]
			if pr >= 0 and pr != p:
				nbsets[p][pr] = true
				nbsets[pr][p] = true
			if gy + 1 < _h:
				var pd := _prov_of[(gy + 1) * _w + gx]
				if pd >= 0 and pd != p:
					nbsets[p][pd] = true
					nbsets[pd][p] = true
	# Sea lanes: connect each province to its nearest few provinces (by centroid direction) so the
	# campaign graph is connected across oceans — otherwise factions on separate continents never
	# meet and no battles occur.
	var cdir: Array = []
	for s in range(_prov_count):
		var c: Vector2i = _prov_centroid[s]
		cdir.append(_dir(c.x, c.y))
	for s in range(_prov_count):
		var order: Array = []
		for t in range(_prov_count):
			if t == s:
				continue
			order.append({"t": t, "d": (cdir[s] as Vector3).distance_squared_to(cdir[t])})
		order.sort_custom(func(a, b): return a["d"] < b["d"])
		for k in range(min(3, order.size())):
			var t := int(order[k]["t"])
			nbsets[s][t] = true
			nbsets[t][s] = true

	_neighbors = []
	for s in range(_prov_count):
		var arr := PackedInt32Array()
		for k in nbsets[s].keys():
			arr.append(int(k))
		_neighbors.append(arr)

	# Capitals: two provinces far apart.
	var cap0 := 0
	var minx := INF
	for s in range(_prov_count):
		var c: Vector2i = _prov_centroid[s]
		var dx: float = _dir(c.x, c.y).x
		if dx < minx:
			minx = dx
			cap0 = s
	var cap1 := 0
	var maxd := -1.0
	var c0: Vector2i = _prov_centroid[cap0]
	var d0 := _dir(c0.x, c0.y)
	for s in range(_prov_count):
		var c: Vector2i = _prov_centroid[s]
		var dd: float = (_dir(c.x, c.y) - d0).length_squared()
		if dd > maxd:
			maxd = dd
			cap1 = s
	_capital_of = PackedInt32Array()
	_capital_of.resize(_prov_count)
	_capital_of.fill(-1)
	_capital_of[cap0] = 0
	_capital_of[cap1] = 1

	# Thrones: two non-capital provinces nearest the midpoint between capitals.
	var mid := (d0 + _dir(_prov_centroid[cap1].x, _prov_centroid[cap1].y)).normalized()
	var ranked: Array = []
	for s in range(_prov_count):
		if s == cap0 or s == cap1:
			continue
		var c: Vector2i = _prov_centroid[s]
		ranked.append({"s": s, "dot": _dir(c.x, c.y).dot(mid)})
	ranked.sort_custom(func(a, b): return a["dot"] > b["dot"])
	_has_throne = PackedByteArray()
	_has_throne.resize(_prov_count)
	_has_throne.fill(0)
	for t in range(min(3, ranked.size())):
		_has_throne[int(ranked[t]["s"])] = 1

	# Deposits: seeded assignment to ~6 provinces.
	_deposit = PackedInt32Array()
	_deposit.resize(_prov_count)
	_deposit.fill(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	for _k in range(6):
		var s := rng.randi_range(0, _prov_count - 1)
		_deposit[s] = rng.randi_range(0, 2)


# ------------------------------------------------------------------ 3D globe

func _build_globe() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(container)

	_sub = SubViewport.new()
	_sub.own_world_3d = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.transparent_bg = false
	container.add_child(_sub)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 50.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.06)
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	_cam.environment = env
	_sub.add_child(_cam)
	_apply_camera()

	_albedo_img = Image.create(_w, _h, false, Image.FORMAT_RGBA8)
	_albedo_tex = ImageTexture.create_from_image(_albedo_img)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_texture = _albedo_tex
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_globe_mi = MeshInstance3D.new()
	_globe_mi.mesh = GlobeMesh.build_globe(_map, "earth")
	_globe_mi.material_override = _mat
	_sub.add_child(_globe_mi)

	_commanders = Node3D.new()
	_sub.add_child(_commanders)


func _apply_camera() -> void:
	var cp := cos(_pitch)
	_cam.position = Vector3(_dist * cp * sin(_yaw), _dist * sin(_pitch), _dist * cp * cos(_yaw))
	_cam.look_at(Vector3.ZERO, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if _state != "map":
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbit_drag = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_dist = clampf(_dist / 1.1, 130.0, 320.0)
			_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_dist = clampf(_dist * 1.1, 130.0, 320.0)
			_apply_camera()
	elif event is InputEventMouseMotion and _orbit_drag:
		_yaw -= event.relative.x * 0.01
		_pitch = clampf(_pitch + event.relative.y * 0.01, -1.2, 1.2)
		_apply_camera()


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var title := Label.new()
	title.text = "Two Worlds — Turn-Based (Globe MVP)"
	title.position = Vector2(160, 18)
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_menu_btn = Button.new()
	_menu_btn.text = "\u2190 Menu"
	_menu_btn.position = Vector2(24, 16)
	_menu_btn.size = Vector2(120, 40)
	_menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://MainMenu.tscn"))
	add_child(_menu_btn)

	_status_label = Label.new()
	_status_label.position = Vector2(24, 66)
	_status_label.add_theme_font_size_override("font_size", 15)
	add_child(_status_label)

	_turn_label = Label.new()
	_turn_label.position = Vector2(24, 116)
	_turn_label.add_theme_font_size_override("font_size", 15)
	add_child(_turn_label)

	_victory_label = Label.new()
	_victory_label.add_theme_font_size_override("font_size", 34)
	_victory_label.add_theme_color_override("font_color", Color(1, 0.93, 0.5))
	_victory_label.visible = false
	add_child(_victory_label)

	_end_btn = Button.new()
	_end_btn.text = "End Turn"
	_end_btn.size = Vector2(220, 56)
	_end_btn.pressed.connect(_on_end_turn)
	add_child(_end_btn)

	_overlay = Control.new()
	_overlay.set_script(BattleOverlayScript)
	add_child(_overlay)
	_overlay.closed.connect(_advance_review)

	_reposition_hud()


func _reposition_hud() -> void:
	if _end_btn:
		_end_btn.position = Vector2(size.x * 0.5 - 110.0, size.y - 74.0)
	if _victory_label:
		_victory_label.position = Vector2(size.x * 0.5 - 260.0, 150.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reposition_hud()


func _refresh() -> void:
	_provinces = _engine.get_provinces()
	_factions = _engine.get_factions()
	_armies = _engine.get_armies()
	_turn = int(_engine.current_turn())
	_outcome = String(_engine.outcome())
	var lines: Array = []
	for f in _factions:
		var gems: PackedFloat32Array = f.get("gems", PackedFloat32Array())
		var gem_str := ""
		if gems.size() >= 3:
			gem_str = "Au%d Ve%d Em%d" % [int(gems[0]), int(gems[1]), int(gems[2])]
		lines.append("%s  Dom %d  Land %d  Units %d  Thrones %d  %s" % [
			String(f.get("name", "F")), int(f.get("dominion", 0.0)), int(f.get("land", 0)),
			int(f.get("units", 0)), int(f.get("thrones", 0)), gem_str])
	_status_label.text = "\n".join(lines)
	_turn_label.text = "Turn %d    Outcome: %s" % [_turn, _outcome]
	_victory_label.visible = _done
	if _done:
		_victory_label.text = "VICTORY — %s" % _outcome


func _fac_color(f: int) -> Color:
	match f:
		0:
			return Color(0.35, 0.6, 1.0)
		1:
			return Color(1.0, 0.4, 0.4)
		_:
			return Color(0.6, 0.6, 0.65)


func _repaint_globe() -> void:
	var ocean := Color(0.05, 0.10, 0.24)
	var neutral_land := Color(0.30, 0.34, 0.30)
	var border := Color(0.03, 0.04, 0.06)
	for gy in range(_h):
		for gx in range(_w):
			var idx := gy * _w + gx
			var p := _prov_of[idx]
			if p < 0:
				_albedo_img.set_pixel(gx, gy, ocean)
				continue
			# Border pixel? (neighbor in a different province)
			var is_border := false
			var rx := (gx + 1) % _w
			var lx := (gx - 1 + _w) % _w
			if _prov_of[gy * _w + rx] != p or _prov_of[gy * _w + lx] != p:
				is_border = true
			elif gy > 0 and _prov_of[(gy - 1) * _w + gx] != p:
				is_border = true
			elif gy + 1 < _h and _prov_of[(gy + 1) * _w + gx] != p:
				is_border = true
			if is_border:
				_albedo_img.set_pixel(gx, gy, border)
				continue
			var col := neutral_land
			if p < _provinces.size():
				var pr: Dictionary = _provinces[p]
				var owner := int(pr.get("owner", -1))
				if owner >= 0:
					var dom: PackedFloat32Array = pr.get("dom", PackedFloat32Array())
					var v := dom[owner] if owner < dom.size() else 0.0
					var t: float = clampf(v / 20.0, 0.25, 1.0)
					col = neutral_land.lerp(_fac_color(owner), t)
			_albedo_img.set_pixel(gx, gy, col)
	_albedo_tex.update(_albedo_img)


func _sync_commanders() -> void:
	var used := 0
	for a in _armies:
		var prov := int(a.get("province", 0))
		var fac := int(a.get("faction", 0))
		var units := int(a.get("units", 0))
		if prov >= _prov_centroid.size():
			continue
		var c: Vector2i = _prov_centroid[prov]
		var pos := GlobeMesh.grid_to_sphere(c.x, c.y, _w, _h, CFG.GLOBE_RADIUS + COMMANDER_LIFT, 0.0)
		var spr: Sprite3D = _cmd_pool[used] if used < _cmd_pool.size() else _new_commander()
		if used >= _cmd_pool.size():
			_cmd_pool.append(spr)
		spr.visible = true
		spr.position = pos
		spr.texture = TEX_SOLDIER_F if fac == 0 else TEX_SOLDIER_H
		var lbl: Label3D = spr.get_child(0)
		lbl.text = "x%d" % units
		lbl.modulate = _fac_color(fac)
		used += 1
	for i in range(used, _cmd_pool.size()):
		_cmd_pool[i].visible = false


func _new_commander() -> Sprite3D:
	var spr := Sprite3D.new()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.double_sided = true
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = 0.09
	spr.render_priority = 10
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.position = Vector3(0, 3.0, 0)
	lbl.font_size = 48
	lbl.pixel_size = 0.06
	lbl.render_priority = 11
	lbl.no_depth_test = true
	spr.add_child(lbl)
	_commanders.add_child(spr)
	return spr


# ------------------------------------------------------------------ turn / battle flow

func _on_end_turn() -> void:
	if _done:
		_seed += 1
		_carve_provinces()
		_engine.begin_campaign(_seed, 2, _neighbors, _capital_of, _has_throne, _deposit, 40, 8)
		_done = false
		_end_btn.text = "End Turn"
		_refresh()
		_repaint_globe()
		_sync_commanders()
		return
	var res: Dictionary = _engine.end_turn()
	_turn = int(res.get("turn", _turn))
	_outcome = String(res.get("outcome", _outcome))
	_done = bool(res.get("done", false))
	_turn_battles = res.get("battles", [])
	_refresh()
	_repaint_globe()
	_sync_commanders()
	if _turn_battles.size() > 0:
		_review_ptr = 0
		_start_review(0)
	elif _done:
		_end_btn.text = "Play Again"


func _start_review(i: int) -> void:
	var b: Dictionary = _engine.get_last_battle_frames(i)
	_state = "battle"
	_end_btn.visible = false
	_overlay.show_battle(b.get("frames", []), _turn_battles[i], float(b.get("width", 120.0)), float(b.get("height", 80.0)))


func _advance_review() -> void:
	_review_ptr += 1
	if _review_ptr < _turn_battles.size():
		_start_review(_review_ptr)
	else:
		_state = "map"
		_end_btn.visible = true
		_end_btn.text = "Play Again" if _done else "End Turn"
		_refresh()
		_repaint_globe()
		_sync_commanders()
