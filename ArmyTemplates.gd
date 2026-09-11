extends RefCounted

## Army-scale Custom Battle deploys. One template lays out every regiment on a side.
## Regiment Line / Double / Column / Wedge stay as slot shapes; these place centers.
## Rank bands (screen/line/overwatch/battery/train/air) plus parent `group`
## (melee ahead of hybrid in the line band). BattleKinds.gd
## No autoloads — safe for headless parse-check.

const Kinds := preload("res://BattleKinds.gd")

const BW := 1000.0
const BH := 600.0
const HILL_CX := 260.0
const HILL_CY := 460.0
const HILL_BLOCK_R := 140.0 * 0.92
const RUIN_CX := 100.0
const RUIN_CY := 55.0
const RUIN_R := 27.5

const FORM_LINE := 0
const FORM_COLUMN := 2
const FORM_WEDGE := 3

const ORDER_FRONT := 0
const ORDER_LEFT := 1
const ORDER_RIGHT := 2
const ORDER_REAR := 3

const TPL_BATTLE_LINE := 0
const TPL_ATTACK_COLUMN := 1
const TPL_WEDGE := 2
const TPL_VEE := 3
const TPL_ECHELON_LEFT := 4
const TPL_ECHELON_RIGHT := 5
const TPL_HOLLOW_SQUARE := 6
const TPL_MIXED_ORDER := 7

const TPL_NAMES: PackedStringArray = [
	"Battle Line",
	"Atk Col",
	"Wedge",
	"Vee",
	"Ech L",
	"Ech R",
	"Square",
	"Mixed",
]


static func layout(fac: int, template: int, kinds: Array) -> Array:
	var t := clampi(template, 0, 7)
	var n := kinds.size()
	var out: Array = []
	out.resize(n)
	var face := 0.0 if fac == 0 else PI
	for i in n:
		out[i] = {
			"x": 200.0 if fac == 0 else 800.0,
			"y": 300.0,
			"facing": face,
			"formation": FORM_LINE,
			"order": ORDER_FRONT,
		}
	if n == 0:
		return out
	var inf: Array = []
	var air: Array = []
	var screen: Array = []
	var overwatch: Array = []
	var battery: Array = []
	var train: Array = []
	for i in n:
		var k := int(kinds[i])
		if Kinds.is_air(k):
			air.append(i)
		else:
			match Kinds.rank(k):
				Kinds.RANK_SCREEN:
					screen.append(i)
				Kinds.RANK_OVERWATCH:
					overwatch.append(i)
				Kinds.RANK_BATTERY:
					battery.append(i)
				Kinds.RANK_TRAIN:
					train.append(i)
				_:
					inf.append(i)
	inf = _order_line_band(t, inf, kinds)
	match t:
		TPL_BATTLE_LINE:
			_battle_line(fac, inf, air, out)
		TPL_ATTACK_COLUMN:
			_attack_column(fac, inf, air, out)
		TPL_WEDGE:
			_chevron(fac, inf, air, out, true)
		TPL_VEE:
			_chevron(fac, inf, air, out, false)
		TPL_ECHELON_LEFT:
			_echelon(fac, inf, air, out, true)
		TPL_ECHELON_RIGHT:
			_echelon(fac, inf, air, out, false)
		TPL_HOLLOW_SQUARE:
			_hollow_square(fac, inf, air, out)
		TPL_MIXED_ORDER:
			_mixed_order(fac, inf, air, out)
	_place_rank_bands(fac, screen, overwatch, battery, train, inf, out)
	for i in n:
		var air_i := Kinds.is_air(int(kinds[i]))
		var p := clamp_legal(fac, Vector2(float(out[i].x), float(out[i].y)), air_i)
		out[i].x = p.x
		out[i].y = p.y
	_separate_land(fac, kinds, out)
	return out


static func _order_line_band(template: int, inf: Array, kinds: Array) -> Array:
	var ordered: Array = inf.duplicate()
	ordered.sort_custom(func(a, b):
		var pa := Kinds.line_priority(int(kinds[a]))
		var pb := Kinds.line_priority(int(kinds[b]))
		if pa != pb:
			return pa < pb
		return int(a) < int(b)
	)
	if template != TPL_WEDGE:
		return ordered
	var melee: Array = []
	var rest: Array = []
	for i in ordered:
		if Kinds.line_priority(int(kinds[i])) == 0:
			melee.append(i)
		else:
			rest.append(i)
	var mid := int(rest.size() / 2)
	return rest.slice(0, mid) + melee + rest.slice(mid, rest.size())


