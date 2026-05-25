class_name BattlePhaseController
extends RefCounted

enum Phase { BRIEFING, DEPLOYMENT, APPROACH, ENGAGEMENT, RESOLUTION, FINISHED }

const BattleMapDataLib := preload("res://BattleMapData.gd")

var current_phase: Phase = Phase.BRIEFING
var phase_timer: float = 0.0
var waves_spawned: int = 0
var max_waves: int = 6
var briefing_skipped: bool = false
var contact_reached: bool = false
var resolution_timer: float = 0.0

const BRIEFING_DURATION := 2.5
const DEPLOYMENT_DURATION := 3.0
const APPROACH_MIN_DURATION := 6.0
const RESOLUTION_DURATION := 4.0
const WAVE_INTERVAL := 2.2


func reset() -> void:
	current_phase = Phase.BRIEFING
	phase_timer = 0.0
	waves_spawned = 0
	contact_reached = false
	resolution_timer = 0.0
	briefing_skipped = false


func skip_briefing() -> void:
	if current_phase == Phase.BRIEFING:
		briefing_skipped = true
		phase_timer = BRIEFING_DURATION


func tick(delta: float, battle_data, store: UnitSimulationStore) -> void:
	if current_phase == Phase.FINISHED:
		return
	phase_timer += delta
	match current_phase:
		Phase.BRIEFING:
			if phase_timer >= BRIEFING_DURATION or briefing_skipped:
				current_phase = Phase.DEPLOYMENT
				phase_timer = 0.0
		Phase.DEPLOYMENT:
			if phase_timer >= DEPLOYMENT_DURATION:
				current_phase = Phase.APPROACH
				phase_timer = 0.0
		Phase.APPROACH:
			_check_contact(battle_data, store)
			if contact_reached and phase_timer >= APPROACH_MIN_DURATION:
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
		Phase.DEPLOYMENT:
			return "Deployment"
		Phase.APPROACH:
			return "Approach"
		Phase.ENGAGEMENT:
			return "Engagement"
		Phase.RESOLUTION:
			return "Resolution"
		_:
			return "Complete"


func can_spawn_wave() -> bool:
	return current_phase in [Phase.DEPLOYMENT, Phase.APPROACH, Phase.ENGAGEMENT] and waves_spawned < max_waves


func mark_wave_spawned() -> void:
	waves_spawned += 1


func should_tick_sector_combat() -> bool:
	return current_phase in [Phase.ENGAGEMENT, Phase.RESOLUTION]


func approach_active() -> bool:
	return current_phase == Phase.APPROACH


func advance_active() -> bool:
	return current_phase in [Phase.DEPLOYMENT, Phase.APPROACH, Phase.ENGAGEMENT, Phase.RESOLUTION]


func _check_contact(battle_data, store: UnitSimulationStore) -> void:
	if battle_data == null or store == null:
		return
	var contact_x: float = (float(battle_data.contact_column) + 0.5) * battle_data.cell_size - battle_data.map_size.x * 0.5
	var band: float = battle_data.cell_size * 3.0
	var friendly_at := 0
	var hostile_at := 0
	var friendly_alive := 0
	var hostile_alive := 0
	for i in range(store.count):
		if not store.is_alive(i):
			continue
		if store.side[i] == UnitSimulationStore.Side.FRIENDLY:
			friendly_alive += 1
			if store.positions[i].x >= contact_x - band:
				friendly_at += 1
		else:
			hostile_alive += 1
			if store.positions[i].x <= contact_x + band:
				hostile_at += 1
	var friendly_ratio: float = float(friendly_at) / maxf(1.0, float(friendly_alive))
	var hostile_ratio: float = float(hostile_at) / maxf(1.0, float(hostile_alive))
	contact_reached = (
		friendly_at >= 60
		and hostile_at >= 60
	) or (
		friendly_ratio >= 0.18
		and hostile_ratio >= 0.18
		and friendly_at >= 30
		and hostile_at >= 30
	)
