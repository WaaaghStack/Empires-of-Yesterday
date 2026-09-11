extends SceneTree

## Headless checks for Custom Battle army templates.
## godot --headless --path . -s res://army_template_headless_test.gd

const ArmyTpl := preload("res://ArmyTemplates.gd")
const Setup := preload("res://CustomBattleSetup.gd")
const Kinds := preload("res://BattleKinds.gd")


func _init() -> void:
	print("=== Army Templates Headless ===")
	var fail := 0
	fail += _check_empty()
	fail += _check_one()
	fail += _check_default_roster()
	fail += _check_fifty()
	fail += _check_setup_hooks()
	fail += _check_compact_ranks()
	fail += _check_hearthline_only_line()
	fail += _check_ledger_sheet()
	fail += _check_shot_styles()
	fail += _check_attack_styles()
	if fail == 0:
		print("PASS army templates headless")
	else:
		push_error("FAIL army templates (%d checks)" % fail)
	quit()


func _kinds(inf_n: int, air_n: int) -> Array:
	var k: Array = []
	for _i in inf_n:
		k.append(0)
	for _j in air_n:
		k.append(1)
	return k


func _inf(placed: Array, kinds: Array) -> Array:
	var pts: Array = []
	for i in placed.size():
		if Kinds.is_air(int(kinds[i])):
			continue
		pts.append(Vector2(float(placed[i].x), float(placed[i].y)))
	return pts


func _air(placed: Array, kinds: Array) -> Array:
	var pts: Array = []
	for i in placed.size():
		if not Kinds.is_air(int(kinds[i])):
			continue
		pts.append(Vector2(float(placed[i].x), float(placed[i].y)))
	return pts


func _bbox(pts: Array) -> Dictionary:
	var min_x := 9999.0
	var max_x := -9999.0
	var min_y := 9999.0
	var max_y := -9999.0
	for p in pts:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y,
		"width": max_y - min_y,
		"depth": max_x - min_x,
	}


func _min_gap(pts: Array) -> float:
	var best := 9999.0
	for a in pts.size():
		for b in range(a + 1, pts.size()):
			best = minf(best, pts[a].distance_to(pts[b]))
	return best


func _legal(fac: int, placed: Array, kinds: Array) -> bool:
	for i in placed.size():
		var p := Vector2(float(placed[i].x), float(placed[i].y))
		if Kinds.is_air(int(kinds[i])):
			if fac == 0 and (p.x >= 500.0 - 10.0 or p.x <= 20.0):
				return false
			if fac == 1 and (p.x <= 500.0 + 10.0 or p.x >= 980.0):
				return false
			continue
		if not ArmyTpl.is_legal_land(fac, p):
			return false
	return true


func _check_empty() -> int:
	var out: Array = ArmyTpl.layout(0, ArmyTpl.TPL_BATTLE_LINE, [])
	if out.size() != 0:
		push_error("empty kinds should return empty")
		return 1
	print("  empty ok")
	return 0


func _check_one() -> int:
	var kinds := [0]
	var out: Array = ArmyTpl.layout(0, ArmyTpl.TPL_HOLLOW_SQUARE, kinds)
	if out.size() != 1:
		push_error("single infantry square size")
		return 1
	if not ArmyTpl.is_legal_land(0, Vector2(float(out[0].x), float(out[0].y))):
		push_error("single square not legal")
		return 1
	print("  single-card square ok")
	return 0


