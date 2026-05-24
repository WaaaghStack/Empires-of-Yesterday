class_name EnemySpriteFactory
extends RefCounted

## Procedural top-down hostile silhouettes (cached). Replace with PNGs in assets/Enemies/ later.

const SPRITE_PX := 64
const TARGET_PX := 26.0

static var _cache: Dictionary = {}


static func get_texture(archetype: String, facing: String) -> Texture2D:
	var key := "%s|%s" % [archetype, facing]
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/Enemies/%s_%s.png" % [archetype, facing]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		_cache[key] = tex
		return tex
	var img := _make_silhouette(archetype, facing)
	var built := ImageTexture.create_from_image(img)
	_cache[key] = built
	return built


static func get_scale_for_texture(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ONE
	var w: float = float(tex.get_width())
	if w <= 0.0:
		return Vector2.ONE
	var s: float = TARGET_PX / w
	return Vector2(s, s)


static func _make_silhouette(archetype: String, facing: String) -> Image:
	var img := Image.create(SPRITE_PX, SPRITE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base := Color(0.72, 0.14, 0.42, 1.0)
	match archetype:
		"sniper":
			base = Color(0.48, 0.18, 0.78, 1.0)
		"heavy":
			base = Color(0.78, 0.28, 0.16, 1.0)
	var cx := SPRITE_PX * 0.5
	var cy := SPRITE_PX * 0.5
	# Body blob
	for y in range(SPRITE_PX):
		for x in range(SPRITE_PX):
			var p := Vector2(x, y)
			var d := p.distance_to(Vector2(cx, cy + 4))
			if d < 14.0:
				img.set_pixel(x, y, base)
			elif d < 16.0:
				img.set_pixel(x, y, base.darkened(0.15))
	# Head / carapace
	for y in range(SPRITE_PX):
		for x in range(SPRITE_PX):
			if Vector2(x, y).distance_to(Vector2(cx, cy - 10)) < 9.0:
				img.set_pixel(x, y, base.lightened(0.12))
	# Facing accent (weapon / maw direction)
	var tip := Vector2(cx, cy)
	match facing:
		"north":
			tip += Vector2(0, -18)
		"south":
			tip += Vector2(0, 18)
		"east":
			tip += Vector2(18, 0)
		"west":
			tip += Vector2(-18, 0)
	for y in range(SPRITE_PX):
		for x in range(SPRITE_PX):
			if Vector2(x, y).distance_to(tip) < 5.0:
				img.set_pixel(x, y, base.lightened(0.25))
	if archetype == "heavy":
		for y in range(SPRITE_PX):
			for x in range(SPRITE_PX):
				if Vector2(x, y).distance_to(Vector2(cx, cy)) < 18.0:
					img.set_pixel(x, y, base)
	return img