static func is_legal_land(fac: int, p: Vector2) -> bool:
	if land_blocked(p.x, p.y):
		return false
	if fac == 0:
		return p.x < BW * 0.5 - 10.0 and p.x > 20.0
	return p.x > BW * 0.5 + 10.0 and p.x < BW - 20.0


static func land_blocked(x: float, y: float) -> bool:
	var dh := Vector2(x - HILL_CX, y - HILL_CY).length()
	var dr := Vector2(x - RUIN_CX, y - RUIN_CY).length()
	return dh < HILL_BLOCK_R or dr < RUIN_R


static func clamp_legal(fac: int, p: Vector2, air: bool) -> Vector2:
	var q := p if air else _slide(p)
	if fac == 0:
		q.x = clampf(q.x, 30.0, BW * 0.5 - 30.0)
	else:
		q.x = clampf(q.x, BW * 0.5 + 30.0, BW - 30.0)
	q.y = clampf(q.y, 24.0, BH - 24.0)
	if not air:
		q = _clear_land(fac, q)
	return q


static func _clear_land(fac: int, p: Vector2) -> Vector2:
	var q := p
	for _i in 6:
		if not land_blocked(q.x, q.y):
			break
		q = _slide(q)
		if fac == 0:
			q.x = clampf(q.x, 30.0, BW * 0.5 - 30.0)
		else:
			q.x = clampf(q.x, BW * 0.5 + 30.0, BW - 30.0)
		q.y = clampf(q.y, 24.0, BH - 24.0)
		if land_blocked(q.x, q.y):
			var dy := q.y - HILL_CY
			var rad := HILL_BLOCK_R + 1.8
			if absf(dy) < rad:
				var dx := sqrt(rad * rad - dy * dy)
				if fac == 0:
					q.x = clampf(HILL_CX - dx, 30.0, BW * 0.5 - 30.0)
				else:
					q.x = clampf(HILL_CX + dx, BW * 0.5 + 30.0, BW - 30.0)
			else:
				q.y = clampf(HILL_CY - rad, 24.0, BH - 24.0)
		if land_blocked(q.x, q.y):
			var dr := Vector2(q.x - RUIN_CX, q.y - RUIN_CY)
			if dr.length() < RUIN_R + 0.5:
				q = _slide(q)
	return q


static func _slide(p: Vector2) -> Vector2:
	var x := p.x
	var y := p.y
	for _i in 4:
		var dh := Vector2(x - HILL_CX, y - HILL_CY)
		if dh.length() < 0.001:
			dh = Vector2(-1.0, 0.0)
		if dh.length() < HILL_BLOCK_R:
			var d := maxf(dh.length(), 0.001)
			x = HILL_CX + dh.x / d * (HILL_BLOCK_R + 1.6)
			y = HILL_CY + dh.y / d * (HILL_BLOCK_R + 1.6)
		var dr := Vector2(x - RUIN_CX, y - RUIN_CY)
		if dr.length() < 0.001:
			dr = Vector2(-1.0, 0.0)
		if dr.length() < RUIN_R:
			var d2 := maxf(dr.length(), 0.001)
			x = RUIN_CX + dr.x / d2 * (RUIN_R + 1.2)
			y = RUIN_CY + dr.y / d2 * (RUIN_R + 1.2)
	return Vector2(clampf(x, 20.0, BW - 20.0), clampf(y, 20.0, BH - 20.0))


