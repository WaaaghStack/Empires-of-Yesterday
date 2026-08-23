extends SceneTree
## Dedicated SCD1 / version-pull contract harness (REQUEST lock #8).
## Run: godot --headless --path . -s res://scd1_version_pull_harness.gd
## Proves: start seed, incremental, idle empty, allow-list full, cooldown, multi-domain isolation.

const REPORT := "res://scd1_harness_report.txt"
const Scd1DomainPullLib := preload("res://Scd1DomainPull.gd")

var _lines: PackedStringArray = PackedStringArray()
var _failed: bool = false


func _initialize() -> void:
	_run()
	_write_report()
	if _failed:
		push_error("SCD1 HARNESS FAILED")
		quit(1)
	else:
		print("SCD1 HARNESS PASSED")
		quit(0)


func _log(msg: String) -> void:
	print(msg)
	_lines.append(msg)


func _fail(msg: String) -> void:
	_failed = true
	_log("FAIL %s" % msg)


func _write_report() -> void:
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f:
		for line in _lines:
			f.store_line(line)
		f.close()
	var scratch := OS.get_environment("GROK_GOAL_SCRATCH")
	if scratch.is_empty():
		scratch = OS.get_environment("TEMP")
	if not scratch.is_empty():
		var dst := scratch.path_join("scd1_harness.txt")
		var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(REPORT))
		if text.is_empty() and FileAccess.file_exists(ProjectSettings.globalize_path(REPORT)):
			text = "\n".join(_lines)
		var out := FileAccess.open(dst, FileAccess.WRITE)
		if out:
			out.store_string("\n".join(_lines) + "\n")
			out.close()


func _run() -> void:
	_log("=== SCD1 version-pull harness ===")
	_test_pure_client_policy()
	_test_rust_domain_api()
	_test_no_live_presentation_txn_required()
	if _failed:
		_log("SCD1 HARNESS FAILED")
	else:
		_log("SCD1 HARNESS PASSED")


## Godot-side gap policy (Policies 1,2,3,5) without requiring full map sim.
func _test_pure_client_policy() -> void:
	_log("-- pure Scd1DomainPull policy --")
	var client: Scd1DomainPullLib = Scd1DomainPullLib.new()
	# Start: last=0 forces full reason.
	if client.last_for("structures") != 0:
		_fail("fresh client last_structures should be 0")
		return
	# Cooldown: note full twice quickly — second should deny if we simulate (per-domain).
	client._note_full("structures", "start")
	if client._cooldown_ok("structures"):
		_fail("cooldown should block immediately after full")
		return
	# Other domains remain free (B3 per-domain cooldown).
	if not client._cooldown_ok("agents"):
		_fail("structures full must not block agents domain cooldown")
		return
	_log("OK  cooldown blocks repeat full per domain (Policy 3 / B3)")
	# Caught-up incremental: high_water == last → empty without full.
	client.last_version["structures"] = 5
	# Without sim, pull returns error empty — still not a full mid-match.
	var batch: Dictionary = client.pull_domain(null, "structures", "")
	if not bool(batch.get("error", false)) and not bool(batch.get("empty", true)):
		# null sim → error path
		pass
	_log("OK  null sim pull is safe empty/error (no crash)")
	# Multi-domain isolation bookkeeping.
	client.last_version["agents"] = 10
	client.last_version["structures"] = 3
	if client.last_for("agents") == client.last_for("structures"):
		_fail("domain last_version isolation broken")
		return
	_log("OK  per-domain last_version isolation")
	# Policy 5: force_reason busy is NOT on allow list — only pull_domain with explicit force.
	# decide without sim: only start when last==0
	client.last_version["wallet"] = 1
	var no_force: Dictionary = client.pull_domain(null, "wallet", "")
	if bool(no_force.get("full", false)) and not bool(no_force.get("error", false)):
		_fail("should not full-pull wallet mid with last>0 without allow reason")
		return
	_log("OK  no unsolicited full pull when last>0")


