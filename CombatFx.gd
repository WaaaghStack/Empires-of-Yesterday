class_name CombatFx
extends RefCounted

static func spawn_shot(from_node: Node2D, target_global: Vector2, color: Color, width: float = 2.5) -> void:
	if not from_node or not is_instance_valid(from_node):
		return
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.points = PackedVector2Array([Vector2.ZERO, from_node.to_local(target_global)])
	line.z_index = 20
	from_node.add_child(line)
	var tween := from_node.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.12)
	tween.tween_callback(line.queue_free)

static func spawn_impact(at_node: Node2D, color: Color) -> void:
	if not at_node or not is_instance_valid(at_node):
		return
	var flash := Polygon2D.new()
	flash.color = color
	flash.polygon = PackedVector2Array([
		Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6),
	])
	flash.z_index = 21
	at_node.add_child(flash)
	var tween := at_node.create_tween()
	tween.tween_property(flash, "scale", Vector2(1.8, 1.8), 0.08)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.12)
	tween.tween_callback(flash.queue_free)
