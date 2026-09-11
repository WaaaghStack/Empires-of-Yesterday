extends Control

## Total War-style Custom Battle builder: army cards + deploy map.
## Shape beforehand (composition + formation + facing + order), then Fight.
## Does not reference autoloads so headless parse-check stays clean.

signal fight_requested(params: Dictionary)
signal cancelled

const UiTheme := preload("res://GameTheme.gd")
const ArmyTpl := preload("res://ArmyTemplates.gd")
const Kinds := preload("res://BattleKinds.gd")

const BW := 1000.0
const BH := 600.0
const HILL_CX := 260.0
const HILL_CY := 460.0
const HILL_BLOCK_R := 140.0 * 0.92
const RUIN_CX := 100.0
const RUIN_CY := 55.0
const RUIN_R := 27.5
const RIVER_X := 500.0
const MAX_INF := 50
const MAX_WINGS := 16
const MAX_UNITS := 10000
const INF_N := 100
const DEFAULT_ARMY: Array = [0, 0, 2, 4, 3, 5, 6, 7, 1]

const FORM_LINE := 0
const FORM_DOUBLE := 1
const FORM_COLUMN := 2
const FORM_WEDGE := 3

var _units: Array = []
var _sel: Array = []
var _next_id: int = 1
var _form: int = FORM_LINE
var _order0: int = 0
var _order1: int = 0
var _seed: int = 1
var _inf_n: int = INF_N
var _inf_spin: SpinBox
var _field: Control
var _fight_btn: Button
var _hint: Label
var _list0: VBoxContainer
var _list1: VBoxContainer
var _scroll0: ScrollContainer
var _scroll1: ScrollContainer
var _form_btns: Array = []
var _army_btns: Array = [[], []]
var _army_tpl: Array = [-1, -1]
var _seed_spin: SpinBox
var _order0_opt: OptionButton
var _order1_opt: OptionButton
var _sel_order_opt: OptionButton
var _busy: bool = false
var _wait: Dictionary = {}

var _boxing: bool = false
var _box_a := Vector2.ZERO
var _box_b := Vector2.ZERO
var _rmb: bool = false
var _rmb_a := Vector2.ZERO
var _rmb_b := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	UiTheme.apply_to_control(self)
	_build()
	_seed_default_armies()
	_refresh()


func _build() -> void:
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.clip_contents = true
	root.add_theme_stylebox_override(
		"panel", UiTheme.make_panel_style(Color(0.07, 0.09, 0.13, 0.97))
	)
	add_child(root)

	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vb)

	vb.add_child(_build_chrome())
	vb.add_child(_build_tool_stack())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(body)

	body.add_child(_make_side_column("Blue", 0))

	_field = Control.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_field.gui_input.connect(_on_field_input)
	_field.draw.connect(_on_field_draw)
	body.add_child(_field)

	body.add_child(_make_side_column("Red", 1))

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_hint.add_theme_font_size_override("font_size", 13)
	vb.add_child(_hint)


func _build_chrome() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Custom Battle"
	title.add_theme_font_size_override("font_size", 24)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(110, 40)
	UiTheme.apply_ghost_button(back)
	back.pressed.connect(func(): cancelled.emit())
	row.add_child(back)
	_fight_btn = Button.new()
	_fight_btn.text = "Fight!"
	_fight_btn.custom_minimum_size = Vector2(140, 40)
	UiTheme.apply_primary_button(_fight_btn)
	_fight_btn.pressed.connect(_on_fight)
	row.add_child(_fight_btn)
	return row


