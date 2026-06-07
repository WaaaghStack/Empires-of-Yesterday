class_name BattleReplayPack
extends RefCounted

## Territory replay blob: columnar layout, one SQLite read to load.
## Magic "EYTR" — v1 full owners per frame; v2 delta owners + log-scale pressure.

const MAGIC := "EYTR"
const VERSION_V1 := 1
const VERSION_V2 := 2
const FRAME_SECONDS := 0.5
const HEADER_SIZE := 24

const BattleTerritoryTapeLib := preload("res://BattleTerritoryTape.gd")
const BattleReplayTapeLib := preload("res://BattleReplayTape.gd")
const BattleTilePressureCodecLib := preload("res://BattleTilePressureCodec.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")


static func pack_tape(tape: BattleTerritoryTapeLib, grid_width: int, grid_height: int) -> PackedByteArray:
	if tape == null or tape.frame_count() == 0:
		return PackedByteArray()
	var cells: int = grid_width * grid_height
	if cells <= 0:
		return PackedByteArray()
	if BattleTerritoryRustBackendLib.extension_available():
		var rust_blob: PackedByteArray = _pack_tape_rust(tape, grid_width, grid_height, cells)
		if not rust_blob.is_empty():
			return rust_blob
	var body := PackedByteArray()
	for fi in range(tape.frame_count()):
		var frame: Dictionary = tape.get_frame(fi)
		var owners: PackedByteArray = tape.owners_at_frame(fi)
		if owners.size() != cells:
			owners.resize(cells)
		var is_full: bool = frame.has("tile_owners")
		var w := StreamPeerBuffer.new()
		w.put_u32(int(frame.get("round", fi)))
		w.put_u16(int(frame.get("friendly_tiles", 0)))
		w.put_u16(int(frame.get("hostile_tiles", 0)))
		w.put_u8(1 if is_full else 0)
		w.put_u8(int(frame.get("pressure_codec", 2)))
		w.put_u16(0)
		if is_full:
			w.put_data(owners)
		else:
			var delta = frame.get("owner_delta", PackedInt32Array())
			var n_delta: int = int(delta.size() / 2) if delta is PackedInt32Array else 0
			w.put_u16(n_delta)
			if delta is PackedInt32Array:
				for j in range(0, delta.size(), 2):
					if j + 1 >= delta.size():
						break
					w.put_u16(int(delta[j]))
					w.put_u8(int(delta[j + 1]) & 0xFF)
		var pf: PackedByteArray = frame.get("pressure_f", PackedByteArray())
		var ph: PackedByteArray = frame.get("pressure_h", PackedByteArray())
		if pf.is_empty() or pf.size() != cells:
			pf = _encode_pressure_from_floats(
				BattleTerritoryTapeLib.pressure_friendly_from_frame(frame), cells, 2
			)
		if ph.is_empty() or ph.size() != cells:
			ph = _encode_pressure_from_floats(
				BattleTerritoryTapeLib.pressure_hostile_from_frame(frame), cells, 2
			)
		w.put_data(pf)
		w.put_data(ph)
		body.append_array(w.data_array)
	var hdr := StreamPeerBuffer.new()
	hdr.put_data(MAGIC.to_utf8_buffer())
	hdr.put_u8(VERSION_V2)
	hdr.put_u8(0)
	hdr.put_u8(0)
	hdr.put_u8(0)
	hdr.put_u32(tape.frame_count())
	hdr.put_u16(grid_width)
	hdr.put_u16(grid_height)
	hdr.put_u16(maxi(1, tape.record_stride))
	hdr.put_u16(0)
	hdr.put_float(FRAME_SECONDS)
	var out := hdr.data_array
	out.append_array(body)
	return out


static func unpack_tape(blob: PackedByteArray) -> BattleTerritoryTapeLib:
	var tape := BattleTerritoryTapeLib.new()
	if blob.size() < HEADER_SIZE:
		return tape
	var magic := blob.slice(0, 4).get_string_from_ascii()
	if magic != MAGIC:
		return tape
	var version: int = int(blob[4])
	if version == VERSION_V1:
		return _unpack_v1(blob)
	if version == VERSION_V2:
		return _unpack_v2(blob)
	return tape


