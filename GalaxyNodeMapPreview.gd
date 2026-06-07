class_name GalaxyNodeMapPreview
extends RefCounted

const BattleMapGeneratorLib := preload("res://BattleMapGenerator.gd")
const BattleMapDataLib := preload("res://BattleMapData.gd")

const TEX_SIZE := 64
const PREVIEW_PLACEHOLDER_FORCE := 500

static var _cache: Dictionary = {}
static var _cache_run_seed: int = -1


static func invalidate_cache(run_seed: int = -1) -> void:
	if run_seed < 0 or run_seed != _cache_run_seed:
		_cache.clear()
		_cache_run_seed = run_seed


static func preview_texture(node: Dictionary, run_seed: int) -> Texture2D:
	if node.is_empty():
		return null
	var node_type := str(node.get("type", ""))
	if node_type == "hq":
		return null
	if _cache_run_seed != run_seed:
		invalidate_cache(run_seed)
	var node_id := str(node.get("id", ""))
	if node_id.is_empty():
		return null
	var key := "%s" % node_id
	if _cache.has(key):
		return _cache[key] as Texture2D
	var map_data = _generate_map_for_node(node, run_seed)
	if map_data == null:
		return null
	var tex: ImageTexture = _rasterize_circular(map_data)
	_cache[key] = tex
	return tex


static func prewarm_all_nodes(galaxy, run_seed: int) -> void:
	if galaxy == null:
		return
	invalidate_cache(run_seed)
	for node in galaxy.nodes:
		preview_texture(node, run_seed)


static func _generate_map_for_node(node: Dictionary, run_seed: int):
	var node_id := str(node.get("id", ""))
	var terrain := str(node.get("terrain_tag", "open_field"))
	var mix: Dictionary = node.get("terrain_mix", {})
	var node_type := str(node.get("type", "battle"))
	var enemy_force: int = int(node.get("enemy_strength", PREVIEW_PLACEHOLDER_FORCE))
	var seed_val: int = (run_seed + hash(node_id)) & 0x7FFFFFFF
	return BattleMapGeneratorLib.generate(
		seed_val,
		terrain,
		PREVIEW_PLACEHOLDER_FORCE,
		enemy_force,
		node_id,
		mix,
		node_type,
	)


static func _rasterize_circular(map_data) -> ImageTexture:
	var gw: int = map_data.grid_width
	var gh: int = map_data.grid_height
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.07, 0.0))
	var center := Vector2(TEX_SIZE * 0.5, TEX_SIZE * 0.5)
	var radius_sq: float = (TEX_SIZE * 0.5 - 0.5) * (TEX_SIZE * 0.5 - 0.5)
	var edge_soft: float = 2.0
	for py in range(TEX_SIZE):
		for px in range(TEX_SIZE):
			var dx: float = float(px) + 0.5 - center.x
			var dy: float = float(py) + 0.5 - center.y
			var dist_sq: float = dx * dx + dy * dy
			if dist_sq > radius_sq:
				continue
			var dist: float = sqrt(dist_sq)
			var alpha_edge: float = 1.0
			var rim: float = sqrt(radius_sq) - edge_soft
			if dist > rim:
				alpha_edge = clampf(1.0 - (dist - rim) / edge_soft, 0.0, 1.0)
			var gx: int = clampi(int(float(px) / float(TEX_SIZE) * float(gw)), 0, gw - 1)
			var gy: int = clampi(int(float(py) / float(TEX_SIZE) * float(gh)), 0, gh - 1)
			var col: Color = _terrain_color(map_data, gx, gy)
			col.a *= alpha_edge
			img.set_pixel(px, py, col)
	_draw_contact_line(img, map_data, center, radius_sq)
	var tex := ImageTexture.create_from_image(img)
	return tex


static func _draw_contact_line(img: Image, map_data, center: Vector2, radius_sq: float) -> void:
	var gw: int = map_data.grid_width
	var contact_gx: float = float(map_data.contact_column) / float(maxi(1, gw))
	var line_px: int = clampi(int(contact_gx * float(TEX_SIZE)), 0, TEX_SIZE - 1)
	var line_col := Color(0.55, 0.6, 0.7, 0.35)
	for py in range(TEX_SIZE):
		var dy: float = float(py) + 0.5 - center.y
		var dx: float = float(line_px) + 0.5 - center.x
		if dx * dx + dy * dy > radius_sq:
			continue
		var existing: Color = img.get_pixel(line_px, py)
		img.set_pixel(line_px, py, existing.lerp(line_col, 0.55))


static func _terrain_color(map_data, gx: int, gy: int) -> Color:
	var t: int = map_data.get_cell_terrain(gx, gy)
	if t == BattleMapDataLib.Terrain.WATER:
		return Color(0.1, 0.32, 0.52, 0.95)
	if map_data.is_cell_blocked(gx, gy):
		return Color(0.38, 0.4, 0.44, 0.96)
	var h: float = map_data.get_tile_height(gx, gy)
	var height_tint: float = clampf((h - 0.35) * 0.35, -0.12, 0.18)
	var col: Color
	match t:
		BattleMapDataLib.Terrain.WATER:
			col = Color(0.1, 0.32, 0.52, 0.95)
		BattleMapDataLib.Terrain.MOUNTAIN:
			col = (
				Color(0.38, 0.4, 0.44, 0.96)
				if map_data.is_cell_blocked(gx, gy)
				else Color(0.3, 0.34, 0.38, 0.9)
			)
		BattleMapDataLib.Terrain.SAND:
			col = Color(0.52, 0.44, 0.28, 0.88)
		BattleMapDataLib.Terrain.MUD:
			col = Color(0.18, 0.28, 0.14, 0.88)
		_:
			col = Color(0.2, 0.38, 0.18, 0.82)
	col = col.lightened(height_tint)
	var idx: int = map_data.cell_index(gx, gy)
	if map_data.cover_cells.size() > idx and int(map_data.cover_cells[idx]) > 0:
		col = col.lerp(Color(0.1, 0.14, 0.12, 1.0), 0.35)
	return col
