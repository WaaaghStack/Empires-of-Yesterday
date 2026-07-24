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
## Per-domain last full-pull time (msec). Avoids one domain's full resync starving others (B3).
var _last_full_pull_msec_by_domain: Dictionary = {}
var _seeded: bool = false


func reset_for_new_match() -> void:
	last_version.clear()
	for d in DOMAINS:
		last_version[d] = 0
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

	# Mid-life sim_generation advance: rewind stale last_version so allow-list recovery works (B2).
	if server_gen > 0 and client_sim_generation > 0 and server_gen != client_sim_generation:
		last_version[domain] = 0
		last = 0

	var reason: String = force_reason
	if reason.is_empty() and sim.has_method("scd1_decide_full_pull"):
		reason = str(sim.call("scd1_decide_full_pull", last, domain, client_sim_generation, false))

	var want_full: bool = not reason.is_empty()
	if want_full:
		# Policy 3: per-domain cooldown (start always allowed). Allow-listed recovery
		# (sim_reset / session_mismatch) still gated per domain, not globally (B3).
		if reason != "start" and not _cooldown_ok(domain):
			return {
				"empty": true,
				"full_denied_cooldown": true,
				"reason": reason,
				"domain": domain,
				"high_water": high,
			}
		if reason == "start" or last == 0:
			reason = "start"
		_note_full(domain, reason)
		if sim.has_method("scd1_note_full_pull"):
			sim.call("scd1_note_full_pull", reason)
		var full_batch: Dictionary = sim.call("pull_domain_since", domain, 0, true)
		_apply_high_water(domain, full_batch, true)
		if server_gen > 0:
			client_sim_generation = server_gen
		_seeded = true
		return full_batch

	# Policy 1 / 5: incremental only (catch-up if behind).
	var batch: Dictionary = sim.call("pull_domain_since", domain, last, false)
	_apply_high_water(domain, batch, false)
	if server_gen > 0:
		client_sim_generation = int(batch.get("sim_generation", server_gen))
	return batch


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
