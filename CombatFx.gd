class_name CombatFx
extends RefCounted

const CombatAudioLib := preload("res://CombatAudio.gd")

static func spawn_shot(from_node: Node2D, target_global: Vector2, color: Color, width: float = 2.5) -> void:
	if not from_node or not is_instance_valid(from_node):
		return
	spawn_muzzle_flash(from_node)
	CombatAudioLib.play_shot(from_node)
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.points = PackedVector2Array([Vector2.ZERO, from_node.to_local(target_global)])
	line.z_index = 20
	from_node.add_child(line)
	var tween := from_node.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.12)
	tween.tween_callback(line.queue_free)

static func spawn_muzzle_flash(at_node: Node2D) -> void:
	if not at_node or not is_instance_valid(at_node):
		return
	var flash := Polygon2D.new()
	flash.color = Color(1.0, 0.92, 0.55, 0.95)
	flash.polygon = PackedVector2Array([
		Vector2(8, -3), Vector2(16, 0), Vector2(8, 3), Vector2(0, 0),
	])
	flash.z_index = 22
	at_node.add_child(flash)
	var tween := at_node.create_tween()
	tween.tween_property(flash, "scale", Vector2(1.6, 1.6), 0.04)
	tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.08)
	tween.tween_callback(flash.queue_free)

static func spawn_impact(at_node: Node2D, color: Color) -> void:
	if not at_node or not is_instance_valid(at_node):
		return
	CombatAudioLib.play_impact(at_node)
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
	spawn_sparks(at_node, color)


static func spawn_damage_number(at_node: Node2D, amount: int, color: Color = Color(1.0, 0.35, 0.3, 1.0)) -> void:
	if not at_node or not is_instance_valid(at_node) or amount <= 0:
		return
	var label := Label.new()
	label.text = str(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.z_index = 30
	label.position = Vector2(-12, -28)
	at_node.add_child(label)
	var tween := at_node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 24.0, 0.55)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)

static func spawn_sparks(at_node: Node2D, color: Color) -> void:
	for i in range(4):
		var spark := Line2D.new()
		spark.width = 1.5
		spark.default_color = color
		var angle := randf_range(0.0, TAU)
		var length := randf_range(8.0, 18.0)
		spark.points = PackedVector2Array([
			Vector2.ZERO,
			Vector2(cos(angle), sin(angle)) * length,
		])
		spark.z_index = 21
		at_node.add_child(spark)
		var tween := at_node.create_tween()
		tween.tween_property(spark, "modulate:a", 0.0, 0.14)
		tween.tween_callback(spark.queue_free)

static func spawn_death(at_node: Node2D, color: Color = Color(0.85, 0.2, 0.25, 0.9)) -> void:
	if not at_node or not is_instance_valid(at_node):
		return
	CombatAudioLib.play_death(at_node)
	var burst := Line2D.new()
	burst.width = 3.0
	burst.default_color = color
	burst.closed = true
	burst.points = PackedVector2Array([
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10),
	])
	burst.z_index = 23
	at_node.add_child(burst)
	var tween := at_node.create_tween()
	tween.tween_property(burst, "scale", Vector2(2.2, 2.2), 0.18)
	tween.parallel().tween_property(burst, "modulate:a", 0.0, 0.22)
	tween.tween_callback(burst.queue_free)
