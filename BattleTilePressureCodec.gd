class_name BattleTilePressureCodec
extends RefCounted

const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")

## Quantize per-tile pressure for tape/SQL (uint8 per cell).

const MAX_PRESSURE := 96.0
const MAX_PRESSURE_V2 := 10000.0


static func encode(pressure: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(pressure.size())
	for i in range(pressure.size()):
		var t: float = clampf(float(pressure[i]) / MAX_PRESSURE, 0.0, 1.0)
		out[i] = int(round(t * 255.0)) & 0xFF
	return out


static func encode_v2(pressure: PackedFloat32Array) -> PackedByteArray:
	if BattleTerritoryRustBackendLib.extension_available():
		var rust_out: PackedByteArray = BattleTerritoryRustBackendLib.encode_pressure_v2(
			pressure
		)
		if rust_out.size() == pressure.size():
			return rust_out
	var out := PackedByteArray()
	out.resize(pressure.size())
	var log_denom: float = log(1.0 + MAX_PRESSURE_V2)
	for i in range(pressure.size()):
		var p: float = maxf(0.0, float(pressure[i]))
		var t: float = clampf(log(1.0 + p) / log_denom, 0.0, 1.0)
		out[i] = int(round(t * 255.0)) & 0xFF
	return out


static func decode(blob: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if blob.is_empty():
		return out
	out.resize(blob.size())
	for i in range(blob.size()):
		out[i] = float(blob[i]) / 255.0 * MAX_PRESSURE
	return out


static func decode_v2(blob: PackedByteArray) -> PackedFloat32Array:
	if BattleTerritoryRustBackendLib.extension_available():
		var rust_out: PackedFloat32Array = BattleTerritoryRustBackendLib.decode_pressure_v2(blob)
		if rust_out.size() == blob.size():
			return rust_out
	var out := PackedFloat32Array()
	if blob.is_empty():
		return out
	out.resize(blob.size())
	var log_denom: float = log(1.0 + MAX_PRESSURE_V2)
	for i in range(blob.size()):
		var t: float = float(blob[i]) / 255.0
		out[i] = exp(t * log_denom) - 1.0
	return out


static func lerp_arrays(a: PackedFloat32Array, b: PackedFloat32Array, t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if a.is_empty() or b.is_empty():
		return b if not b.is_empty() else a
	var n: int = mini(a.size(), b.size())
	out.resize(n)
	var blend: float = clampf(t, 0.0, 1.0)
	for i in range(n):
		out[i] = lerpf(a[i], b[i], blend)
	return out
