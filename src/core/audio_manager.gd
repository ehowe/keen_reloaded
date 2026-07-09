extends Node
## Global audio bus: music + SFX. Owns players that survive scene swaps.
## SFX registry maps name -> preloaded AudioStream (keyed by sfx/ filename).
## Gameplay calls play_sfx(name) directly at the event source.
##
## NOTE: Godot 4.7 has no AudioStreamPlayerPolyphonic node class and
## AudioStreamPlayer has no play_stream() method (that API was removed vs
## earlier 4.x). Polyphony is achieved with a round-robin voice pool of
## MAX_POLYPHONY AudioStreamPlayer nodes.

const SFX_DIR := "res://assets/audio/sfx/"
const MAX_POLYPHONY := 8
const MUSIC_THEME := preload("res://assets/audio/music/menu.wav")

var _sfx: Dictionary = {}  # name -> AudioStream
var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0


func _ready() -> void:
	_build_players()
	_load_sfx_registry()


## Play a sound by registry name. Unknown names are a no-op + push_warning.
## Uses a round-robin voice pool so overlapping calls each get their own
## player up to MAX_POLYPHONY (non-cutting).
func play_sfx(name: String) -> void:
	var stream: AudioStream = _sfx.get(name, null)
	if stream == null:
		push_warning("AudioManager: unknown sfx '%s'" % name)
		return
	var voice: AudioStreamPlayer = _sfx_pool[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % MAX_POLYPHONY
	voice.stream = stream
	voice.play()


## Play a looping music stream. null stops current music (silence).
func play_music(stream: AudioStream) -> void:
	if stream == null:
		stop_music()
		return
	# Ensure WAV streams loop (import flags reset on reimport; set at runtime).
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


## Stops music. Active short SFX voices (<1s) play out by design.
func stop_all() -> void:
	stop_music()


## Test/extension seam: register a stream at runtime (overrides on conflict).
func register_sfx(name: String, stream: AudioStream) -> void:
	_sfx[name] = stream


func _build_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)
	for i in MAX_POLYPHONY:
		var voice := AudioStreamPlayer.new()
		voice.name = "SfxPlayer%d" % i
		add_child(voice)
		_sfx_pool.append(voice)


## Scan SFX_DIR, load every .wav keyed by filename without extension.
func _load_sfx_registry() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		push_warning("AudioManager: sfx dir not found: %s" % SFX_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.get_extension().to_lower() == "wav":
			var stream: AudioStream = load(SFX_DIR + fname)
			if stream != null:
				_sfx[fname.get_basename()] = stream
		fname = dir.get_next()
	dir.list_dir_end()
