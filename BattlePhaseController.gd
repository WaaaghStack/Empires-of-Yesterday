class_name BattlePhaseController
extends RefCounted

enum Phase { BRIEFING, ENGAGEMENT, RESOLUTION, FINISHED }

const BattleMapDataLib := preload("res://BattleMapData.gd")

var current_phase: Phase = Phase.BRIEFING
var phase_timer: float = 0.0
var briefing_skipped: bool = false
var resolution_timer: float = 0.0

const BRIEFING_DURATION := 2.5
const RESOLUTION_DURATION := 3.0


func reset() -> void:
	current_phase = Phase.BRIEFING
	phase_timer = 0.0
	resolution_timer = 0.0
	briefing_skipped = false


func skip_briefing() -> void:
	if current_phase == Phase.BRIEFING:
		briefing_skipped = true
		phase_timer = BRIEFING_DURATION


func tick(delta: float, _battle_data = null, _store = null) -> void:
	if current_phase == Phase.FINISHED:
		return
	phase_timer += delta
	match current_phase:
		Phase.BRIEFING:
			if phase_timer >= BRIEFING_DURATION or briefing_skipped:
				current_phase = Phase.ENGAGEMENT
				phase_timer = 0.0
		Phase.ENGAGEMENT:
			pass
		Phase.RESOLUTION:
			resolution_timer += delta
			if resolution_timer >= RESOLUTION_DURATION:
				current_phase = Phase.FINISHED


func begin_resolution() -> void:
	if current_phase == Phase.ENGAGEMENT:
		current_phase = Phase.RESOLUTION
		resolution_timer = 0.0


func phase_name() -> String:
	match current_phase:
		Phase.BRIEFING:
			return "Briefing"
		Phase.ENGAGEMENT:
			return "Engagement"
		Phase.RESOLUTION:
			return "Resolution"
		_:
			return "Complete"


func turns_active() -> bool:
	return current_phase in [Phase.ENGAGEMENT, Phase.RESOLUTION]