func _tool_scroll(row: HBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 44
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.add_child(row)
	return scroll


func _build_tool_stack() -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(_tool_scroll(_build_regiment_row()))
	wrap.add_child(_tool_scroll(_build_army_row(0)))
	wrap.add_child(_tool_scroll(_build_army_row(1)))
	return wrap


func _build_army_row(fac: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lb := Label.new()
	lb.text = "Blue army" if fac == 0 else "Red army"
	row.add_child(lb)
	_army_btns[fac] = []
	for i in ArmyTpl.TPL_NAMES.size():
		var b := Button.new()
		b.text = String(ArmyTpl.TPL_NAMES[i])
		b.custom_minimum_size = Vector2(92, 36)
		b.pressed.connect(_on_army_tpl.bind(fac, i))
		row.add_child(b)
		_army_btns[fac].append(b)
	return row


func _build_regiment_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var forms := ["Line", "Double", "Column", "Wedge"]
	for i in forms.size():
		var b := Button.new()
		b.text = forms[i]
		b.custom_minimum_size = Vector2(88, 36)
		b.pressed.connect(_on_form_pressed.bind(i))
		row.add_child(b)
		_form_btns.append(b)

	row.add_child(_order_box("Blue default", true))
	row.add_child(_order_box("Red default", false))
	row.add_child(_sel_order_box())

	var seed_lbl := Label.new()
	seed_lbl.text = "Seed"
	row.add_child(seed_lbl)
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 2147483647
	_seed_spin.step = 1
	_seed_spin.value = 1
	_seed_spin.rounded = true
	_seed_spin.custom_minimum_size = Vector2(120, 0)
	_seed_spin.value_changed.connect(func(v: float): _seed = int(v))
	row.add_child(_seed_spin)
	var reroll := Button.new()
	reroll.text = "Reroll"
	UiTheme.apply_ghost_button(reroll)
	reroll.pressed.connect(func(): _seed_spin.value = float(randi() & 0x7FFFFFFF))
	row.add_child(reroll)

	var inf_lbl := Label.new()
	inf_lbl.text = "Hearthline"
	row.add_child(inf_lbl)
	_inf_spin = SpinBox.new()
	_inf_spin.min_value = 20
	_inf_spin.max_value = 500
	_inf_spin.step = 10
	_inf_spin.value = INF_N
	_inf_spin.rounded = true
	_inf_spin.custom_minimum_size = Vector2(88, 0)
	_inf_spin.value_changed.connect(func(v: float):
		_inf_n = clampi(int(v), 20, 500)
		_refresh()
	)
	row.add_child(_inf_spin)
	var stress := Button.new()
	stress.text = "10k stress"
	UiTheme.apply_ghost_button(stress)
	stress.pressed.connect(_fill_10k)
	row.add_child(stress)
	return row


func _order_box(label: String, blue: bool) -> HBoxContainer:
	var box := HBoxContainer.new()
	var lb := Label.new()
	lb.text = label
	box.add_child(lb)
	var opt := OptionButton.new()
	opt.add_item("Front", 0)
	opt.add_item("Attack left", 1)
	opt.add_item("Attack right", 2)
	opt.add_item("Attack rear", 3)
	opt.custom_minimum_size = Vector2(140, 0)
	if blue:
		_order0_opt = opt
		opt.item_selected.connect(func(i: int): _on_side_order(true, i))
	else:
		_order1_opt = opt
		opt.item_selected.connect(func(i: int): _on_side_order(false, i))
	box.add_child(opt)
	return box


func _sel_order_box() -> HBoxContainer:
	var box := HBoxContainer.new()
	var lb := Label.new()
	lb.text = "Selected"
	box.add_child(lb)
	_sel_order_opt = OptionButton.new()
	_fill_order_items(_sel_order_opt)
	_sel_order_opt.custom_minimum_size = Vector2(140, 0)
	_sel_order_opt.item_selected.connect(_on_sel_order)
	box.add_child(_sel_order_opt)
	return box


func _fill_order_items(opt: OptionButton) -> void:
	opt.add_item("Front", 0)
	opt.add_item("Attack left", 1)
	opt.add_item("Attack right", 2)
	opt.add_item("Attack rear", 3)


func _on_side_order(blue: bool, i: int) -> void:
	if blue:
		_order0 = i
	else:
		_order1 = i
	var fac := 0 if blue else 1
	for u in _units:
		if int(u.fac) == fac:
			u.order = i
	_refresh()


func _on_sel_order(i: int) -> void:
	for u_i in _sel:
		_units[u_i].order = i
	if _field:
		_field.queue_redraw()
	_rebuild_list(_list0, 0)
	_rebuild_list(_list1, 1)


func _sync_sel_order_opt() -> void:
	if _sel_order_opt == null:
		return
	_sel_order_opt.disabled = _sel.is_empty()
	_sel_order_opt.set_block_signals(true)
	if _sel.is_empty():
		_sel_order_opt.select(0)
	else:
		var o := int(_units[_sel[0]].get("order", 0))
		for i in _sel:
			if int(_units[i].get("order", 0)) != o:
				o = 0
				break
		_sel_order_opt.select(o)
	_sel_order_opt.set_block_signals(false)


func _on_card_order(oid: int, unit_i: int) -> void:
	_set_unit_order(unit_i, oid)


func _set_unit_order(i: int, o: int) -> void:
	if i < 0 or i >= _units.size():
		return
	_units[i].order = o
	_sync_sel_order_opt()
	if _field:
		_field.queue_redraw()


func _make_side_column(title: String, fac: int) -> PanelContainer:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(268, 0)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	wrap.add_theme_stylebox_override(
		"panel", UiTheme.make_panel_style(Color(0.09, 0.11, 0.16, 0.92))
	)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(vb)
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", 18)
	vb.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiTheme.configure_scroll(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	scroll.resized.connect(func():
		list.custom_minimum_size.x = maxf(scroll.size.x - 8.0, 0.0)
	)
	vb.add_child(scroll)
	if fac == 0:
		_list0 = list
		_scroll0 = scroll
	else:
		_list1 = list
		_scroll1 = scroll
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for k in Kinds.COUNT:
		var b := Button.new()
		b.text = "+ " + Kinds.short_name(k)
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		UiTheme.apply_ghost_button(b)
		b.pressed.connect(_add_card.bind(fac, k))
		grid.add_child(b)
	vb.add_child(grid)
	return wrap


func _seed_default_armies() -> void:
	_units.clear()
	_sel.clear()
	_next_id = 1
	for k in DEFAULT_ARMY:
		_add_card(0, int(k), false)
	for k in DEFAULT_ARMY:
		_add_card(1, int(k), false)
	_apply_army_template(0, ArmyTpl.TPL_BATTLE_LINE, false)
	_apply_army_template(1, ArmyTpl.TPL_BATTLE_LINE, false)


func _regiment_n(kind: int) -> int:
	return Kinds.regiment_size(kind, _inf_n)


func _count_air(fac: int) -> int:
	var n := 0
	for u in _units:
		if int(u.fac) == fac and Kinds.is_air(int(u.kind)):
			n += 1
	return n


func _count_land(fac: int) -> int:
	var n := 0
	for u in _units:
		if int(u.fac) == fac and not Kinds.is_air(int(u.kind)):
			n += 1
	return n


func _bodies() -> int:
	var n := 0
	for u in _units:
		n += _regiment_n(int(u.kind))
	return n


func _add_card(fac: int, kind: int, refresh: bool = true) -> void:
	kind = Kinds.clamp_kind(kind)
	if Kinds.is_air(kind):
		if _count_air(fac) >= MAX_WINGS:
			return
	elif _count_land(fac) >= MAX_INF:
		return
	var add := _regiment_n(kind)
	if _bodies() + add > MAX_UNITS:
		return
	var p := _auto_slot(fac, kind)
	_units.append({
		"id": _next_id,
		"fac": fac,
		"kind": kind,
		"x": p.x,
		"y": p.y,
		"facing": 0.0 if fac == 0 else PI,
		"formation": _form,
		"order": _order0 if fac == 0 else _order1,
	})
	_next_id += 1
	if refresh:
		_refresh()
		_scroll_side_end(fac)


func _fill_10k() -> void:
	_inf_n = INF_N
	if _inf_spin:
		_inf_spin.set_block_signals(true)
		_inf_spin.value = INF_N
		_inf_spin.set_block_signals(false)
	_units.clear()
	_sel.clear()
	_next_id = 1
	for i in 50:
		_add_card(0, 0, false)
	for i in 50:
		_add_card(1, 0, false)
	_apply_army_template(0, ArmyTpl.TPL_BATTLE_LINE, false)
	_apply_army_template(1, ArmyTpl.TPL_BATTLE_LINE, false)
	_refresh()
	_scroll_side_end(0)
	_scroll_side_end(1)


func _scroll_side_end(fac: int) -> void:
	var sc := _scroll0 if fac == 0 else _scroll1
	UiTheme.scroll_to_bottom(sc)


func _auto_slot(fac: int, kind: int) -> Vector2:
	var t := 0.36
	match Kinds.rank(kind):
		Kinds.RANK_SCREEN:
			t = 0.48
		Kinds.RANK_OVERWATCH:
			t = 0.30
		Kinds.RANK_BATTERY:
			t = 0.22
		Kinds.RANK_TRAIN:
			t = 0.12
		Kinds.RANK_AIR:
			t = 0.10
		_:
			t = 0.36
	var x := ArmyTpl._x_along(fac, t)
	var n := 0
	var rnk := Kinds.rank(kind)
	for u in _units:
		if int(u.fac) == fac and Kinds.rank(int(u.kind)) == rnk:
			n += 1
	var y := 50.0 + float(n) * 36.0
	y = clampf(y, 40.0, BH - 40.0)
	return _clamp_legal(fac, Vector2(x, y))


func _on_army_tpl(fac: int, template: int) -> void:
	_apply_army_template(fac, template)


func _apply_army_template(fac: int, template: int, refresh: bool = true) -> void:
	var idxs: Array = []
	var kinds: Array = []
	for i in _units.size():
		if int(_units[i].fac) == fac:
			idxs.append(i)
			kinds.append(int(_units[i].kind))
	if idxs.is_empty():
		return
	var placed: Array = ArmyTpl.layout(fac, template, kinds)
	for k in idxs.size():
		var u: Dictionary = _units[idxs[k]]
		var p: Dictionary = placed[k]
		u.x = float(p.x)
		u.y = float(p.y)
		u.facing = float(p.facing)
		u.formation = int(p.formation)
		u.order = int(p.order)
		_units[idxs[k]] = u
	_army_tpl[fac] = template
	_sel.clear()
	if refresh:
		_refresh()


func _on_form_pressed(i: int) -> void:
	_form = i
	for u_i in _sel:
		_units[u_i].formation = i
	if _sel.size() >= 2:
		_spread_selection()
	_refresh()


func _spread_selection() -> void:
	if _sel.size() < 2:
		return
	var pts: Array = []
	for i in _sel:
		pts.append(Vector2(_units[i].x, _units[i].y))
	pts.sort_custom(func(a, b): return a.y < b.y)
	_arrange_sel(pts[0], pts[pts.size() - 1])


func _on_fight() -> void:
	if _busy or not _can_fight():
		return
	_busy = true
	_fight_btn.disabled = true
	_fight_btn.text = "Resolving…"
	_wait = UiTheme.attach_resolve_wait(self, _bodies())
	await get_tree().process_frame
	await get_tree().process_frame
	var roster: Array = []
	for u in _units:
		roster.append({
			"faction": int(u.fac),
			"kind": int(u.kind),
			"count": _regiment_n(int(u.kind)),
			"x": float(u.x),
			"y": float(u.y),
			"facing": float(u.facing),
			"formation": int(u.formation),
			"order": int(u.get("order", 0)),
		})
	fight_requested.emit({
		"seed": maxi(_seed, 1),
		"order0": _order0,
		"order1": _order1,
		"roster": roster,
	})


func _can_fight() -> bool:
	if _units.is_empty():
		return false
	var has0 := false
	var has1 := false
	for u in _units:
		if not _is_legal(u):
			return false
		if int(u.fac) == 0:
			has0 = true
		else:
			has1 = true
	return has0 and has1 and _bodies() <= MAX_UNITS


func _is_legal(u: Dictionary) -> bool:
	var p := Vector2(float(u.x), float(u.y))
	if land_blocked(p.x, p.y) and not Kinds.is_air(int(u.kind)):
		return false
	if int(u.fac) == 0:
		return p.x < BW * 0.5 - 10.0 and p.x > 20.0
	return p.x > BW * 0.5 + 10.0 and p.x < BW - 20.0


func land_blocked(x: float, y: float) -> bool:
	var dh := Vector2(x - HILL_CX, y - HILL_CY).length()
	var dr := Vector2(x - RUIN_CX, y - RUIN_CY).length()
	return dh < HILL_BLOCK_R or dr < RUIN_R


func _slide(p: Vector2) -> Vector2:
	var x := p.x
	var y := p.y
	for _i in 3:
		var dh := Vector2(x - HILL_CX, y - HILL_CY)
		if dh.length() < HILL_BLOCK_R:
			var d := maxf(dh.length(), 0.001)
			x = HILL_CX + dh.x / d * (HILL_BLOCK_R + 1.6)
			y = HILL_CY + dh.y / d * (HILL_BLOCK_R + 1.6)
		var dr := Vector2(x - RUIN_CX, y - RUIN_CY)
		if dr.length() < RUIN_R:
			var d2 := maxf(dr.length(), 0.001)
			x = RUIN_CX + dr.x / d2 * (RUIN_R + 1.2)
			y = RUIN_CY + dr.y / d2 * (RUIN_R + 1.2)
	return Vector2(clampf(x, 20.0, BW - 20.0), clampf(y, 20.0, BH - 20.0))


func _clamp_legal(fac: int, p: Vector2) -> Vector2:
	var q := _slide(p)
	if fac == 0:
		q.x = minf(q.x, BW * 0.5 - 30.0)
	else:
		q.x = maxf(q.x, BW * 0.5 + 30.0)
	return q


func _refresh() -> void:
	_rebuild_list(_list0, 0)
	_rebuild_list(_list1, 1)
	for i in _form_btns.size():
		if int(_form) == i:
			UiTheme.apply_latched_button(_form_btns[i])
		else:
			UiTheme.apply_ghost_button(_form_btns[i])
	for fac in 2:
		var btns: Array = _army_btns[fac]
		for i in btns.size():
			if int(_army_tpl[fac]) == i:
				UiTheme.apply_latched_button(btns[i])
			else:
				UiTheme.apply_ghost_button(btns[i])
	var ok := _can_fight()
	if _busy:
		_fight_btn.disabled = true
		_fight_btn.text = "Resolving…"
	else:
		_fight_btn.disabled = not ok
		_fight_btn.text = "Fight! (%d)" % _bodies()
	_sync_sel_order_opt()
	var n := _bodies()
	if n > MAX_UNITS:
		_hint.text = "Over the 10,000 cap (%d). Lower Hearthline size or remove cards." % n
	elif ok:
		_hint.text = "Eight Compact jobs. Hearthline size is the spinbox; other cards have fixed bodies. Army buttons place by rank. 10k stress is Hearthline only."
	else:
		_hint.text = "Fight stays off until every unit sits on its own half, clear of the hill. Add cards from the Compact palette, then place them."
	if _field:
		_field.queue_redraw()


func _rebuild_list(list: VBoxContainer, fac: int) -> void:
	if list == null:
		return
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for i in _units.size():
		var u: Dictionary = _units[i]
		if int(u.fac) != fac:
			continue
		var row := HBoxContainer.new()
		var lab := Button.new()
		var kind_s := "%s %d" % [Kinds.short_name(int(u.kind)), _regiment_n(int(u.kind))]
		lab.text = kind_s
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _sel.has(i):
			UiTheme.apply_latched_button(lab)
		else:
			UiTheme.apply_ghost_button(lab)
		lab.pressed.connect(_on_card_clicked.bind(i), CONNECT_DEFERRED)
		row.add_child(lab)
		var ord := OptionButton.new()
		_fill_order_items(ord)
		ord.custom_minimum_size = Vector2(118, 32)
		ord.set_block_signals(true)
		ord.select(int(u.get("order", 0)))
		ord.set_block_signals(false)
		ord.item_selected.connect(_on_card_order.bind(i))
		row.add_child(ord)
		var rm := Button.new()
		rm.text = "×"
		rm.custom_minimum_size = Vector2(36, 32)
		UiTheme.apply_ghost_button(rm)
		rm.pressed.connect(_remove_at.bind(i), CONNECT_DEFERRED)
		row.add_child(rm)
		list.add_child(row)


func _remove_at(i: int) -> void:
	if i < 0 or i >= _units.size():
		return
	_units.remove_at(i)
	_sel.clear()
	_refresh()


func _on_card_clicked(i: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		if _sel.has(i):
			_sel.erase(i)
		else:
			_sel.append(i)
	else:
		_sel = [i]
	_refresh()


func _map_rect() -> Rect2:
	var sz := _field.size
	var aspect := BW / BH
	var w := sz.x
	var h := w / aspect
	if h > sz.y:
		h = sz.y
		w = h * aspect
	var o := Vector2((sz.x - w) * 0.5, (sz.y - h) * 0.5)
	return Rect2(o, Vector2(w, h))


func _world_to_ctrl(p: Vector2) -> Vector2:
	var r := _map_rect()
	return Vector2(r.position.x + p.x / BW * r.size.x, r.position.y + p.y / BH * r.size.y)


func _ctrl_to_world(p: Vector2) -> Vector2:
	var r := _map_rect()
	var q := (p - r.position) / r.size
	return Vector2(q.x * BW, q.y * BH)


func _on_field_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var wp := _ctrl_to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_boxing = true
				_box_a = wp
				_box_b = wp
				var hit := _hit_unit(wp)
				if hit >= 0:
					_boxing = false
					if Input.is_key_pressed(KEY_SHIFT):
						if _sel.has(hit):
							_sel.erase(hit)
						else:
							_sel.append(hit)
					else:
						_sel = [hit]
					_refresh()
			else:
				if _boxing:
					_box_b = wp
					_finish_box()
				_boxing = false
				_field.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if _sel.is_empty():
					return
				_rmb = true
				_rmb_a = wp
				_rmb_b = wp
			else:
				if _rmb:
					_rmb_b = wp
					_arrange_sel(_rmb_a, _rmb_b)
				_rmb = false
				_refresh()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var wp := _ctrl_to_world(mm.position)
		if _boxing:
			_box_b = wp
			_field.queue_redraw()
		if _rmb:
			_rmb_b = wp
			_field.queue_redraw()


func _hit_unit(wp: Vector2) -> int:
	var best := -1
	var best_d := 6.0
	for i in _units.size():
		var u: Dictionary = _units[i]
		var d := wp.distance_to(Vector2(float(u.x), float(u.y)))
		if d < best_d:
			best_d = d
			best = i
	return best


func _finish_box() -> void:
	var r := Rect2(_box_a, _box_b - _box_a).abs()
	if r.size.length() < 4.0:
		return
	if not Input.is_key_pressed(KEY_SHIFT):
		_sel.clear()
	for i in _units.size():
		var u: Dictionary = _units[i]
		if r.has_point(Vector2(float(u.x), float(u.y))) and not _sel.has(i):
			_sel.append(i)
	_refresh()


func _arrange_sel(from: Vector2, to: Vector2) -> void:
	if _sel.is_empty():
		return
	var fac := int(_units[_sel[0]].fac)
	var along := to - from
	if along.length() < 4.0:
		along = Vector2(0.0, 14.0 * maxf(float(_sel.size() - 1), 1.0))
		to = from + along
	var perp := Vector2(-along.y, along.x)
	if perp.length() < 0.001:
		perp = Vector2(1.0, 0.0)
	perp = perp.normalized()
	var toward := Vector2(1.0, 0.0) if fac == 0 else Vector2(-1.0, 0.0)
	if perp.dot(toward) < 0.0:
		perp = -perp
	var ang := perp.angle()
	var n := _sel.size()
	var min_sp := 14.0
	match _form:
		FORM_LINE:
			for k in n:
				var t := 0.5 if n == 1 else float(k) / float(n - 1)
				var p := from.lerp(to, t)
				if n > 1 and from.distance_to(to) < min_sp * float(n - 1):
					p = from + along.normalized() * min_sp * float(k)
				_place_unit(_sel[k], p, ang)
		FORM_DOUBLE:
			var half := int(ceil(float(n) / 2.0))
			for k in n:
				var row := 0 if k < half else 1
				var col := k if k < half else k - half
				var cols := half if row == 0 else n - half
				var t := 0.5 if cols <= 1 else float(col) / float(cols - 1)
				var p := from.lerp(to, t) - perp * float(row) * 14.0
				_place_unit(_sel[k], p, ang)
		FORM_COLUMN:
			for k in n:
				var p := from + along.normalized() * (along.length() * 0.15) - perp * min_sp * float(k)
				_place_unit(_sel[k], p, ang)
		FORM_WEDGE:
			for k in n:
				var t := 0.5 if n == 1 else float(k) / float(n - 1)
				var p := from.lerp(to, t) + perp * (0.5 - absf(t - 0.5)) * 28.0
				_place_unit(_sel[k], p, ang)


func _place_unit(i: int, p: Vector2, ang: float) -> void:
	var u: Dictionary = _units[i]
	var q := _clamp_legal(int(u.fac), p)
	u.x = q.x
	u.y = q.y
	u.facing = ang
	u.formation = _form
	_units[i] = u


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		var d := Vector2.ZERO
		match k.keycode:
			KEY_LEFT, KEY_A:
				d.x = -2.0
			KEY_RIGHT, KEY_D:
				d.x = 2.0
			KEY_UP, KEY_W:
				d.y = -2.0
			KEY_DOWN, KEY_S:
				d.y = 2.0
			_:
				return
		for i in _sel:
			var u: Dictionary = _units[i]
			_place_unit(i, Vector2(float(u.x), float(u.y)) + d, float(u.facing))
		_refresh()
		get_viewport().set_input_as_handled()


func _on_field_draw() -> void:
	var r := _map_rect()
	_field.draw_rect(r, Color(0.18, 0.28, 0.16, 1.0), true)
	# River
	var rx := r.position.x + (RIVER_X / BW) * r.size.x
	var rw := (60.0 / BW) * r.size.x
	_field.draw_rect(Rect2(rx - rw * 0.5, r.position.y, rw, r.size.y), Color(0.22, 0.42, 0.62, 0.85), true)
	# Hill
	var hc := _world_to_ctrl(Vector2(HILL_CX, HILL_CY))
	var hr := (HILL_BLOCK_R / BW) * r.size.x
	_field.draw_circle(hc, hr, Color(0.36, 0.34, 0.28, 0.95))
	var rc := _world_to_ctrl(Vector2(RUIN_CX, RUIN_CY))
	_field.draw_circle(rc, (RUIN_R / BW) * r.size.x, Color(0.42, 0.40, 0.36, 0.9))
	# Midline
	var mx := r.position.x + r.size.x * 0.5
	_field.draw_line(Vector2(mx, r.position.y), Vector2(mx, r.position.y + r.size.y), Color(1, 1, 1, 0.12), 1.0)
	for i in _units.size():
		var u: Dictionary = _units[i]
		var p := _world_to_ctrl(Vector2(float(u.x), float(u.y)))
		var col := Color(0.35, 0.72, 1.0) if int(u.fac) == 0 else Color(0.92, 0.32, 0.34)
		if _sel.has(i):
			_field.draw_circle(p, 9.0, Color(1, 0.92, 0.45, 0.85))
		var rad := 6.0
		var knd := int(u.kind)
		if Kinds.is_air(knd):
			rad = 8.0
		elif knd == Kinds.LEDGER_PIECES:
			rad = 7.0
		elif knd == Kinds.ROLLING_HEARTHS:
			rad = 8.5
		_field.draw_circle(p, rad, col)
		var face := Vector2.from_angle(float(u.facing))
		var tip := p + Vector2(face.x, face.y) * 12.0
		_field.draw_line(p, tip, Color(1, 1, 1, 0.8), 2.0)
		var tag: String = "F"
		match clampi(int(u.get("order", 0)), 0, 3):
			1:
				tag = "L"
			2:
				tag = "R"
			3:
				tag = "Rr"
		_field.draw_string(ThemeDB.fallback_font, p + Vector2(8, -6), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
	if _boxing:
		var a := _world_to_ctrl(_box_a)
		var b := _world_to_ctrl(_box_b)
		_field.draw_rect(Rect2(a, b - a).abs(), Color(1, 1, 1, 0.12), true)
		_field.draw_rect(Rect2(a, b - a).abs(), Color(1, 1, 1, 0.45), false, 1.0)
	if _rmb:
		_field.draw_line(_world_to_ctrl(_rmb_a), _world_to_ctrl(_rmb_b), Color(1, 0.92, 0.45, 0.9), 2.0)