static func _unpack_v1(blob: PackedByteArray) -> BattleTerritoryTapeLib:
	var tape := BattleTerritoryTapeLib.new()
	var frame_count: int = int(blob.decode_u32(8))
	var grid_w: int = int(blob.decode_u16(12))
	var grid_h: int = int(blob.decode_u16(14))
	tape.record_stride = int(blob.decode_u16(16))
	tape.round_duration = blob.decode_float(20)
	var cells: int = grid_w * grid_h
	var frame_stride: int = 8 + cells * 3
	var expected: int = HEADER_SIZE + frame_count * frame_stride
	if blob.size() < expected or cells <= 0 or frame_count <= 0:
		return tape
	var off: int = HEADER_SIZE
	for _fi in range(frame_count):
		var round_i: int = int(blob.decode_u32(off))
		off += 4
		var friendly: int = int(blob.decode_u16(off))
		off += 2
		var hostile: int = int(blob.decode_u16(off))
		off += 2
		off += 2
		var owners: PackedByteArray = blob.slice(off, off + cells)
		off += cells
		var pf: PackedByteArray = blob.slice(off, off + cells)
		off += cells
		var ph: PackedByteArray = blob.slice(off, off + cells)
		off += cells
		tape.frames.append({
			"round": round_i,
			"friendly_tiles": friendly,
			"hostile_tiles": hostile,
			"tile_owners": owners,
			"pressure_f": pf,
			"pressure_h": ph,
		})
	tape.rebuild_segment_timing()
	if not tape.frames.is_empty():
		tape._owners_cache = tape.owners_at_frame(tape.frames.size() - 1)
	return tape


static func _unpack_v2(blob: PackedByteArray) -> BattleTerritoryTapeLib:
	var tape := BattleTerritoryTapeLib.new()
	var frame_count: int = int(blob.decode_u32(8))
	var grid_w: int = int(blob.decode_u16(12))
	var grid_h: int = int(blob.decode_u16(14))
	tape.record_stride = int(blob.decode_u16(16))
	tape.round_duration = blob.decode_float(20)
	var cells: int = grid_w * grid_h
	if cells <= 0 or frame_count <= 0:
		return tape
	var off: int = HEADER_SIZE
	var owners_full: PackedByteArray = PackedByteArray()
	owners_full.resize(cells)
	for _fi in range(frame_count):
		if off + 12 > blob.size():
			break
		var round_i: int = int(blob.decode_u32(off))
		off += 4
		var friendly: int = int(blob.decode_u16(off))
		off += 2
		var hostile: int = int(blob.decode_u16(off))
		off += 2
		var full_flag: int = int(blob[off])
		off += 1
		var codec: int = int(blob[off])
		off += 1
		off += 2
		var frame: Dictionary = {
			"round": round_i,
			"friendly_tiles": friendly,
			"hostile_tiles": hostile,
			"pressure_codec": codec,
		}
		if full_flag != 0:
			if off + cells > blob.size():
				break
			owners_full = blob.slice(off, off + cells)
			off += cells
			frame["tile_owners"] = owners_full
		else:
			if off + 2 > blob.size():
				break
			var n_delta: int = int(blob.decode_u16(off))
			off += 2
			var delta := PackedInt32Array()
			delta.resize(n_delta * 2)
			for d in range(n_delta):
				if off + 3 > blob.size():
					break
				var idx: int = int(blob.decode_u16(off))
				off += 2
				var owner_byte: int = int(blob[off])
				off += 1
				delta[d * 2] = idx
				delta[d * 2 + 1] = owner_byte
				if idx >= 0 and idx < cells:
					owners_full[idx] = owner_byte
			frame["owner_delta"] = delta
		if off + cells * 2 > blob.size():
			break
		frame["pressure_f"] = blob.slice(off, off + cells)
		off += cells
		frame["pressure_h"] = blob.slice(off, off + cells)
		off += cells
		tape.frames.append(frame)
	tape.rebuild_segment_timing()
	if not tape.frames.is_empty():
		tape._owners_cache = tape.owners_at_frame(tape.frames.size() - 1)
	return tape


