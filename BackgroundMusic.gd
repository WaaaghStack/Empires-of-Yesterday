extends Node
## Plays looping background music from res://assets/music/ (mp3, ogg, wav).

const MUSIC_DIR := "res://assets/music/"
const MUSIC_EXTENSIONS: PackedStringArray = ["mp3", "ogg", "wav"]

const DEFAULT_VOLUME_DB := -12.0

var _tracks: Array[String] = []
var _track_index: int = 0
var _player: AudioStreamPlayer
var _enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	_player.volume_db = DEFAULT_VOLUME_DB
	add_child(_player)
	_player.finished.connect(_on_track_finished)
	_reload_tracks()
	if not _tracks.is_empty():
		_play_track(_track_index)


func _reload_tracks() -> void:
	_tracks.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		push_warning("BackgroundMusic: cannot open %s" % MUSIC_DIR)
		return
	for file_name in dir.get_files():
		if _is_music_file(file_name):
			_tracks.append(MUSIC_DIR + file_name)
	_tracks.sort()


func _is_music_file(file_name: String) -> bool:
	var ext := file_name.get_extension().to_lower()
	return ext in MUSIC_EXTENSIONS


func _play_track(index: int) -> void:
	if _tracks.is_empty() or not _enabled:
		return
	_track_index = posmod(index, _tracks.size())
	var stream: AudioStream = load(_tracks[_track_index]) as AudioStream
	if stream == null:
		push_warning("BackgroundMusic: failed to load %s" % _tracks[_track_index])
		return
	_apply_loop(stream)
	_player.stream = stream
	_player.play()


func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop = true


func _on_track_finished() -> void:
	if _tracks.size() <= 1:
		return
	_play_track(_track_index + 1)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not _enabled:
		_player.stop()
	elif not _player.playing and not _tracks.is_empty():
		_play_track(_track_index)


func set_volume_db(volume_db: float) -> void:
	_player.volume_db = volume_db


func refresh_and_play() -> void:
	_reload_tracks()
	if _tracks.is_empty():
		_player.stop()
		return
	_track_index = 0
	_play_track(0)