static func _x_along(fac: int, t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	if fac == 0:
		return lerpf(105.0, 390.0, u)
	return lerpf(895.0, 610.0, u)


static func _face_enemy(fac: int) -> float:
	return 0.0 if fac == 0 else PI


static func _spread_y(n: int, y0: float = 70.0, y1: float = 530.0) -> PackedFloat32Array:
	var ys := PackedFloat32Array()
	ys.resize(n)
	if n <= 0:
		return ys
	if n == 1:
		ys[0] = (y0 + y1) * 0.5
		return ys
	for i in n:
		ys[i] = lerpf(y0, y1, float(i) / float(n - 1))
	return ys


static func _put(
	out: Array,
	i: int,
	x: float,
	y: float,
	facing: float,
	formation: int,
	order: int
) -> void:
	out[i] = {
		"x": x,
		"y": y,
		"facing": facing,
		"formation": formation,
		"order": order,
	}


static func _battle_line(fac: int, inf: Array, air: Array, out: Array) -> void:
	var face := _face_enemy(fac)
	var n := inf.size()
	var two := n > 12
	var ys := _spread_y(n)
	if two:
		var half := int(ceil(float(n) / 2.0))
		var y_front := _spread_y(half)
		var y_back := _spread_y(n - half)
		var xf := _x_along(fac, 0.42)
		var xb := _x_along(fac, 0.28)
		for k in n:
			if k < half:
				_put(out, inf[k], xf, y_front[k], face, FORM_LINE, ORDER_FRONT)
			else:
				_put(out, inf[k], xb, y_back[k - half], face, FORM_LINE, ORDER_FRONT)
	else:
		var x := _x_along(fac, 0.36)
		for k in n:
			_put(out, inf[k], x, ys[k], face, FORM_LINE, ORDER_FRONT)
	_bombers_behind(fac, air, out, 0.16)


static func _attack_column(fac: int, inf: Array, air: Array, out: Array) -> void:
	var face := _face_enemy(fac)
	var n := inf.size()
	var files := 1
	if n > 10:
		files = 2
	if n > 24:
		files = 3
	var ranks := 1 if n == 0 else (n + files - 1) / files
	var y_mid := 230.0
	var file_sp := 26.0
	var tip := _x_along(fac, 0.84)
	var rear_limit := _x_along(fac, 0.10)
	var depth := absf(tip - rear_limit)
	var rank_sp := 30.0
	if ranks > 1:
		rank_sp = minf(30.0, depth / float(ranks - 1))
	var back_sign := -1.0 if fac == 0 else 1.0
	for k in n:
		var file := k % files
		var rank := k / files
		var y := y_mid + (float(file) - float(files - 1) * 0.5) * file_sp
		var x := tip + back_sign * float(rank) * rank_sp
		_put(out, inf[k], x, y, face, FORM_COLUMN, ORDER_FRONT)
	var rear_t := 0.84 - 0.08 * float(maxi(ranks, 1))
	_bombers_behind(fac, air, out, clampf(rear_t, 0.08, 0.5), y_mid - 40.0, y_mid + 40.0)


static func _chevron(fac: int, inf: Array, air: Array, out: Array, wedge: bool) -> void:
	var face := _face_enemy(fac)
	var n := inf.size()
	var ys := _spread_y(n)
	var form := FORM_WEDGE if wedge else FORM_LINE
	for k in n:
		var t := 0.5 if n == 1 else float(k) / float(n - 1)
		var wing := absf(t - 0.5) * 2.0
		var advance := (1.0 - wing * 0.88) if wedge else (0.12 + wing * 0.78)
		var x := _x_along(fac, 0.22 + advance * 0.58)
		var order := ORDER_FRONT
		if not wedge:
			if n >= 3:
				if fac == 0:
					if t < 0.34:
						order = ORDER_LEFT
					elif t > 0.66:
						order = ORDER_RIGHT
				else:
					if t > 0.66:
						order = ORDER_LEFT
					elif t < 0.34:
						order = ORDER_RIGHT
		_put(out, inf[k], x, ys[k], face, form, order)
	if wedge:
		_bombers_behind(fac, air, out, 0.14)
	else:
		_bombers_behind(fac, air, out, 0.18, 220.0, 380.0)


static func _echelon(fac: int, inf: Array, air: Array, out: Array, left: bool) -> void:
	var face := _face_enemy(fac)
	var n := inf.size()
	var ys := _spread_y(n)
	for k in n:
		var t := 0.5 if n == 1 else float(k) / float(n - 1)
		var advance: float
		if fac == 0:
			advance = (1.0 - t) if left else t
		else:
			advance = t if left else (1.0 - t)
		var x := _x_along(fac, 0.20 + advance * 0.58)
		var order := ORDER_FRONT
		if n >= 3:
			if left:
				var on_left := (fac == 0 and t < 0.34) or (fac == 1 and t > 0.66)
				if on_left:
					order = ORDER_LEFT
			else:
				var on_right := (fac == 0 and t > 0.66) or (fac == 1 and t < 0.34)
				if on_right:
					order = ORDER_RIGHT
		_put(out, inf[k], x, ys[k], face, FORM_LINE, order)
	_bombers_behind(fac, air, out, 0.18, _weight_y0(fac, left), _weight_y1(fac, left))


static func _weight_y0(fac: int, left: bool) -> float:
	if fac == 0:
		return 70.0 if left else 360.0
	return 360.0 if left else 70.0


static func _weight_y1(fac: int, left: bool) -> float:
	if fac == 0:
		return 240.0 if left else 530.0
	return 530.0 if left else 240.0


static func _hollow_square(fac: int, inf: Array, air: Array, out: Array) -> void:
	var n := inf.size()
	var front_x := _x_along(fac, 0.50)
	var rear_x := _x_along(fac, 0.12)
	var y0 := 70.0
	var y1 := 320.0
	var face_e := _face_enemy(fac)
	var face_home := PI if fac == 0 else 0.0
	var face_n := -PI * 0.5
	var face_s := PI * 0.5
	if n <= 0:
		_bombers_at(fac, air, out, (front_x + rear_x) * 0.5, (y0 + y1) * 0.5)
		return
	if n == 1:
		_put(out, inf[0], (front_x + rear_x) * 0.5, (y0 + y1) * 0.5, face_e, FORM_LINE, ORDER_FRONT)
	elif n == 2:
		_put(out, inf[0], front_x, (y0 + y1) * 0.5, face_e, FORM_LINE, ORDER_FRONT)
		_put(out, inf[1], rear_x, (y0 + y1) * 0.5, face_home, FORM_LINE, ORDER_REAR)
	elif n == 3:
		_put(out, inf[0], front_x, (y0 + y1) * 0.5, face_e, FORM_LINE, ORDER_FRONT)
		_put(out, inf[1], (front_x + rear_x) * 0.5, y0, face_n, FORM_LINE, _flank_order(fac, true))
		_put(out, inf[2], (front_x + rear_x) * 0.5, y1, face_s, FORM_LINE, _flank_order(fac, false))
	else:
		var perim_w := absf(front_x - rear_x)
		var perim_h := absf(y1 - y0)
		var perim := 2.0 * (perim_w + perim_h)
		for i in n:
			var d := (float(i) / float(n)) * perim
			var x := front_x
			var y := y0
			var facing := face_e
			var order := ORDER_FRONT
			if d <= perim_h:
				var u := d / maxf(perim_h, 0.001)
				x = front_x
				y = lerpf(y0, y1, u)
				facing = face_e
				order = ORDER_FRONT
			elif d <= perim_h + perim_w:
				var u := (d - perim_h) / maxf(perim_w, 0.001)
				x = lerpf(front_x, rear_x, u)
				y = y1
				facing = face_s
				order = _flank_order(fac, false)
			elif d <= perim_h * 2.0 + perim_w:
				var u := (d - perim_h - perim_w) / maxf(perim_h, 0.001)
				x = rear_x
				y = lerpf(y1, y0, u)
				facing = face_home
				order = ORDER_REAR
			else:
				var u := (d - perim_h * 2.0 - perim_w) / maxf(perim_w, 0.001)
				x = lerpf(rear_x, front_x, u)
				y = y0
				facing = face_n
				order = _flank_order(fac, true)
			_put(out, inf[i], x, y, facing, FORM_LINE, order)
	_bombers_at(fac, air, out, (front_x + rear_x) * 0.5, (y0 + y1) * 0.5)


static func _flank_order(fac: int, top: bool) -> int:
	# Top of the slab is Blue's left / Red's right.
	if top:
		return ORDER_LEFT if fac == 0 else ORDER_RIGHT
	return ORDER_RIGHT if fac == 0 else ORDER_LEFT


static func _mixed_order(fac: int, inf: Array, air: Array, out: Array) -> void:
	var face := _face_enemy(fac)
	var n := inf.size()
	var ys := _spread_y(n)
	var x := _x_along(fac, 0.36)
	for k in n:
		var form := FORM_LINE if (k % 2) == 0 else FORM_COLUMN
		_put(out, inf[k], x, ys[k], face, form, ORDER_FRONT)
	if fac == 0:
		_bombers_behind(fac, air, out, 0.14, 400.0, 540.0)
	else:
		_bombers_behind(fac, air, out, 0.14, 70.0, 210.0)


static func _bombers_behind(
	fac: int,
	air: Array,
	out: Array,
	t: float,
	y0: float = 80.0,
	y1: float = 520.0
) -> void:
	var x := _x_along(fac, t)
	var ys := _spread_y(air.size(), y0, y1)
	var face := _face_enemy(fac)
	for k in air.size():
		_put(out, air[k], x, ys[k], face, FORM_LINE, ORDER_FRONT)


static func _bombers_at(fac: int, air: Array, out: Array, x: float, y: float) -> void:
	var face := _face_enemy(fac)
	var n := air.size()
	if n == 0:
		return
	if n == 1:
		_put(out, air[0], x, y, face, FORM_LINE, ORDER_FRONT)
		return
	var ys := _spread_y(n, y - 28.0, y + 28.0)
	for k in n:
		_put(out, air[k], x, ys[k], face, FORM_LINE, ORDER_FRONT)


static func _place_rank_bands(
	fac: int,
	screen: Array,
	overwatch: Array,
	battery: Array,
	train: Array,
	inf: Array,
	out: Array
) -> void:
	var face := _face_enemy(fac)
	var line_x := _x_along(fac, 0.36)
	if not inf.is_empty():
		var acc := 0.0
		for i in inf:
			acc += float(out[i].x)
		line_x = acc / float(inf.size())
	var ahead := 52.0 if fac == 0 else -52.0
	_put_band(fac, screen, out, line_x + ahead, 90.0, 510.0, face, FORM_LINE, ORDER_FRONT)
	_put_band(fac, overwatch, out, line_x - ahead * 0.4, 80.0, 520.0, face, FORM_LINE, ORDER_FRONT)
	_put_band(fac, battery, out, line_x - ahead * 0.95, 110.0, 490.0, face, FORM_LINE, ORDER_FRONT)
	_put_band(fac, train, out, line_x - ahead * 1.4, 130.0, 470.0, face, FORM_LINE, ORDER_FRONT)


static func _put_band(
	fac: int,
	idxs: Array,
	out: Array,
	x: float,
	y0: float,
	y1: float,
	face: float,
	formation: int,
	order: int
) -> void:
	if idxs.is_empty():
		return
	var ys := _spread_y(idxs.size(), y0, y1)
	for k in idxs.size():
		_put(out, idxs[k], x, ys[k], face, formation, order)


static func _separate_land(fac: int, kinds: Array, out: Array) -> void:
	var land: Array = []
	for i in kinds.size():
		if not Kinds.is_air(int(kinds[i])):
			land.append(i)
	if land.size() < 2:
		return
	var min_sp := minf(12.0, 500.0 / float(maxi(land.size() - 1, 1)))
	min_sp = maxf(min_sp, 6.0)
	for _pass in 5:
		for a in land.size():
			for b in range(a + 1, land.size()):
				var i: int = land[a]
				var j: int = land[b]
				var pa := Vector2(float(out[i].x), float(out[i].y))
				var pb := Vector2(float(out[j].x), float(out[j].y))
				var d := pa.distance_to(pb)
				var push := Vector2.ZERO
				if d < 0.0001:
					push = Vector2(0.0, min_sp * 0.5)
				elif d < min_sp:
					push = (pb - pa).normalized() * ((min_sp - d) * 0.5)
				else:
					continue
				var qa := clamp_legal(fac, pa - push, false)
				var qb := clamp_legal(fac, pb + push, false)
				out[i].x = qa.x
				out[i].y = qa.y
				out[j].x = qb.x
				out[j].y = qb.y
