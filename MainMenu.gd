extends Control

const EnemyStrategyLib := preload("res://EnemyStrategy.gd")
const CFG := preload("res://WorldConquestConfig.gd")
const _LAND_MASK: Texture2D = preload("res://data/earth/land_mask_360x180.png")

@onready var main_panel: PanelContainer = $MainPanel
@onready var custom_panel: PanelContainer = $CustomWorldPanel
@onready var seed_label: Label = $MainPanel/VBox/SeedLabel
@onready var theater_blurb: Label = $MainPanel/VBox/TheaterBlurb
@onready var earth_btn: Button = $MainPanel/VBox/TheaterRow/EarthBtn
@onready var pangea_btn: Button = $MainPanel/VBox/TheaterRow/PangeaBtn
@onready var arch_btn: Button = $MainPanel/VBox/TheaterRow/ArchBtn
@onready var play_button: Button = $MainPanel/VBox/PlayButton
@onready var custom_world_button: Button = $MainPanel/VBox/CustomWorldButton
@onready var settings_button: Button = $MainPanel/VBox/SettingsButton
@onready var ai_vs_ai_check: CheckBox = $MainPanel/VBox/AiVsAiCheck
@onready var quit_button: Button = $QuitButton

@onready var custom_seed_label: Label = $CustomWorldPanel/VBox/SeedCartouche/SeedRow/CustomSeedLabel
@onready var copy_seed_button: Button = $CustomWorldPanel/VBox/SeedCartouche/SeedRow/CopySeedButton
@onready var reroll_seed_button: Button = $CustomWorldPanel/VBox/SeedCartouche/SeedRow/RerollSeedButton
@onready var custom_theater_option: OptionButton = $CustomWorldPanel/VBox/TheaterRow/CustomTheaterOption
@onready var map_hint: Label = $CustomWorldPanel/VBox/MapHint
@onready var land_bias_slider: HSlider = $CustomWorldPanel/VBox/LandBiasRow/LandBiasSlider
@onready var land_bias_value: Label = $CustomWorldPanel/VBox/LandBiasRow/LandBiasValue
@onready var resource_density_slider: HSlider = $CustomWorldPanel/VBox/ResourceRow/ResourceDensitySlider
@onready var resource_density_value: Label = $CustomWorldPanel/VBox/ResourceRow/ResourceDensityValue
@onready var mountain_bias_slider: HSlider = $CustomWorldPanel/VBox/MountainRow/MountainBiasSlider
@onready var mountain_bias_value: Label = $CustomWorldPanel/VBox/MountainRow/MountainBiasValue
@onready var any_region_btn: Button = $CustomWorldPanel/VBox/StartRegionRow/AnyRegionBtn
@onready var west_region_btn: Button = $CustomWorldPanel/VBox/StartRegionRow/WestRegionBtn
@onready var east_region_btn: Button = $CustomWorldPanel/VBox/StartRegionRow/EastRegionBtn
@onready var difficulty_option: OptionButton = $CustomWorldPanel/VBox/DifficultyRow/DifficultyOption
@onready var difficulty_hint: Label = $CustomWorldPanel/VBox/DifficultyHint
@onready var generate_play_button: Button = $CustomWorldPanel/VBox/GeneratePlayButton
@onready var custom_back_button: Button = $CustomWorldPanel/VBox/BackButton
@onready var hero_globe: Node3D = $GlobeLayer/SubViewport/MenuHeroGlobe
@onready var sketch_caption: Label = $SketchCaption

var _custom_seed: int = 0
var _theater_id: String = CFG.THEATER_EARTH
var _settings_open: bool = false
var _start_region_id: int = 0


