class_name Scd1DomainPull
extends RefCounted
## SCD1 versioned domain pulls for live World Conquest.
## Spec: docs/REQUEST_SCD1_VERSIONED_PULL.md — Policies 1,2,3,5,6,7.

const DOMAINS: Array[String] = [
	"territory",
	"structures",
	# R1: "roads" domain retired from live pull (Rust slot may remain for ABI).
	"agents",
	"bombers",
	"wallet",
]

const FULL_PULL_COOLDOWN_SEC := 3.0

## last_version per domain (monotonic high-water applied).
var last_version: Dictionary = {}
var client_sim_generation: int = 0
## Per-domain last full-pull time (msec). Avoids one domain's full resync starving others (B3).
var _last_full_pull_msec_by_domain: Dictionary = {}
## Per-domain: first full seed completed this match. Prevents Start spam when epoch stays 0.
var _domain_seeded: Dictionary = {}
var _seeded: bool = false


func reset_for_new_match() -> void:
	last_version.clear()
	_domain_seeded.clear()
	for d in DOMAINS:
		last_version[d] = 0
		_domain_seeded[d] = false
	client_sim_generation = 0
	_seeded = false
	_last_full_pull_msec_by_domain.clear()


func _init() -> void:
	reset_for_new_match()


func _cooldown_ok(domain: String) -> bool:
	if not _last_full_pull_msec_by_domain.has(domain):
		return true
	var last_ms: int = int(_last_full_pull_msec_by_domain[domain])
	var elapsed_ms: int = Time.get_ticks_msec() - last_ms
	return elapsed_ms >= int(FULL_PULL_COOLDOWN_SEC * 1000.0)


func _note_full(domain: String, reason: String) -> void:
	_last_full_pull_msec_by_domain[domain] = Time.get_ticks_msec()
	# Policy 6: always log; avoid hard dependency on RunLog autoload (harness -s mode).
	print("FULL_RESYNC domain=%s reason=%s cooldown_secs=%.0f" % [domain, reason, FULL_PULL_COOLDOWN_SEC])


func _empty_batch(domain: String, high: int, server_gen: int) -> Dictionary:
	return {
		"empty": true,
		"full": false,
		"domain": domain,
		"high_water": high,
		"sim_generation": server_gen,
	}


## Pull one domain. force_reason non-empty forces full if cooldown allows (Policy 2/3).
func pull_domain(sim, domain: String, force_reason: String = "") -> Dictionary:
	if sim == null or not sim.has_method("pull_domain_since"):
		return {"empty": true, "error": true, "domain": domain}
	var last: int = int(last_version.get(domain, 0))
	var high: int = 0
	if sim.has_method("scd1_domain_epoch"):
		high = int(sim.call("scd1_domain_epoch", domain))
	var server_gen: int = 0
	if sim.has_method("scd1_sim_generation"):
		server_gen = int(sim.call("scd1_sim_generation"))
	var domain_seeded: bool = bool(_domain_seeded.get(domain, false))

	# Mid-life sim_generation advance: rewind stale last_version so allow-list recovery works (B2).
	if server_gen > 0 and client_sim_generation > 0 and server_gen != client_sim_generation:
		last_version[domain] = 0
		last = 0
		domain_seeded = false
		_domain_seeded[domain] = false

	# Quiet empty domain: already seeded this match, still no writes (epoch 0).
	# Without this, decide_full_pull(last=0) → "start" every frame and Start bypasses cooldown
	# → FULL_RESYNC spam (structures/agents/bombers/wallet before first write).
	if (
		domain_seeded
		and last == 0
		and high == 0
		and force_reason.is_empty()
	):
		return _empty_batch(domain, high, server_gen)

	# Caught up: skip pull_domain_since FFI (epoch already known).
	if force_reason.is_empty() and last > 0 and high > 0 and last >= high:
		return _empty_batch(domain, high, server_gen)

	var reason: String = force_reason
	if reason.is_empty() and sim.has_method("scd1_decide_full_pull"):
		reason = str(sim.call("scd1_decide_full_pull", last, domain, client_sim_generation, false))

	# After an empty seed (last stays 0), Rust decide_full_pull(last=0) returns "start" again
	# when the first real write bumps high>0. That would FULL_RESYNC on every first place —
	# wrong. Incremental from 0 is the correct catch-up.
	if reason == "start" and domain_seeded and force_reason.is_empty():
		reason = ""

	var want_full: bool = not reason.is_empty()
	if want_full:
		# Policy 3: per-domain cooldown. First Start of a domain is allowed once;
		# repeat Start / recovery reasons must respect cooldown (no Start bypass loop).
		var first_start: bool = reason == "start" and not domain_seeded
		if not first_start and not _cooldown_ok(domain):
			return {
				"empty": true,
				"full_denied_cooldown": true,
				"reason": reason,
				"domain": domain,
				"high_water": high,
			}
		_note_full(domain, reason)
		if sim.has_method("scd1_note_full_pull"):
			sim.call("scd1_note_full_pull", reason)
		var full_batch: Dictionary = sim.call("pull_domain_since", domain, 0, true)
		_apply_high_water(domain, full_batch, true)
		if server_gen > 0:
			client_sim_generation = server_gen
		_domain_seeded[domain] = true
		_seeded = true
		_trace_pull(domain, reason if not reason.is_empty() else "full", full_batch)
		return full_batch

	# Policy 1 / 5: incremental only (catch-up if behind).
	var batch: Dictionary = sim.call("pull_domain_since", domain, last, false)
	_apply_high_water(domain, batch, false)
	if server_gen > 0:
		client_sim_generation = int(batch.get("sim_generation", server_gen))
	_trace_pull(domain, "incr", batch)
	return batch


