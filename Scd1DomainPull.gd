class_name Scd1DomainPull
extends RefCounted
## SCD1 versioned domain pulls for live World Conquest.
## Spec: docs/REQUEST_SCD1_VERSIONED_PULL.md — Policies 1,2,3,5,6,7.

const DOMAINS: Array[String] = [
	"territory",
	"structures",
	"roads",
	"agents",
	"bombers",
	"wallet",
]

const FULL_PULL_COOLDOWN_SEC := 3.0

## last_version per domain (monotonic high-water applied).
var last_version: Dictionary = {}
var client_sim_generation: int = 0
var _last_full_pull_msec: int = -1
var _seeded: bool = false


func reset_for_new_match() -> void:
	last_version.clear()
	for d in DOMAINS:
		last_version[d] = 0
	client_sim_generation = 0
	_seeded = false
	_last_full_pull_msec = -1


func _init() -> void:
	reset_for_new_match()


func _cooldown_ok() -> bool:
	if _last_full_pull_msec < 0:
		return true
	var elapsed_ms: int = Time.get_ticks_msec() - _last_full_pull_msec
	return elapsed_ms >= int(FULL_PULL_COOLDOWN_SEC * 1000.0)


func _note_full(reason: String) -> void:
	_last_full_pull_msec = Time.get_ticks_msec()
	# Policy 6: always log; avoid hard dependency on RunLog autoload (harness -s mode).
	print("FULL_RESYNC reason=%s cooldown_secs=%.0f" % [reason, FULL_PULL_COOLDOWN_SEC])


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

	var reason: String = force_reason
	if reason.is_empty() and sim.has_method("scd1_decide_full_pull"):
		reason = str(sim.call("scd1_decide_full_pull", last, domain, client_sim_generation, false))

	var want_full: bool = not reason.is_empty()
	if want_full:
		# Policy 3: cooldown (start always allowed).
		if reason != "start" and not _cooldown_ok():
			return {
				"empty": true,
				"full_denied_cooldown": true,
				"reason": reason,
				"domain": domain,
				"high_water": high,
			}
		if reason == "start" or last == 0:
			reason = "start"
		_note_full(reason)
		if sim.has_method("scd1_note_full_pull"):
			sim.call("scd1_note_full_pull", reason)
		var full_batch: Dictionary = sim.call("pull_domain_since", domain, 0, true)
		_apply_high_water(domain, full_batch)
		if server_gen > 0:
			client_sim_generation = server_gen
		_seeded = true
		return full_batch

	# Policy 1 / 5: incremental only (catch-up if behind).
	var batch: Dictionary = sim.call("pull_domain_since", domain, last, false)
	_apply_high_water(domain, batch)
	if server_gen > 0:
		client_sim_generation = int(batch.get("sim_generation", server_gen))
	return batch


func _apply_high_water(domain: String, batch: Dictionary) -> void:
	if batch.is_empty() or bool(batch.get("error", false)):
		return
	var hw: int = int(batch.get("high_water", last_version.get(domain, 0)))
	if hw > int(last_version.get(domain, 0)):
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