func _ready() -> void:
	GameTheme.apply_to_control(self)
	GameTheme.ignore_mouse($Background)
	GameTheme.ignore_mouse($GlobeLayer)
	GameTheme.ignore_mouse(sketch_caption)
	main_panel.add_theme_stylebox_override(
		"panel", GameTheme.make_panel_style(Color(0.09, 0.11, 0.16, 0.78))
	)
	custom_panel.add_theme_stylebox_override(
		"panel", GameTheme.make_panel_style(Color(0.09, 0.11, 0.16, 0.78))
	)
	var seed_cartouche: PanelContainer = $CustomWorldPanel/VBox/SeedCartouche
	if seed_cartouche:
		seed_cartouche.add_theme_stylebox_override(
			"panel",
			GameTheme.make_panel_style(Color(0.09, 0.11, 0.16, 0.50), GameTheme.BORDER, 4)
		)
	GameTheme.apply_primary_button(play_button)
	GameTheme.apply_primary_button(generate_play_button)
	GameTheme.apply_ghost_button(custom_world_button)
	GameTheme.apply_ghost_button(settings_button)
	GameTheme.apply_ghost_button(quit_button)
	GameTheme.apply_ghost_button(custom_back_button)
	GameTheme.apply_ghost_button(copy_seed_button)
	GameTheme.apply_ghost_button(reroll_seed_button)
	play_button.pressed.connect(_on_play_pressed)
	custom_world_button.pressed.connect(_on_custom_world_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	if copy_seed_button:
		copy_seed_button.pressed.connect(_on_copy_seed_pressed)
	reroll_seed_button.pressed.connect(_on_reroll_seed_pressed)
	generate_play_button.pressed.connect(_on_generate_play_pressed)
	custom_back_button.pressed.connect(_on_custom_back_pressed)
	land_bias_slider.value_changed.connect(_on_land_bias_changed)
	resource_density_slider.value_changed.connect(_on_resource_density_changed)
	mountain_bias_slider.value_changed.connect(_on_mountain_bias_changed)
	earth_btn.pressed.connect(_on_theater_card.bind(CFG.THEATER_EARTH))
	pangea_btn.pressed.connect(_on_theater_card.bind(CFG.THEATER_PANGEA))
	arch_btn.pressed.connect(_on_theater_card.bind(CFG.THEATER_ARCHIPELAGO))
	earth_btn.tooltip_text = CFG.theater_blurb(CFG.THEATER_EARTH)
	pangea_btn.tooltip_text = CFG.theater_blurb(CFG.THEATER_PANGEA)
	arch_btn.tooltip_text = CFG.theater_blurb(CFG.THEATER_ARCHIPELAGO)
	if any_region_btn:
		any_region_btn.pressed.connect(_on_start_region_pressed.bind(0))
	if west_region_btn:
		west_region_btn.pressed.connect(_on_start_region_pressed.bind(1))
	if east_region_btn:
		east_region_btn.pressed.connect(_on_start_region_pressed.bind(2))
	if ai_vs_ai_check:
		ai_vs_ai_check.button_pressed = RunState.ai_vs_ai
		ai_vs_ai_check.visible = false
		ai_vs_ai_check.tooltip_text = (
			"Both sides expand with the outpost AI. Deploy is skipped; you can orbit/zoom and watch. Hold Shift on Play to enable without opening Settings."
		)
	_setup_theater_crops()
	_setup_custom_options()
	_setup_theater_options()
	_select_theater(_theater_id)
	_show_main()
	_refresh_seed_label()
	_refresh_hero_globe()
	RunLog.info("MainMenu opened (world conquest)")


func _setup_theater_crops() -> void:
	earth_btn.icon = _make_theater_crop(0)
	pangea_btn.icon = _make_theater_crop(1)
	arch_btn.icon = _make_theater_crop(2)
	for btn in [earth_btn, pangea_btn, arch_btn]:
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.add_theme_constant_override("icon_max_width", 104)


func _make_theater_crop(mode: int) -> ImageTexture:
	var img := Image.create(104, 44, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.14, 0.32, 1.0))
	if mode == 0 and _LAND_MASK != null:
		var src: Image = _LAND_MASK.get_image()
		if src != null and not src.is_empty():
			var sw: int = src.get_width()
			var sh: int = src.get_height()
			for y in range(44):
				var sy: int = clampi(int(float(y) / 44.0 * float(sh)), 0, sh - 1)
				for x in range(104):
					var sx: int = clampi(int(float(x) / 104.0 * float(sw)), 0, sw - 1)
					var v: float = src.get_pixel(sx, sy).r
					if v > 0.42:
						img.set_pixel(x, y, Color(0.42, 0.58, 0.34, 1.0))
			return ImageTexture.create_from_image(img)
	for y in range(44):
		for x in range(104):
			var n: float = _hash21(Vector2(float(x) * 0.07 + float(mode) * 3.1, float(y) * 0.11))
			var thresh: float = 0.55 if mode == 1 else 0.68
			if n > thresh:
				img.set_pixel(x, y, Color(0.48, 0.44, 0.34, 1.0) if mode == 1 else Color(0.38, 0.55, 0.36, 1.0))
	return ImageTexture.create_from_image(img)


