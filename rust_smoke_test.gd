extends SceneTree

## Rust GDExtension smoke test.
## Run with:
##   godot --headless --path . -s res://rust_smoke_test.gd
##
## Or from the editor: attach to a node and press play, or call the static test.

func _init() -> void:
	print("=== Empire Territory Rust Smoke Test ===")
	_run()
	quit()


static func _run() -> void:
	if not ClassDB.class_exists("TerritorySim"):
		push_error("TerritorySim class not found. The Rust GDExtension is not loaded.")
		print("  - Make sure you built the crate (cargo build --release)")
		print("  - Copied the .dll into rust/empire_territory/bin/ with the exact name from empire_territory.gdextension")
		print("  - The .gdextension file is present next to the bin/ folder")
		print("  - Restarted Godot after placing the files")
		return

	print("OK  TerritorySim class is registered by the GDExtension.")

	var sim: RefCounted = ClassDB.instantiate("TerritorySim")
	if sim == null:
		push_error("Failed to instantiate TerritorySim")
		return

	print("OK  Instantiated TerritorySim: ", sim)

	var msg: String = sim.call("hello")
	print("OK  sim.hello() -> ", msg)

	var ver: String = sim.call("version")
	print("OK  sim.version() -> ", ver)

	for _i in range(4):
		sim.call("advance_round")
	print("OK  advance_round() x4 did not crash")

	var w: int = 8
	var h: int = 6
	var n: int = w * h
	var land := PackedByteArray()
	land.resize(n)
	land.fill(1)
	var pf := PackedFloat32Array()
	var ph := PackedFloat32Array()
	pf.resize(n)
	ph.resize(n)
	for i in range(n):
		pf[i] = 0.5 if i % 3 == 0 else 0.0
		ph[i] = 0.3 if i % 5 == 0 else 0.0
	var rgba: PackedByteArray = sim.call("bake_fluid_rgba", w, h, land, pf, ph, 1.0)
	if rgba.size() != n * 4:
		push_error("bake_fluid_rgba expected %d bytes, got %d" % [n * 4, rgba.size()])
		return
	print("OK  bake_fluid_rgba() -> %d bytes (%dx%d RGBA8)" % [rgba.size(), w, h])

	var encoded: PackedByteArray = sim.call("encode_pressure_v2", pf)
	var decoded: PackedFloat32Array = sim.call("decode_pressure_v2", encoded)
	if decoded.size() != pf.size():
		push_error("encode/decode pressure size mismatch")
		return
	print("OK  encode_pressure_v2 / decode_pressure_v2 round-trip (%d tiles)" % decoded.size())

	print("")
	print("=== Rust smoke test PASSED ===")