func _trace_pull(domain: String, reason: String, batch: Dictionary) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var trace: Node = tree.root.get_node_or_null("ActivityTrace")
	if trace == null or not trace.has_method("txn"):
		return
	var stats: Dictionary = _batch_stats(domain, batch)
	stats["reason"] = reason
	# Skip no-op incrementals (rows=0) — wallet epoch can tick every frame without row payload.
	if (
		reason == "incr"
		and int(stats.get("rows", 0)) == 0
		and int(stats.get("removed", 0)) == 0
		and int(stats.get("denied_cd", 0)) == 0
	):
		return
	trace.call("txn", "scd1_pull", stats)


func _batch_stats(domain: String, batch: Dictionary) -> Dictionary:
	var rows: int = 0
	if batch.has("rows") and batch.get("rows") is Array:
		rows = (batch.get("rows") as Array).size()
	elif batch.has("indices") and batch.get("indices") is PackedInt32Array:
		rows = (batch.get("indices") as PackedInt32Array).size()
	elif batch.has("display_indices") and batch.get("display_indices") is PackedInt32Array:
		rows = (batch.get("display_indices") as PackedInt32Array).size()
	var removed: int = 0
	if batch.has("removed_ids") and batch.get("removed_ids") is PackedInt32Array:
		removed = (batch.get("removed_ids") as PackedInt32Array).size()
	return {
		"domain": domain,
		"mode": "full" if bool(batch.get("full", false)) else "incr",
		"empty": 1 if bool(batch.get("empty", false)) else 0,
		"rows": rows,
		"removed": removed,
		"high_water": int(batch.get("high_water", 0)),
		"denied_cd": 1 if bool(batch.get("full_denied_cooldown", false)) else 0,
	}


func _apply_high_water(domain: String, batch: Dictionary, is_full: bool = false) -> void:
	if batch.is_empty() or bool(batch.get("error", false)):
		return
	var hw: int = int(batch.get("high_water", last_version.get(domain, 0)))
	var prev: int = int(last_version.get(domain, 0))
	# Full seed / reset: always adopt server high-water (may rewind after epoch zero) (B2).
	if is_full or bool(batch.get("full", false)):
		last_version[domain] = hw
		return
	# Session mismatch recovery without full flag: never stay ahead of server.
	if hw < prev:
		last_version[domain] = hw
		return
	if hw > prev:
		last_version[domain] = hw


## Pull all domains once (per-frame cadence). Returns map domain -> batch.
func pull_all_domains(sim) -> Dictionary:
	var out: Dictionary = {}
	for d in DOMAINS:
		out[d] = pull_domain(sim, d, "")
	return out


## True if structures batch would be empty given only agents changed (isolation helper for harness).
func last_for(domain: String) -> int:
	return int(last_version.get(domain, 0))
