extends SceneTree
## One-off audio asset generator. Writes placeholder .wav files into
## assets/audio/{sfx,music}/. Run headless:
##   godot --headless --path . --script res://tools/gen_audio.gd
## Output is committed; re-run only to regenerate. Not a runtime dependency.
## All output is original/CC0 — free to replace with real Keen-style audio.

const SR := 44100
const SHAPE_SINE := 0
const SHAPE_SQUARE := 1
const TAU_F := 6.2831853

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SFX_DIR)
	DirAccess.make_dir_recursive_absolute(MUSIC_DIR)
	# ---- SFX (short, envelope-decayed) ----
	_sfx("jump.wav", _tone(220.0, 440.0, 0.12, SHAPE_SQUARE, 0.6))
	_sfx("pogo.wav", _tone(330.0, 660.0, 0.10, SHAPE_SQUARE, 0.6))
	_sfx("shoot.wav", _tone(880.0, 220.0, 0.10, SHAPE_SQUARE, 0.5))
	_sfx("hurt.wav", _tone(110.0, 90.0, 0.22, SHAPE_SQUARE, 0.7))
	_sfx("die.wav", _tone(330.0, 110.0, 0.45, SHAPE_SQUARE, 0.6))
	_sfx("pickup_score.wav", _concat(
		_tone(660.0, 660.0, 0.07, SHAPE_SQUARE, 0.5),
		_tone(990.0, 990.0, 0.08, SHAPE_SQUARE, 0.5)))
	_sfx("pickup_ammo.wav", _tone(1320.0, 1320.0, 0.09, SHAPE_SINE, 0.5))
	_sfx("enemy_hit.wav", _tone(440.0, 440.0, 0.04, SHAPE_SQUARE, 0.4))
	_sfx("enemy_die.wav", _tone(440.0, 110.0, 0.25, SHAPE_SQUARE, 0.55))
	_sfx("complete.wav", _arpeggio([523.0, 659.0, 784.0, 1047.0], 0.10, SHAPE_SQUARE, 0.5))
	_sfx("menu_move.wav", _tone(1000.0, 1000.0, 0.02, SHAPE_SQUARE, 0.3))
	_sfx("menu_select.wav", _concat(
		_tone(660.0, 660.0, 0.05, SHAPE_SQUARE, 0.4),
		_tone(880.0, 880.0, 0.06, SHAPE_SQUARE, 0.4)))
	# ---- Music (sustained drones; integer-period length -> seamless loop) ----
	_music("menu.wav", _drone([130.0, 196.0], 8.0, 0.18))
	_music("overworld.wav", _drone([164.0, 246.0], 16.0, 0.16))
	_music("level.wav", _drone([196.0, 246.0, 294.0], 16.0, 0.15))
	print("gen_audio: wrote assets/audio/{sfx,music}")
	quit()


## Pitch sweep f0->f1 over duration, exponential decay. For SFX (no loop needed).
func _tone(f0: float, f1: float, duration: float, shape: int, vol: float) -> PackedInt32Array:
	var total := maxi(1, int(round(duration * SR)))
	var out := PackedInt32Array()
	out.resize(total)
	var phase := 0.0
	for i in total:
		var t := float(i) / float(total)
		var freq := lerpf(f0, f1, t)
		phase += freq / float(SR)
		var p := fmod(phase, 1.0)
		var s := sin(p * TAU_F) if shape == SHAPE_SINE else (-1.0 if p < 0.5 else 1.0)
		var env := exp(-3.5 * t)
		out[i] = int(clampf(s * env * vol, -1.0, 1.0) * 32767.0)
	return out


## Sustained chord drone (sum of sines). Sample count aligned to an integer
## number of periods of the fundamental -> seamless loop, no clicks.
func _drone(freqs: Array, duration: float, vol: float) -> PackedInt32Array:
	var fundamental: float = freqs[0]
	var periods := maxi(1, int(round(fundamental * duration)))
	var total := int(round(float(periods) / fundamental * float(SR)))
	var out := PackedInt32Array()
	out.resize(total)
	var norm := 1.0 / float(freqs.size())
	for i in total:
		var s := 0.0
		for f in freqs:
			s += sin(fmod(float(i) * float(f) / float(SR), 1.0) * TAU_F)
		out[i] = int(clampf(s * norm * vol, -1.0, 1.0) * 32767.0)
	return out


func _arpeggio(freqs: Array, note_dur: float, shape: int, vol: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in freqs:
		out.append_array(_tone(float(f), float(f), note_dur, shape, vol))
	return out


func _concat(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var out := a.duplicate()
	out.append_array(b)
	return out


func _sfx(name: String, samples: PackedInt32Array) -> void:
	_write(SFX_DIR, name, samples)


func _music(name: String, samples: PackedInt32Array) -> void:
	_write(MUSIC_DIR, name, samples)


func _write(dir: String, name: String, samples: PackedInt32Array) -> void:
	var f := FileAccess.open(dir + name, FileAccess.WRITE)
	if f == null:
		push_error("gen_audio: cannot write %s%s" % [dir, name])
		return
	f.store_buffer(_wav_bytes(samples))
	f.close()


## Build a 16-bit mono PCM WAV byte buffer from int16 samples.
func _wav_bytes(samples: PackedInt32Array) -> PackedByteArray:
	var data_size := samples.size() * 2
	var b := PackedByteArray()
	b.append_array("RIFF".to_ascii_buffer())
	_u32(b, 36 + data_size)
	b.append_array("WAVE".to_ascii_buffer())
	b.append_array("fmt ".to_ascii_buffer())
	_u32(b, 16)        # PCM fmt chunk size
	_u16(b, 1)         # audio format = PCM
	_u16(b, 1)         # mono
	_u32(b, SR)
	_u32(b, SR * 2)    # byte rate = sr * channels * bytes/sample
	_u16(b, 2)         # block align
	_u16(b, 16)        # bits per sample
	b.append_array("data".to_ascii_buffer())
	_u32(b, data_size)
	for s in samples:
		_u16(b, clampi(s, -32768, 32767))
	return b


## Append an int as 2 little-endian bytes (two's complement for negatives).
func _u16(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)


## Append an int as 4 little-endian bytes.
func _u32(b: PackedByteArray, v: int) -> void:
	b.append(v & 0xFF)
	b.append((v >> 8) & 0xFF)
	b.append((v >> 16) & 0xFF)
	b.append((v >> 24) & 0xFF)