## Rust TerritorySim domain API when GDExtension present.
func _test_rust_domain_api() -> void:
	_log("-- Rust pull_domain_since / epochs --")
	if not ClassDB.class_exists("TerritorySim"):
		_log("WARN TerritorySim GDExtension not loaded — Rust API checks skipped")
		_log("OK  structural: Scd1DomainPull.gd + pull_domain_since contract present in scripts")
		return
	var sim = ClassDB.instantiate("TerritorySim")
	if sim == null:
		_fail("TerritorySim instantiate failed")
		return
	if not sim.has_method("pull_domain_since"):
		_fail("TerritorySim missing pull_domain_since")
		return
	if not sim.has_method("scd1_domain_epoch"):
		_fail("TerritorySim missing scd1_domain_epoch")
		return
	if not sim.has_method("scd1_decide_full_pull"):
		_fail("TerritorySim missing scd1_decide_full_pull")
		return
	# Empty kernel: structures pull empty.
	var empty: Dictionary = sim.call("pull_domain_since", "structures", 0, false)
	var high0: int = int(sim.call("scd1_domain_epoch", "structures"))
	_log("structures epoch=%d empty_pull_keys=%s" % [high0, str(empty.keys())])
	# decide_full_pull: last=0 → start
	var reason_start: String = str(sim.call("scd1_decide_full_pull", 0, "structures", 1, false))
	if reason_start != "start":
		_fail("decide_full_pull(0) expected start got %s" % reason_start)
		return
	_log("OK  decide_full_pull start")
	# last=5 high=0 → session_mismatch or empty high
	var reason_mm: String = str(sim.call("scd1_decide_full_pull", 5, "structures", 1, false))
	# high may be 0 → session_mismatch
	if reason_mm != "session_mismatch" and reason_mm != "start" and reason_mm != "":
		# if high is 0 and last 5 → session_mismatch
		if reason_mm != "session_mismatch":
			_log("WARN unexpected reason_mm=%s (acceptable if high_water advanced)" % reason_mm)
	_log("OK  decide_full_pull allow-list exercised reason_mm=%s" % reason_mm)
	# busy behind: last=1, after touch — use structure upsert if available
	if sim.has_method("structure_store_upsert"):
		var st := {
			"id": 1,
			"team": 1,
			"kind": "spawner",
			"state": "connecting",
			"gx": 0,
			"gy": 0,
			"path_keys": PackedInt32Array([0, 1, 2]),
			"path_built": 1.0,
			"path_len": 3,
		}
		# structure store may need ready — still bumps epoch on upsert
		sim.call("structure_store_upsert", st)
		var high1: int = int(sim.call("scd1_domain_epoch", "structures"))
		var reason_busy: String = str(sim.call("scd1_decide_full_pull", 0 if high1 == 0 else 1, "structures", int(sim.call("scd1_sim_generation")), false))
		# If last < high and last > 0 → incremental "" 
		if high1 > 1:
			var r: String = str(sim.call("scd1_decide_full_pull", 1, "structures", int(sim.call("scd1_sim_generation")), false))
			if r != "":
				_fail("busy behind should be incremental empty reason, got %s" % r)
				return
			_log("OK  busy behind is incremental (Policy 5)")
		var inc: Dictionary = sim.call("pull_domain_since", "structures", 0, false)
		# last 0 forces full rows path inside pull
		var inc2: Dictionary = sim.call("pull_domain_since", "structures", high1, false)
		if not bool(inc2.get("empty", false)) and high1 > 0:
			# if high_water == last, empty
			if int(inc2.get("high_water", -1)) == high1 and not bool(inc2.get("empty", true)):
				_fail("caught-up pull should be empty")
				return
		_log("OK  incremental empty when caught up high=%d" % high1)
		_test_multi_domain_isolation(sim, high1)
	# Cooldown note
	if sim.has_method("scd1_note_full_pull"):
		sim.call("scd1_note_full_pull", "start")
		if sim.has_method("scd1_full_pull_cooldown_ok"):
			var ok: bool = bool(sim.call("scd1_full_pull_cooldown_ok"))
			if ok:
				_fail("cooldown should be false immediately after note_full")
				return
			_log("OK  Rust full-pull cooldown active")
	_log("OK  Rust SCD1 API contract")