func _hash21(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


func _setup_custom_options() -> void:
	difficulty_option.clear()
	difficulty_option.add_item("Beginner — fewer pumps", EnemyStrategyLib.Difficulty.BEGINNER)
	difficulty_option.add_item("Medium — standard posture", EnemyStrategyLib.Difficulty.MEDIUM)
	difficulty_option.add_item("Expert — aggressive spacing", EnemyStrategyLib.Difficulty.EXPERT)
	difficulty_option.select(EnemyStrategyLib.Difficulty.MEDIUM)
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	land_bias_slider.min_value = -1.0
	land_bias_slider.max_value = 1.0
	land_bias_slider.step = 0.05
	land_bias_slider.value = 0.0
	resource_density_slider.min_value = 0.25
	resource_density_slider.max_value = 2.0
	resource_density_slider.step = 0.05
	resource_density_slider.value = 1.0
	mountain_bias_slider.min_value = -1.0
	mountain_bias_slider.max_value = 1.0
	mountain_bias_slider.step = 0.05
	mountain_bias_slider.value = 0.0
	_on_land_bias_changed(0.0)
	_on_resource_density_changed(1.0)
	_on_mountain_bias_changed(0.0)
	_on_difficulty_selected(difficulty_option.selected)
	_reroll_custom_seed()
	_select_start_region(0)


func _setup_theater_options() -> void:
	_fill_theater_option(custom_theater_option)
	if custom_theater_option:
		custom_theater_option.item_selected.connect(_on_custom_theater_selected)


func _fill_theater_option(opt: OptionButton) -> void:
	if opt == null:
		return
	opt.clear()
	for i in range(CFG.THEATER_IDS.size()):
		var tid: String = CFG.THEATER_IDS[i]
		opt.add_item(CFG.theater_display_name(tid), i)
		opt.set_item_tooltip(i, CFG.theater_blurb(tid))
	opt.select(0)


func _theater_id_from_option(opt: OptionButton) -> String:
	if opt == null:
		return CFG.THEATER_EARTH
	var idx: int = opt.selected
	if idx < 0 or idx >= CFG.THEATER_IDS.size():
		return CFG.THEATER_EARTH
	return CFG.THEATER_IDS[idx]


func _select_theater_option(opt: OptionButton, theater_id: String) -> void:
	if opt == null:
		return
	var want: String = CFG.normalize_theater_id(theater_id)
	for i in range(CFG.THEATER_IDS.size()):
		if CFG.THEATER_IDS[i] == want:
			opt.select(i)
			return
	opt.select(0)


func _apply_theater_to_sliders(theater_id: String) -> void:
	var preset: Dictionary = CFG.theater_preset(theater_id)
	land_bias_slider.value = float(preset.get("land_bias", 0.0))
	mountain_bias_slider.value = float(preset.get("mountain_bias", 0.0))
	resource_density_slider.value = float(preset.get("resource_density", 1.0))
	_refresh_custom_hint()
	_refresh_hero_globe()
	_refresh_seed_label()


func _on_theater_card(theater_id: String) -> void:
	_select_theater(theater_id)
	_refresh_hero_globe()
	_refresh_seed_label()


func _select_theater(theater_id: String) -> void:
	_theater_id = CFG.normalize_theater_id(theater_id)
	earth_btn.set_pressed_no_signal(_theater_id == CFG.THEATER_EARTH)
	pangea_btn.set_pressed_no_signal(_theater_id == CFG.THEATER_PANGEA)
	arch_btn.set_pressed_no_signal(_theater_id == CFG.THEATER_ARCHIPELAGO)
	if theater_blurb:
		theater_blurb.text = CFG.theater_blurb(_theater_id)
	_style_theater_buttons()


func _style_theater_buttons() -> void:
	for pair in [
		[earth_btn, _theater_id == CFG.THEATER_EARTH],
		[pangea_btn, _theater_id == CFG.THEATER_PANGEA],
		[arch_btn, _theater_id == CFG.THEATER_ARCHIPELAGO],
	]:
		var btn: Button = pair[0]
		var on: bool = bool(pair[1])
		if on:
			GameTheme.apply_latched_button(btn)
		else:
			GameTheme.apply_ghost_button(btn)
			btn.modulate = Color.WHITE


func _on_custom_theater_selected(_idx: int) -> void:
	_apply_theater_to_sliders(_theater_id_from_option(custom_theater_option))


func _show_main() -> void:
	main_panel.visible = true
	custom_panel.visible = false
	quit_button.visible = true
	if sketch_caption:
		sketch_caption.visible = false
	_refresh_hero_globe()


func _show_custom() -> void:
	main_panel.visible = false
	custom_panel.visible = true
	quit_button.visible = false
	if sketch_caption:
		sketch_caption.visible = true
	_refresh_custom_seed_label()
	_refresh_custom_hint()
	_refresh_hero_globe()


func _refresh_seed_label() -> void:
	var theater_name: String = CFG.theater_display_name(_theater_id)
	if RunState.run_seed == 0:
		seed_label.text = "Random %s map each run" % theater_name
	else:
		seed_label.text = "%s seed: %d" % [theater_name, RunState.run_seed]


func _refresh_custom_seed_label() -> void:
	custom_seed_label.text = "Seed  %d" % _custom_seed


func _refresh_custom_hint() -> void:
	if map_hint == null:
		return
	var tid: String = _theater_id_from_option(custom_theater_option)
	if tid == CFG.THEATER_EARTH:
		map_hint.text = "Preview coasts — match uses the real mask."
	else:
		map_hint.text = "Preview continents — match bakes from seed."
	if sketch_caption:
		sketch_caption.text = "Sketch of land fraction — not the match map."


func _refresh_hero_globe() -> void:
	if hero_globe == null or not hero_globe.has_method("apply_theater"):
		return
	var tid: String = _theater_id
	var land: float = 0.0
	var mountain: float = 0.0
	var resource: float = 1.0
	var meridian: int = 0
	if custom_panel.visible:
		tid = _theater_id_from_option(custom_theater_option)
		land = float(land_bias_slider.value)
		mountain = float(mountain_bias_slider.value)
		resource = float(resource_density_slider.value)
		meridian = _start_region_id
	else:
		var preset: Dictionary = CFG.theater_preset(_theater_id)
		land = float(preset.get("land_bias", 0.0))
		mountain = float(preset.get("mountain_bias", 0.0))
		resource = float(preset.get("resource_density", 1.0))
	hero_globe.apply_theater(tid, land, mountain, resource)
	if hero_globe.has_method("set_meridian_highlight"):
		hero_globe.set_meridian_highlight(meridian)


func _reroll_custom_seed() -> void:
	_custom_seed = randi() & 0x7FFFFFFF
	if _custom_seed == 0:
		_custom_seed = 1
	_refresh_custom_seed_label()


func _on_copy_seed_pressed() -> void:
	DisplayServer.clipboard_set(str(_custom_seed))
	if copy_seed_button:
		copy_seed_button.text = "Copied"
		get_tree().create_timer(0.9).timeout.connect(func() -> void:
			if copy_seed_button:
				copy_seed_button.text = "Copy"
		)


func _on_land_bias_changed(v: float) -> void:
	if v < -0.2:
		land_bias_value.text = "Open ocean"
	elif v > 0.2:
		land_bias_value.text = "Supercontinent"
	else:
		land_bias_value.text = "Balanced"
	_refresh_hero_globe()


func _on_resource_density_changed(v: float) -> void:
	if v < 0.7:
		resource_density_value.text = "Sparse"
	elif v > 1.3:
		resource_density_value.text = "Rich"
	else:
		resource_density_value.text = "Typical"
	_refresh_hero_globe()


func _on_mountain_bias_changed(v: float) -> void:
	if v < -0.2:
		mountain_bias_value.text = "Low plains"
	elif v > 0.2:
		mountain_bias_value.text = "High ranges"
	else:
		mountain_bias_value.text = "Mixed"
	_refresh_hero_globe()


func _on_start_region_pressed(region_id: int) -> void:
	_select_start_region(region_id)
	_refresh_hero_globe()


func _select_start_region(region_id: int) -> void:
	_start_region_id = clampi(region_id, 0, 2)
	_style_region_button(any_region_btn, _start_region_id == 0)
	_style_region_button(west_region_btn, _start_region_id == 1)
	_style_region_button(east_region_btn, _start_region_id == 2)


func _style_region_button(btn: Button, on: bool) -> void:
	if btn == null:
		return
	btn.set_pressed_no_signal(on)
	if on:
		GameTheme.apply_latched_button(btn)
	else:
		GameTheme.apply_ghost_button(btn)
		btn.modulate = Color.WHITE


func _on_difficulty_selected(_idx: int) -> void:
	if difficulty_hint == null:
		return
	match difficulty_option.get_selected_id():
		EnemyStrategyLib.Difficulty.BEGINNER:
			difficulty_hint.text = "Opponent plants fewer outposts and waits longer between pumps."
		EnemyStrategyLib.Difficulty.EXPERT:
			difficulty_hint.text = "Opponent spaces pumps tightly and contests land quickly."
		_:
			difficulty_hint.text = "Standard AI posture — the default match."


func _on_settings_pressed() -> void:
	_settings_open = not _settings_open
	if ai_vs_ai_check:
		ai_vs_ai_check.visible = _settings_open
	settings_button.text = "Settings ▾" if _settings_open else "Settings"


func _on_play_pressed() -> void:
	if ai_vs_ai_check:
		RunState.ai_vs_ai = ai_vs_ai_check.button_pressed or Input.is_key_pressed(KEY_SHIFT)
	else:
		RunState.ai_vs_ai = Input.is_key_pressed(KEY_SHIFT)
	RunState.apply_theater(_theater_id)
	RunState.start_region = "any"
	RunState.ai_difficulty = -1
	if RunState.run_seed == 0:
		RunState.run_seed = randi() & 0x7FFFFFFF
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_custom_world_pressed() -> void:
	_select_theater_option(custom_theater_option, _theater_id)
	_apply_theater_to_sliders(_theater_id)
	_show_custom()


func _on_custom_back_pressed() -> void:
	_show_main()


func _on_reroll_seed_pressed() -> void:
	_reroll_custom_seed()


func _start_region_from_option() -> String:
	match _start_region_id:
		1:
			return "west"
		2:
			return "east"
		_:
			return "any"


func _on_generate_play_pressed() -> void:
	if ai_vs_ai_check:
		RunState.ai_vs_ai = ai_vs_ai_check.button_pressed or Input.is_key_pressed(KEY_SHIFT)
	var theater_id: String = _theater_id_from_option(custom_theater_option)
	RunState.apply_theater(theater_id)
	RunState.custom_world = true
	RunState.land_bias = float(land_bias_slider.value)
	RunState.resource_density = float(resource_density_slider.value)
	RunState.mountain_bias = float(mountain_bias_slider.value)
	RunState.start_region = _start_region_from_option()
	RunState.ai_difficulty = int(difficulty_option.get_selected_id())
	RunState.run_seed = _custom_seed
	RunState.world_map_id = "earth"
	RunLog.info(
		(
			"Custom World: theater=%s seed=%d land_bias=%.2f resource=%.2f mountain=%.2f region=%s difficulty=%d procedural=%d"
			% [
				RunState.theater_id,
				RunState.run_seed,
				RunState.land_bias,
				RunState.resource_density,
				RunState.mountain_bias,
				RunState.start_region,
				RunState.ai_difficulty,
				1 if RunState.custom_world else 0,
			]
		)
	)
	get_tree().change_scene_to_file("res://WorldConquestScreen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