func _check_default_roster() -> int:
	var kinds := _kinds(8, 2)
	var fac := 0
	var layouts: Array = []
	for t in 8:
		var placed: Array = ArmyTpl.layout(fac, t, kinds)
		if placed.size() != kinds.size():
			push_error("template %d size" % t)
			return 1
		if not _legal(fac, placed, kinds):
			push_error("template %d illegal pads" % t)
			return 1
		var again: Array = ArmyTpl.layout(fac, t, kinds)
		if absf(float(again[0].x) - float(placed[0].x)) > 0.01:
			push_error("template %d not deterministic" % t)
			return 1
		var inf := _inf(placed, kinds)
		var air := _air(placed, kinds)
		if _min_gap(inf) < 6.0:
			push_error("template %d inf stacked (gap=%.2f)" % [t, _min_gap(inf)])
			return 1
		var inf_mean_x := 0.0
		for p in inf:
			inf_mean_x += p.x
		inf_mean_x /= float(inf.size())
		var air_mean_x := 0.0
		for p in air:
			air_mean_x += p.x
		air_mean_x /= float(air.size())
		if air_mean_x >= inf_mean_x - 2.0 and t != ArmyTpl.TPL_HOLLOW_SQUARE:
			push_error("template %d bombers not behind infantry" % t)
			return 1
		if t == ArmyTpl.TPL_HOLLOW_SQUARE:
			var bb := _bbox(inf)
			var cx := (float(bb["min_x"]) + float(bb["max_x"])) * 0.5
			var cy := (float(bb["min_y"]) + float(bb["max_y"])) * 0.5
			if air[0].distance_to(Vector2(cx, cy)) > 80.0:
				push_error("square bombers not in the hollow")
				return 1
		layouts.append(placed)
	var line := _bbox(_inf(layouts[ArmyTpl.TPL_BATTLE_LINE], kinds))
	var col := _bbox(_inf(layouts[ArmyTpl.TPL_ATTACK_COLUMN], kinds))
	if line.width < col.width + 80.0:
		push_error("Battle Line should be wider than Attack Column")
		return 1
	if col.depth < line.depth + 40.0:
		push_error("Attack Column should be deeper than Battle Line")
		return 1
	var wedge_inf: Array = _inf(layouts[ArmyTpl.TPL_WEDGE], kinds)
	var vee_inf: Array = _inf(layouts[ArmyTpl.TPL_VEE], kinds)
	var w_mid := _mid_x(wedge_inf)
	var w_wing := _wing_x(wedge_inf)
	var v_mid := _mid_x(vee_inf)
	var v_wing := _wing_x(vee_inf)
	if w_mid <= w_wing:
		push_error("Wedge tip should sit ahead of the wings")
		return 1
	if v_mid >= v_wing:
		push_error("Vee center should sit behind the wings")
		return 1
	var ech_l: Array = _inf(layouts[ArmyTpl.TPL_ECHELON_LEFT], kinds)
	var ech_r: Array = _inf(layouts[ArmyTpl.TPL_ECHELON_RIGHT], kinds)
	var left_y := _extreme_x(ech_l, true)
	var right_y := _extreme_x(ech_r, true)
	if left_y <= right_y:
		push_error("Echelon Left should advance the top (Blue left) vs Echelon Right")
		return 1
	var mixed: Array = layouts[ArmyTpl.TPL_MIXED_ORDER]
	var saw_line := false
	var saw_col := false
	for i in kinds.size():
		if int(kinds[i]) == 1:
			continue
		var f := int(mixed[i].formation)
		if f == ArmyTpl.FORM_LINE:
			saw_line = true
		if f == ArmyTpl.FORM_COLUMN:
			saw_col = true
	if not (saw_line and saw_col):
		push_error("Mixed Order should alternate Line and Column")
		return 1
	print("  8-template distinctness / legal / bombers ok")
	return 0


func _mid_x(pts: Array) -> float:
	var ys: Array = []
	for p in pts:
		ys.append(p)
	ys.sort_custom(func(a, b): return a.y < b.y)
	return ys[ys.size() / 2].x


func _wing_x(pts: Array) -> float:
	var ys: Array = []
	for p in pts:
		ys.append(p)
	ys.sort_custom(func(a, b): return a.y < b.y)
	return (ys[0].x + ys[ys.size() - 1].x) * 0.5


func _extreme_x(pts: Array, smallest_y: bool) -> float:
	var best: Vector2 = pts[0]
	for p in pts:
		if smallest_y and p.y < best.y:
			best = p
		if not smallest_y and p.y > best.y:
			best = p
	return best.x