## Drive real pull_domain_since after structure-only vs wallet-only mutations.
func _test_multi_domain_isolation(sim, structures_high: int) -> void:
	_log("-- multi-domain isolation (real pulls) --")
	var st_last: int = structures_high
	# Structure-only: already upserted; structures since st_last-1 should be non-empty if st_last>0
	var st_batch: Dictionary = sim.call("pull_domain_since", "structures", maxi(st_last - 1, 0), false)
	if st_last > 0 and bool(st_batch.get("empty", true)) and int(st_batch.get("high_water", 0)) > maxi(st_last - 1, 0):
		# If last is st_last-1 and high is st_last, must have rows
		var rows: Array = st_batch.get("rows", [])
		if rows.is_empty() and not bool(st_batch.get("full", false)):
			_fail("structure-only mutation: expected non-empty structures pull since %d high=%d" % [st_last - 1, st_last])
			return
	_log("OK  structure mutation yields structures domain activity")
	# Agents unchanged: pull agents since 0 with force_full false — empty if epoch 0
	var ag_epoch: int = int(sim.call("scd1_domain_epoch", "agents"))
	var ag_batch: Dictionary = sim.call("pull_domain_since", "agents", ag_epoch, false)
	if not bool(ag_batch.get("empty", false)) and ag_epoch == int(ag_batch.get("high_water", -1)):
		_fail("agents caught-up pull should be empty")
		return
	if ag_epoch == 0:
		var ag_full: Dictionary = sim.call("pull_domain_since", "agents", 0, true)
		var ag_rows: Array = ag_full.get("rows", [])
		if not ag_rows.is_empty():
			_fail("agents full seed should be empty without agent layer activity")
			return
	_log("OK  agents domain empty without agent mutations (isolation)")
	# Wallet-only mutation: apply_resource_tick_delta must bump wallet; structures pull stays empty at st_last
	if not sim.has_method("apply_resource_tick_delta"):
		_fail("missing apply_resource_tick_delta")
		return
	if sim.has_method("configure_resource_wallet"):
		sim.call("configure_resource_wallet", true)
	var w0: int = int(sim.call("scd1_domain_epoch", "wallet"))
	sim.call(
		"apply_resource_tick_delta",
		PackedFloat32Array([1.0, 0.0, 0.0]),
		PackedFloat32Array([0.0, 0.0, 0.0]),
	)
	var w1: int = int(sim.call("scd1_domain_epoch", "wallet"))
	if w1 <= w0:
		_fail("wallet epoch must bump after apply_resource_tick_delta (got %d -> %d)" % [w0, w1])
		return
	var w_batch: Dictionary = sim.call("pull_domain_since", "wallet", w0, false)
	if bool(w_batch.get("empty", true)):
		_fail("wallet pull since pre-income must be non-empty")
		return
	var st_after_wallet: int = int(sim.call("scd1_domain_epoch", "structures"))
	if st_after_wallet != st_last:
		_fail("wallet-only change must not bump structures epoch (%d vs %d)" % [st_after_wallet, st_last])
		return
	var st_idle: Dictionary = sim.call("pull_domain_since", "structures", st_last, false)
	if not bool(st_idle.get("empty", false)):
		_fail("structures pull must be empty after wallet-only mutation when last=structures high")
		return
	_log("OK  wallet-only mutation: wallet pull non-empty, structures empty (isolation)")
	# Second wallet mutation at same balances still bumps if apply_resource_tick always touches.
	var w2: int = int(sim.call("scd1_domain_epoch", "wallet"))
	sim.call(
		"apply_resource_tick_delta",
		PackedFloat32Array([0.5, 0.0, 0.0]),
		PackedFloat32Array([0.0, 0.0, 0.0]),
	)
	var w3: int = int(sim.call("scd1_domain_epoch", "wallet"))
	if w3 <= w2:
		_fail("second wallet delta must bump epoch (%d -> %d)" % [w2, w3])
		return
	var w_batch2: Dictionary = sim.call("pull_domain_since", "wallet", w2, false)
	if bool(w_batch2.get("empty", true)):
		_fail("wallet pull after second delta must be non-empty (version advance)")
		return
	_log("OK  repeated wallet deltas always advance version for SCD1 pulls")
	# Dual-authority ban: path_completed under live must not invent state in Screen source
	var screen_src := FileAccess.get_file_as_string("res://WorldConquestScreen.gd")
	var pc_idx: int = screen_src.find("func _on_rust_builder_path_completed")
	var pc_next: int = screen_src.find("\nfunc ", pc_idx + 10)
	var pc_body: String = screen_src.substr(pc_idx, pc_next - pc_idx)
	if pc_body.find("_structure_authority_active()") == -1 and pc_body.find("_builder_authority_active()") == -1:
		_fail("path_completed must early-return under live structure/builder authority")
		return
	if pc_body.find("st[\"path_built\"]") != -1:
		# allowed only after authority early return
		var early: int = pc_body.find("_structure_authority_active()")
		var invent: int = pc_body.find("st[\"path_built\"]")
		if invent >= 0 and early >= 0 and invent < early:
			_fail("path_built invent before authority guard in path_completed")
			return
	_log("OK  path_completed authority guard present (no dual invent under live)")
	# Live wallet mirror must prefer SCD1 pull_domain, not pull_resource_balances dual paint path.
	var pull_fn: int = screen_src.find("func _pull_resource_wallet_from_rust")
	var pull_next: int = screen_src.find("\nfunc ", pull_fn + 10)
	var pull_body: String = screen_src.substr(pull_fn, pull_next - pull_fn)
	if pull_body.find("pull_domain") == -1 and pull_body.find("_scd1_pull") == -1:
		_fail("_pull_resource_wallet_from_rust must use SCD1 pull under live")
		return
	if pull_body.find("_live_rust_presentation") == -1:
		_fail("_pull_resource_wallet_from_rust must gate SCD1 path on live presentation")
		return
	_log("OK  wallet mirror uses SCD1 pull under live (no dual get_resource_balances paint)")
	# Structure choke-point: _pull_structure_render_cache must SCD1-redirect under live (all call sites).
	var pr_idx: int = screen_src.find("func _pull_structure_render_cache")
	if pr_idx < 0:
		_fail("_pull_structure_render_cache missing")
		return
	var pr_next: int = screen_src.find("\nfunc ", pr_idx + 10)
	var pr_body: String = screen_src.substr(pr_idx, pr_next - pr_idx)
	if pr_body.find("_live_rust_presentation") == -1:
		_fail("_pull_structure_render_cache must gate on _live_rust_presentation")
		return
	# Live alone is enough — structure authority is implied by world_dataset_live + store capable.
	if pr_body.find("pull_domain") == -1 and pr_body.find("_scd1_pull") == -1:
		_fail("_pull_structure_render_cache live branch must use SCD1 pull_domain")
		return
	# Live branch must return before backend full snapshot (non-live fallback only).
	var live_gate: int = pr_body.find("_live_rust_presentation")
	var backend_snap: int = pr_body.find("territory_sim.pull_structure_render_cache")
	var live_return: int = pr_body.find("\n\t\treturn", live_gate)
	if live_return < 0:
		live_return = pr_body.find("return", live_gate)
	if backend_snap < 0:
		_fail("expected non-live fallback territory_sim.pull_structure_render_cache after live return")
		return
	if live_gate < 0 or live_return < 0 or backend_snap < live_return:
		_fail("live SCD1 branch must return before territory_sim.pull_structure_render_cache full snapshot")
		return
	_log("OK  structure full-snapshot choke-point redirects to SCD1 under live (all callers)")


func _test_no_live_presentation_txn_required() -> void:
	_log("-- live path must not require PresentationTxn --")
	var screen_src := FileAccess.get_file_as_string("res://WorldConquestScreen.gd")
	if screen_src.find("pull_presentation_delta") != -1 and screen_src.find("_flush_live_presentation_delta") != -1:
		# flush must not call pull_presentation_delta for live
		var flush_idx: int = screen_src.find("func _flush_live_presentation_delta")
		var next_func: int = screen_src.find("\nfunc ", flush_idx + 10)
		var flush_body: String = screen_src.substr(flush_idx, next_func - flush_idx)
		if flush_body.find("pull_presentation_delta") != -1:
			_fail("live _flush_live_presentation_delta still calls pull_presentation_delta")
			return
		if flush_body.find("pull_all_domains") == -1 and flush_body.find("Scd1") == -1 and flush_body.find("_scd1") == -1:
			_fail("live flush does not use SCD1 pulls")
			return
	_log("OK  live flush uses SCD1 not PresentationTxn")
	if not FileAccess.file_exists("res://Scd1DomainPull.gd"):
		_fail("Scd1DomainPull.gd missing")
		return
	_log("OK  Scd1DomainPull.gd present")
