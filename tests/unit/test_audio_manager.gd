extends GutTest

const KNOWN := ["jump", "pogo", "shoot", "hurt", "die", "pickup_score",
	"pickup_ammo", "enemy_hit", "enemy_die", "complete", "menu_move", "menu_select"]


func test_registry_has_all_known_sfx():
	for n in KNOWN:
		assert_true(AudioManager._sfx.has(n), "registry should contain sfx '%s'" % n)


func test_registry_nonempty():
	assert_gt(AudioManager._sfx.size(), 0)


func test_unknown_sfx_is_noop():
	# Unknown name must not crash and must not pollute the registry.
	AudioManager.play_sfx("definitely_not_real")
	assert_false(AudioManager._sfx.has("definitely_not_real"))


func test_register_sfx_seam():
	var stream := load("res://assets/audio/sfx/jump.wav")
	AudioManager.register_sfx("seam_test", stream)
	assert_true(AudioManager._sfx.has("seam_test"))
	AudioManager.play_sfx("seam_test")  # registered -> no warning
	AudioManager._sfx.erase("seam_test")


func test_play_music_starts_player():
	var stream := load("res://assets/audio/sfx/jump.wav")
	AudioManager.play_music(stream)
	assert_true(AudioManager._music_player.playing)
	assert_eq(AudioManager._music_player.stream, stream)


func test_play_music_null_stops():
	AudioManager.play_music(null)
	assert_false(AudioManager._music_player.playing)


func test_stop_music():
	var stream := load("res://assets/audio/sfx/jump.wav")
	AudioManager.play_music(stream)
	AudioManager.stop_music()
	assert_false(AudioManager._music_player.playing)


func test_stop_all_stops_music():
	var stream := load("res://assets/audio/sfx/jump.wav")
	AudioManager.play_music(stream)
	AudioManager.stop_all()
	assert_false(AudioManager._music_player.playing)