func _check_fifty() -> int:
	var kinds := _kinds(50, 4)
	for t in 8:
		var placed: Array = ArmyTpl.layout(0, t, kinds)
		if not _legal(0, placed, kinds):
			push_error("50-card template %d illegal" % t)
			return 1
		var inf := _inf(placed, kinds)
		if _min_gap(inf) < 5.0:
			push_error("50-card template %d stacked" % t)
			return 1
		var red: Array = ArmyTpl.layout(1, t, kinds)
		if not _legal(1, red, kinds):
			push_error("red 50-card template %d illegal" % t)
			return 1
	print("  50-card + wings legal on both halves")
	return 0


func _check_setup_hooks() -> int:
	var src := FileAccess.get_file_as_string("res://CustomBattleSetup.gd")
	if not src.contains("_on_army_tpl") or not src.contains("Blue army"):
		push_error("CustomBattleSetup missing army template bar")
		return 1
	if not src.contains("ArmyTpl.layout"):
		push_error("CustomBattleSetup does not apply ArmyTemplates.layout")
		return 1
	if not src.contains("BattleKinds") or not src.contains("DEFAULT_ARMY"):
		push_error("CustomBattleSetup missing Compact palette")
		return 1
	var script: GDScript = Setup
	if script == null:
		push_error("CustomBattleSetup.gd failed to parse")
		return 1
	var node: Control = Setup.new()
	node._ready()
	if node._units.size() < 16:
		push_error("default Compact armies too small (%d)" % node._units.size())
		return 1
	var saw := PackedByteArray()
	saw.resize(8)
	saw.fill(0)
	for u in node._units:
		saw[clampi(int(u.kind), 0, 7)] = 1
	for k in 8:
		if saw[k] == 0:
			push_error("default army missing kind %d" % k)
			return 1
	node.queue_free()
	print("  CustomBattleSetup hooks ok")
	return 0


func _mean_kind_x(placed: Array, kinds: Array, kind: int) -> float:
	var acc := 0.0
	var n := 0
	for i in kinds.size():
		if int(kinds[i]) != kind:
			continue
		acc += float(placed[i].x)
		n += 1
	if n == 0:
		return 0.0
	return acc / float(n)


func _check_compact_ranks() -> int:
	var kinds: Array = [0, 0, 2, 4, 3, 5, 6, 7, 1]
	for t in 8:
		var placed: Array = ArmyTpl.layout(0, t, kinds)
		if placed.size() != kinds.size():
			push_error("compact template %d size" % t)
			return 1
		if not _legal(0, placed, kinds):
			push_error("compact template %d illegal" % t)
			return 1
		var land := _inf(placed, kinds)
		if _min_gap(land) < 5.0:
			push_error("compact template %d land stacked (gap=%.2f)" % [t, _min_gap(land)])
			return 1
	var line: Array = ArmyTpl.layout(0, ArmyTpl.TPL_BATTLE_LINE, kinds)
	var hearth_x := _mean_kind_x(line, kinds, 0)
	var walk_x := _mean_kind_x(line, kinds, 4)
	var ledger_x := _mean_kind_x(line, kinds, 5)
	var train_x := _mean_kind_x(line, kinds, 6)
	var air_x := _mean_kind_x(line, kinds, 1)
	if walk_x <= hearth_x:
		push_error("Walk-Mappers should screen ahead of Hearthline")
		return 1
	if ledger_x >= hearth_x:
		push_error("Ledger Pieces should sit behind the line")
		return 1
	if train_x >= ledger_x:
		push_error("Rolling Hearths should sit behind the battery")
		return 1
	if air_x >= hearth_x - 2.0:
		push_error("Debt Wings should sit behind the line")
		return 1
	var col: Array = ArmyTpl.layout(0, ArmyTpl.TPL_ATTACK_COLUMN, kinds)
	var stove_x := _mean_kind_x(col, kinds, 2)
	var hearth_col := _mean_kind_x(col, kinds, 0)
	if stove_x <= hearth_col:
		push_error("Attack Column should put Stovebreakers ahead of Hearthline")
		return 1
	var wedge: Array = ArmyTpl.layout(0, ArmyTpl.TPL_WEDGE, kinds)
	var stove_w := _mean_kind_x(wedge, kinds, 2)
	var hearth_w := _mean_kind_x(wedge, kinds, 0)
	if stove_w <= hearth_w:
		push_error("Wedge tip should put Stovebreakers ahead of Hearthline")
		return 1
	print("  compact rank bands ok")
	return 0


