class_name CombatAudio
extends RefCounted

static var _shot_stream: AudioStreamWAV
static var _impact_stream: AudioStreamWAV
static var _death_stream: AudioStreamWAV
static var _order_stream: AudioStreamWAV
static var _secured_stream: AudioStreamWAV
static var _extract_stream: AudioStreamWAV
static var _extract_tick_stream: AudioStreamWAV
static var _extract_complete_stream: AudioStreamWAV
static var _ui_stream: AudioStreamWAV
static var _threat_stream: AudioStreamWAV
static var _contact_stream: AudioStreamWAV

static func play_shot(_at_node: Node2D) -> void:
	_play(_at_node, _get_shot(), -4.0, 0.94, 1.08)

static func play_impact(_at_node: Node2D) -> void:
	_play(_at_node, _get_impact(), -6.0, 0.9, 1.12)

static func play_death(_at_node: Node2D) -> void:
	_play(_at_node, _get_death(), -2.0, 0.88, 1.02)

static func play_order_issued(host: Node = null) -> void:
	_play(host, _get_order(), -8.0, 0.95, 1.05)

static func play_room_secured(host: Node = null) -> void:
	_play(host, _get_secured(), -6.0, 0.92, 1.08)

static func play_extract_channel(host: Node = null) -> void:
	_play(host, _get_extract(), -5.0, 0.9, 1.0)

static func play_extract_countdown_tick(host: Node = null) -> void:
	_play(host, _get_extract_tick(), -9.0, 0.92, 1.08)

static func play_extract_complete(host: Node = null) -> void:
	_play(host, _get_extract_complete(), -4.0, 0.95, 1.02)

static func play_ui_click(host: Node = null) -> void:
	_play(host, _get_ui(), -10.0, 0.98, 1.02)

static func play_threat_ping(host: Node = null) -> void:
	_play(host, _get_threat(), -3.0, 0.82, 0.95)

static func play_contact_ping(host: Node = null) -> void:
	_play(host, _get_contact(), -5.0, 0.9, 1.05)

static func _play(from_node: Node, stream: AudioStream, volume_db: float, pitch_min: float, pitch_max: float) -> void:
	if stream == null:
		return
	var host := _audio_host(from_node)
	if not host:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.bus = &"Master"
	host.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

static func _audio_host(from_node: Node) -> Node:
	if from_node and from_node.is_inside_tree():
		return from_node
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene:
		return tree.current_scene
	return null

static func _get_shot() -> AudioStreamWAV:
	if _shot_stream == null:
		_shot_stream = _make_burst(0.07, 880.0, 0.72, 0.42)
	return _shot_stream

static func _get_impact() -> AudioStreamWAV:
	if _impact_stream == null:
		_impact_stream = _make_burst(0.09, 240.0, 0.58, 0.55)
	return _impact_stream

static func _get_death() -> AudioStreamWAV:
	if _death_stream == null:
		_death_stream = _make_burst(0.36, 120.0, 0.78, 0.32, true)
	return _death_stream

static func _get_order() -> AudioStreamWAV:
	if _order_stream == null:
		_order_stream = _make_burst(0.05, 520.0, 0.45, 0.2)
	return _order_stream

static func _get_secured() -> AudioStreamWAV:
	if _secured_stream == null:
		_secured_stream = _make_burst(0.12, 340.0, 0.55, 0.25)
	return _secured_stream

static func _get_extract() -> AudioStreamWAV:
	if _extract_stream == null:
		_extract_stream = _make_burst(0.18, 180.0, 0.5, 0.35, true)
	return _extract_stream

static func _get_extract_tick() -> AudioStreamWAV:
	if _extract_tick_stream == null:
		_extract_tick_stream = _make_burst(0.04, 260.0, 0.38, 0.12)
	return _extract_tick_stream

static func _get_extract_complete() -> AudioStreamWAV:
	if _extract_complete_stream == null:
		_extract_complete_stream = _make_burst(0.22, 320.0, 0.62, 0.28, true)
	return _extract_complete_stream

static func _get_ui() -> AudioStreamWAV:
	if _ui_stream == null:
		_ui_stream = _make_burst(0.03, 640.0, 0.35, 0.15)
	return _ui_stream

static func _get_threat() -> AudioStreamWAV:
	if _threat_stream == null:
		_threat_stream = _make_burst(0.28, 160.0, 0.72, 0.62, true)
	return _threat_stream

static func _get_contact() -> AudioStreamWAV:
	if _contact_stream == null:
		_contact_stream = _make_burst(0.14, 420.0, 0.52, 0.38)
	return _contact_stream

static func _make_burst(duration: float, freq: float, volume: float, noise_mix: float, falloff: bool = false) -> AudioStreamWAV:
	var sample_rate := 22050
	var frame_count: int = maxi(int(duration * float(sample_rate)), 1)
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for i in range(frame_count):
		var t: float = float(i) / float(sample_rate)
		var progress: float = float(i) / float(frame_count)
		var envelope: float = 1.0 - progress
		if falloff:
			envelope = envelope * envelope
		var tone: float = sin(TAU * freq * t) * envelope * volume
		var noise: float = (randf() * 2.0 - 1.0) * envelope * noise_mix
		var sample: int = int(clampf((tone + noise) * 32767.0, -32768.0, 32767.0))
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream
