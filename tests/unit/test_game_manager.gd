extends GutTest

func test_pending_level_round_trip():
	var ld := LevelData.new()
	ld.level_id = "t"
	GameManager.pending_level = ld
	assert_eq(GameManager.pending_level, ld)
	GameManager.pending_level = null

func test_return_scene_round_trip():
	var ps := PackedScene.new()
	GameManager.return_scene = ps
	assert_eq(GameManager.return_scene, ps)
	GameManager.return_scene = null

func test_input_actions_registered():
	# GameManager._ready runs at autoload load, before tests.
	assert_true(InputMap.has_action("move_left"))
	assert_true(InputMap.has_action("move_right"))
	assert_true(InputMap.has_action("jump"))
	assert_true(InputMap.has_action("pogo"))
	assert_true(InputMap.has_action("shoot"))

func test_interact_action_registered():
	assert_true(InputMap.has_action("interact"))
