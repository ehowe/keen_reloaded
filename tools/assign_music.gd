extends SceneTree
## One-off: assign placeholder music to the bundled keen1 levels. Run headless:
##   godot --headless --path . --script res://tools/assign_music.gd
## Re-runnable; idempotent.

func _init() -> void:
	_assign("res://assets/levels/keen1/overworld.tres", "res://assets/audio/music/overworld.wav")
	_assign("res://assets/levels/keen1/level1.tres", "res://assets/audio/music/level.wav")
	quit()


func _assign(tres_path: String, wav_path: String) -> void:
	var ld := load(tres_path) as LevelData
	if ld == null:
		push_error("assign_music: cannot load %s" % tres_path)
		return
	ld.music = load(wav_path)
	var err := ResourceSaver.save(ld, tres_path)
	if err != OK:
		push_error("assign_music: save failed %s (err=%d)" % [tres_path, err])
		return
	print("assign_music: %s -> %s" % [tres_path, wav_path])