func _check_hearthline_only_line() -> int:
	var kinds := _kinds(12, 0)
	var line: Array = ArmyTpl.layout(0, ArmyTpl.TPL_BATTLE_LINE, kinds)
	var col: Array = ArmyTpl.layout(0, ArmyTpl.TPL_ATTACK_COLUMN, kinds)
	if line.size() != 12 or col.size() != 12:
		push_error("hearthline-only size")
		return 1
	if not _legal(0, line, kinds) or not _legal(0, col, kinds):
		push_error("hearthline-only illegal")
		return 1
	var ys: Array = []
	for p in line:
		ys.append(float(p.y))
	ys.sort()
	for i in range(1, ys.size()):
		if ys[i] <= ys[i - 1]:
			push_error("hearthline-only Battle Line should stay a vertical infantry file")
			return 1
	print("  hearthline-only line ok")
	return 0


func _check_ledger_sheet() -> int:
	if Kinds.sheet_cols(Kinds.LEDGER_PIECES) != 2:
		push_error("Ledger Pieces need a 2-frame idle|fire sheet")
		return 1
	if not String(Kinds.friendly_tex(Kinds.LEDGER_PIECES)).ends_with("ledger_pieces_friendly_sheet.png"):
		push_error("Ledger friendly tex should be the idle|fire sheet")
		return 1
	if not String(Kinds.hostile_tex(Kinds.LEDGER_PIECES)).ends_with("ledger_pieces_hostile_sheet.png"):
		push_error("Ledger hostile tex should be the idle|fire sheet")
		return 1
	print("  ledger idle/fire sheet ok")
	return 0


func _check_shot_styles() -> int:
	var want := {
		0: Kinds.SHOT_RIFLE,
		1: Kinds.SHOT_BOMB,
		2: Kinds.SHOT_HEAT,
		3: Kinds.SHOT_SATCHEL,
		4: Kinds.SHOT_RIFLE,
		5: Kinds.SHOT_SHELL,
		6: Kinds.SHOT_NONE,
		7: Kinds.SHOT_FLAK,
	}
	for k in want.keys():
		if Kinds.shot_style(int(k)) != int(want[k]):
			push_error("shot_style kind %d should be %d" % [int(k), int(want[k])])
			return 1
	print("  per-kind shot styles ok")
	return 0


func _check_attack_styles() -> int:
	if Kinds.attack_style(Kinds.HEARTHLINE) != Kinds.STYLE_HOLD:
		push_error("Hearthline should hold")
		return 1
	if Kinds.attack_style(Kinds.LEDGER_PIECES) != Kinds.STYLE_HOLD:
		push_error("Ledger should hold")
		return 1
	if Kinds.attack_style(Kinds.WALK_MAPPERS) != Kinds.STYLE_HOLD:
		push_error("Walk-Mappers should hold")
		return 1
	if Kinds.attack_style(Kinds.CEILING_CLERKS) != Kinds.STYLE_HOLD:
		push_error("Ceiling Clerks should hold")
		return 1
	if Kinds.attack_style(Kinds.STOVEBREAKERS) != Kinds.STYLE_CHARGE:
		push_error("Stovebreakers should charge")
		return 1
	if Kinds.attack_style(Kinds.ASH_WARDENS) != Kinds.STYLE_CHARGE:
		push_error("Ash Wardens should charge")
		return 1
	if Kinds.attack_style(Kinds.DEBT_WINGS) != Kinds.STYLE_DRIVE_BY:
		push_error("Debt Wings should drive-by")
		return 1
	if Kinds.attack_style(Kinds.ROLLING_HEARTHS) != Kinds.STYLE_TRAIN:
		push_error("Rolling Hearths should stay train")
		return 1
	print("  per-kind attack styles ok")
	return 0
