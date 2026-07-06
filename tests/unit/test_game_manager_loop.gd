extends GutTest

func before_each():
	GameManager.clear_progress()

func test_is_level_completed_false_by_default():
	assert_false(GameManager.is_level_completed("keen1_01"))

func test_mark_completed_then_query():
	GameManager.mark_completed("keen1_01")
	assert_true(GameManager.is_level_completed("keen1_01"))

func test_mark_completed_is_idempotent():
	GameManager.mark_completed("keen1_01")
	GameManager.mark_completed("keen1_01")
	assert_eq(GameManager.completed_levels.count("keen1_01"), 1)

func test_clear_progress():
	GameManager.mark_completed("keen1_01")
	var ld := LevelData.new()
	ld.level_id = "ow_x"
	GameManager.register_level(ld)
	GameManager.clear_progress()
	assert_false(GameManager.is_level_completed("keen1_01"))
	assert_null(GameManager.get_level_by_id("ow_x"), "registry cleared too")

func test_register_and_get_level():
	var ld := LevelData.new()
	ld.level_id = "ow_x"
	GameManager.register_level(ld)
	assert_eq(GameManager.get_level_by_id("ow_x"), ld)

func test_serialize_deserialize_round_trip():
	GameManager.mark_completed("a")
	GameManager.mark_completed("b")
	GameManager.current_episode_id = "keen1"
	var data := GameManager.serialize()
	GameManager.clear_progress()
	GameManager.current_episode_id = ""
	GameManager.deserialize(data)
	assert_true(GameManager.is_level_completed("a"))
	assert_true(GameManager.is_level_completed("b"))
	assert_eq(GameManager.current_episode_id, "keen1")

func test_default_state_is_menu():
	assert_eq(GameManager.state, GameManager.State.MENU)
