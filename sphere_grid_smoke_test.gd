extends SceneTree

## Headless equal-area sphere grid smoke.
## godot --headless --path . -s res://sphere_grid_smoke_test.gd

const SphereGridLib := preload("res://SphereGridLib.gd")


func _init() -> void:
	print("=== Sphere Grid Smoke Test ===")
	var ok: bool = _run()
	if ok:
		print("PASS sphere grid smoke")
	else:
		push_error("FAIL sphere grid smoke")
	quit(0 if ok else 1)


func _run() -> bool:
	var cases: Array[Dictionary] = [
		{"f": 1, "expect": 12},
		{"f": 2, "expect": 42},
		{"f": 8, "expect": 642},
	]
	for c in cases:
		var f: int = int(c.f)
		var expect: int = int(c.expect)
		var grid: Dictionary = SphereGridLib.generate(f)
		var n: int = int(grid.get("cell_count", 0))
		if n != expect:
			push_error("SphereGridLib f=%d cell_count %d != %d" % [f, n, expect])
			return false
		var neighbor_counts: PackedByteArray = grid.get("neighbor_count", PackedByteArray())
		if neighbor_counts.size() != n:
			push_error(
				"SphereGridLib f=%d neighbor_count size %d != cell_count %d"
				% [f, neighbor_counts.size(), n]
			)
			return false
		for i in range(n):
			var deg: int = int(neighbor_counts[i])
			if deg < 5 or deg > 6:
				push_error("SphereGridLib f=%d cell %d degree %d (expected 5-6)" % [f, i, deg])
				return false
		print("OK  SphereGridLib f=%d cells=%d neighbors=5-6" % [f, n])
	if ClassDB.class_exists("TerritorySim"):
		var sim = ClassDB.instantiate("TerritorySim")
		if sim != null and sim.has_method("generate_sphere_grid"):
			for c in cases:
				var f: int = int(c.f)
				var expect: int = int(c.expect)
				var rust: Dictionary = sim.generate_sphere_grid(f)
				var rust_n: int = int(rust.get("cell_count", 0))
				if rust_n != expect:
					push_error(
						"TerritorySim f=%d cell_count %d != GDScript %d"
						% [f, rust_n, expect]
					)
					return false
				print("OK  TerritorySim f=%d cell_count=%d matches GDScript" % [f, rust_n])
	return true
