class_name BattleTerritoryReplayBake
extends RefCounted

const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")


## Build one display Image for a tape frame (fluid from pressure, else softened owners).
static func render_frame_image(tape: BattleTerritoryTapeLib, frame_index: int, battle_data) -> Image:
	if tape == null or battle_data == null or frame_index < 0 or frame_index >= tape.frame_count():
		return null
	var pressures: Dictionary = tape.pressures_at_frame(frame_index)
	var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
	var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
	if not pf.is_empty() and not ph.is_empty():
		return BattleTileFluidFieldLib.build_fluid_image_from_powers(
			battle_data, pf, ph, 1.0, 0
		)
	var owners: PackedByteArray = tape.owners_at_frame(frame_index)
	if owners.is_empty():
		return null
	return BattleTileFluidFieldLib.build_fluid_image(battle_data, owners, 1, 1.0)


static func bake_frame_rgba(tape: BattleTerritoryTapeLib, frame_index: int, battle_data) -> PackedByteArray:
	if tape == null or battle_data == null or frame_index < 0 or frame_index >= tape.frame_count():
		return PackedByteArray()
	var pressures: Dictionary = tape.pressures_at_frame(frame_index)
	var pf: PackedFloat32Array = pressures.get("f", PackedFloat32Array())
	var ph: PackedFloat32Array = pressures.get("h", PackedFloat32Array())
	if (
		BattleTerritoryRustBackendLib.extension_available()
		and not pf.is_empty()
		and not ph.is_empty()
	):
		var rgba: PackedByteArray = BattleTerritoryRustBackendLib.bake_fluid_rgba(
			battle_data, pf, ph, 1.0
		)
		if not rgba.is_empty():
			return rgba
	var img: Image = render_frame_image(tape, frame_index, battle_data)
	if img == null:
		return PackedByteArray()
	return img.get_data()


static func lerp_images(img_a: Image, img_b: Image, blend: float) -> Image:
	if img_a == null:
		return img_b
	if img_b == null:
		return img_a
	if img_a.get_size() != img_b.get_size():
		return img_b if blend >= 0.5 else img_a
	var t: float = clampf(blend, 0.0, 1.0)
	if t <= 0.001:
		return img_a
	if t >= 0.999:
		return img_b
	var out: Image = img_a.duplicate()
	var w: int = out.get_width()
	var h: int = out.get_height()
	for gy in range(h):
		for gx in range(w):
			var ca: Color = img_a.get_pixel(gx, gy)
			var cb: Color = img_b.get_pixel(gx, gy)
			out.set_pixel(gx, gy, ca.lerp(cb, t))
	return out