static func _pack_tape_rust(
	tape: BattleTerritoryTapeLib,
	grid_width: int,
	grid_height: int,
	cells: int,
) -> PackedByteArray:
	var frame_count: int = tape.frame_count()
	var rounds := PackedInt32Array()
	var friendly := PackedInt32Array()
	var hostile := PackedInt32Array()
	var full_flags := PackedByteArray()
	var owner_blobs: Array = []
	var delta_blobs: Array = []
	var pf_blobs: Array = []
	var ph_blobs: Array = []
	rounds.resize(frame_count)
	friendly.resize(frame_count)
	hostile.resize(frame_count)
	full_flags.resize(frame_count)
	for fi in range(frame_count):
		var frame: Dictionary = tape.get_frame(fi)
		var owners: PackedByteArray = tape.owners_at_frame(fi)
		if owners.size() != cells:
			owners.resize(cells)
		var is_full: bool = frame.has("tile_owners")
		rounds[fi] = int(frame.get("round", fi))
		friendly[fi] = int(frame.get("friendly_tiles", 0))
		hostile[fi] = int(frame.get("hostile_tiles", 0))
		full_flags[fi] = 1 if is_full else 0
		if is_full:
			owner_blobs.append(owners)
			delta_blobs.append(PackedByteArray())
		else:
			owner_blobs.append(PackedByteArray())
			var delta = frame.get("owner_delta", PackedInt32Array())
			var packed_delta := PackedByteArray()
			if delta is PackedInt32Array:
				for j in range(0, delta.size(), 2):
					if j + 1 >= delta.size():
						break
					var idx: int = int(delta[j])
					var owner_byte: int = int(delta[j + 1]) & 0xFF
					packed_delta.append(idx & 0xFF)
					packed_delta.append((idx >> 8) & 0xFF)
					packed_delta.append(owner_byte)
			delta_blobs.append(packed_delta)
		var pf: PackedByteArray = frame.get("pressure_f", PackedByteArray())
		var ph: PackedByteArray = frame.get("pressure_h", PackedByteArray())
		if pf.is_empty() or pf.size() != cells:
			pf = _encode_pressure_from_floats(
				BattleTerritoryTapeLib.pressure_friendly_from_frame(frame), cells, 2
			)
		if ph.is_empty() or ph.size() != cells:
			ph = _encode_pressure_from_floats(
				BattleTerritoryTapeLib.pressure_hostile_from_frame(frame), cells, 2
			)
		pf_blobs.append(pf)
		ph_blobs.append(ph)
	var sim: RefCounted = ClassDB.instantiate("TerritorySim")
	return sim.call(
		"pack_territory_tape_from_dict",
		{
			"grid_w": grid_width,
			"grid_h": grid_height,
			"record_stride": maxi(1, tape.record_stride),
			"frame_count": frame_count,
			"frame_rounds": rounds,
			"frame_friendly": friendly,
			"frame_hostile": hostile,
			"frame_full_flags": full_flags,
			"frame_owner_blobs": owner_blobs,
			"frame_delta_blobs": delta_blobs,
			"frame_pressure_f": pf_blobs,
			"frame_pressure_h": ph_blobs,
		},
	)


static func _encode_pressure_from_floats(
	src: PackedFloat32Array,
	cells: int,
	codec: int = 1,
) -> PackedByteArray:
	if src.is_empty():
		var z := PackedByteArray()
		z.resize(cells)
		return z
	if src.size() != cells:
		var padded := PackedFloat32Array()
		padded.resize(cells)
		for i in range(mini(cells, src.size())):
			padded[i] = src[i]
		if codec >= 2:
			return BattleTilePressureCodecLib.encode_v2(padded)
		return BattleTilePressureCodecLib.encode(padded)
	if codec >= 2:
		return BattleTilePressureCodecLib.encode_v2(src)
	return BattleTilePressureCodecLib.encode(src)
