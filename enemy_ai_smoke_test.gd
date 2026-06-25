extends SceneTree

## Headless: EnemyStrategy planner selfcheck (fast, no full UI bootstrap).
## godot --headless --path . -s res://enemy_ai_smoke_test.gd

const EnemyStrategyLib := preload("res://EnemyStrategy.gd")


func _init() -> void:
	print("=== Enemy AI Smoke Test ===")
	var sc: Dictionary = EnemyStrategyLib.run_selfcheck()
	var detail: String = str(sc.get("detail", ""))
	if not bool(sc.get("ok", false)):
		push_error("enemy_ai_smoke_test: FAIL %s" % detail)
		quit(1)
		return
	print("enemy_ai_smoke_test: PASS (%s)" % detail)
	quit(0)
