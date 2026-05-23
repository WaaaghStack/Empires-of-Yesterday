class_name MapVisuals
extends RefCounted

const FACILITY_THEMES: Array[String] = ["industrial", "bio", "command"]

static func pick_facility_theme(rng: RandomNumberGenerator) -> String:
	return FACILITY_THEMES[rng.randi() % FACILITY_THEMES.size()]


static func get_facility_palette(theme: String) -> Dictionary:
	match theme:
		"bio":
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
		"command":
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
