class_name MapVisuals
extends RefCounted

const FACILITY_THEMES: Array[String] = ["colony", "jungle", "crashed_ship"]
const LEGACY_THEME_ALIASES: Dictionary = {
	"industrial": "colony",
	"bio": "jungle",
	"command": "crashed_ship",
}

const COLONY_TILE_SIZE := 64

const COLONY_TILE_PATHS: Dictionary = {
	"floor": "res://assets/tiles/colony/floor.png",
	"floor_alt": "res://assets/tiles/colony/floor_alt.png",
	"corridor": "res://assets/tiles/colony/corridor.png",
	"corridor_stripe": "res://assets/tiles/colony/corridor_stripe.png",
}

static var _tile_cache: Dictionary = {}


static func normalize_theme(theme: String) -> String:
	if theme in FACILITY_THEMES:
		return theme
	return str(LEGACY_THEME_ALIASES.get(theme, theme))


static func pick_facility_theme(rng: RandomNumberGenerator) -> String:
	return FACILITY_THEMES[rng.randi() % FACILITY_THEMES.size()]


static func get_colony_tile(tile_id: String) -> Texture2D:
	if _tile_cache.has(tile_id):
		return _tile_cache[tile_id] as Texture2D
	var path := str(COLONY_TILE_PATHS.get(tile_id, ""))
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		_ensure_colony_tiles()
	var tex: Texture2D = load(path) as Texture2D
	if tex:
		_tile_cache[tile_id] = tex
	return tex


static func has_colony_tiles() -> bool:
	return ResourceLoader.exists(COLONY_TILE_PATHS["floor"])


static func _ensure_colony_tiles() -> void:
	var base_dir := ProjectSettings.globalize_path("res://assets/tiles/colony")
	DirAccess.make_dir_absolute(base_dir)
	for tile_id in COLONY_TILE_PATHS.keys():
		var res_path: String = COLONY_TILE_PATHS[tile_id]
		if ResourceLoader.exists(res_path):
			continue
		var disk_path := ProjectSettings.globalize_path(res_path)
		var color := Color(0.14, 0.16, 0.22, 1.0)
		match tile_id:
			"floor_alt":
				color = Color(0.16, 0.19, 0.26, 1.0)
			"corridor":
				color = Color(0.11, 0.13, 0.18, 1.0)
			"corridor_stripe":
				color = Color(0.22, 0.42, 0.78, 1.0)
		var image := Image.create(COLONY_TILE_SIZE, COLONY_TILE_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(color)
		image.save_png(disk_path)


static func make_tiled_sprite(rect: Rect2, tile_id: String, z_index: int = 0) -> Sprite2D:
	var tex := get_colony_tile(tile_id)
	if tex == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = rect.position
	sprite.scale = Vector2(rect.size.x / float(COLONY_TILE_SIZE), rect.size.y / float(COLONY_TILE_SIZE))
	sprite.z_index = z_index
	return sprite


static func colony_theme_active(theme: String) -> bool:
	return normalize_theme(theme) == "colony"


static func make_colony_tiled_rect(rect: Rect2, filename: String) -> Sprite2D:
	var tile_id := filename.trim_suffix(".png")
	return make_tiled_sprite(rect, tile_id, 0)


static func get_facility_palette(theme: String) -> Dictionary:
	var resolved := normalize_theme(theme)
	match resolved:
		"jungle":
			return {
				"deck": Color(0.04, 0.09, 0.07, 1.0),
				"corridor_floor": Color(0.08, 0.16, 0.12, 1.0),
				"corridor_stripe": Color(0.18, 0.62, 0.38, 0.85),
				"corridor_outline": Color(0.28, 0.52, 0.38, 0.85),
				"hull_outer": Color(0.45, 0.78, 0.55, 1.0),
				"hull_inner": Color(0.25, 0.85, 0.55, 0.95),
				"room_colors": [
					Color(0.15, 0.42, 0.28, 0.22), Color(0.12, 0.35, 0.22, 0.18),
					Color(0.2, 0.5, 0.32, 0.2), Color(0.1, 0.28, 0.2, 0.24),
					Color(0.22, 0.48, 0.35, 0.18), Color(0.08, 0.32, 0.25, 0.2),
				],
			}
		"crashed_ship":
			return {
				"deck": Color(0.08, 0.07, 0.05, 1.0),
				"corridor_floor": Color(0.14, 0.12, 0.09, 1.0),
				"corridor_stripe": Color(0.72, 0.52, 0.18, 0.85),
				"corridor_outline": Color(0.52, 0.42, 0.28, 0.85),
				"hull_outer": Color(0.82, 0.68, 0.38, 1.0),
				"hull_inner": Color(0.95, 0.78, 0.32, 0.95),
				"room_colors": [
					Color(0.45, 0.32, 0.12, 0.22), Color(0.38, 0.28, 0.14, 0.18),
					Color(0.52, 0.38, 0.15, 0.2), Color(0.35, 0.25, 0.12, 0.24),
					Color(0.48, 0.35, 0.18, 0.18), Color(0.42, 0.3, 0.14, 0.2),
				],
			}
		_:
			return {
				"deck": Color(0.07, 0.08, 0.11, 1.0),
				"corridor_floor": Color(0.11, 0.13, 0.17, 1.0),
				"corridor_stripe": Color(0.18, 0.42, 0.82, 0.85),
				"corridor_outline": Color(0.35, 0.42, 0.52, 0.85),
				"hull_outer": Color(0.65, 0.72, 0.85, 1.0),
				"hull_inner": Color(0.35, 0.75, 1.0, 0.95),
				"room_colors": [
					Color(0.2, 0.45, 0.85, 0.22), Color(0.35, 0.35, 0.5, 0.18),
					Color(0.25, 0.3, 0.38, 0.16), Color(0.55, 0.25, 0.2, 0.18),
					Color(0.2, 0.4, 0.22, 0.2), Color(0.35, 0.3, 0.15, 0.2),
				],
			}


static func make_rect_polygon(rect: Rect2, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = color
	poly.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	return poly


static func make_rect_outline(rect: Rect2, color: Color, width: float = 2.0) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.points = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
		rect.position,
	])
	return line


static func make_unit_square(size: float, color: Color) -> Polygon2D:
	var half := size * 0.5
	var poly := Polygon2D.new()
	poly.color = color
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	return poly
