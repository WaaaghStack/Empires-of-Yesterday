extends SceneTree

## Headless smoke for the proposed two-worlds transaction engine (eon_engine via GDExtension).
## Verifies the TwoWorldsEngine class is registered, deterministic, and reconciles.
## godot --headless --path . -s res://two_worlds_smoke_test.gd

func _init() -> void:
	print("=== Two Worlds Engine Smoke ===")
	if not ClassDB.class_exists("TwoWorldsEngine"):
		push_error("FAIL TwoWorldsEngine class not registered (rebuild the Rust DLL)")
		quit()
		return
	var engine = ClassDB.instantiate("TwoWorldsEngine")
	var verdict := String(engine.self_check())
	print(verdict)
	var ok := verdict.contains("deterministic=true") and verdict.contains("reconciled=true")
	print("--- campaign summary (seed 2026) ---")
	print(String(engine.run_campaign_summary(2026, 60)))
	if ok:
		print("PASS two_worlds smoke")
	else:
		push_error("FAIL two_worlds smoke (determinism/reconcile)")
	quit()
