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

func test_enter_level_sets_pending_and_state():
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(lvl)
	# Avoid real scene swap during the test:
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(3, 4))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.pending_level, lvl)
	assert_eq(GameManager.last_entrance_pos, Vector2i(3, 4))
	assert_eq(GameManager.pending_player_spawn, Vector2i(-1, -1))

func test_complete_level_returns_to_overworld():
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(ow)
	GameManager.register_level(lvl)
	GameManager.current_overworld = ow
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(5, 6))
	GameManager.complete_level_no_scene_swap()
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_true(GameManager.is_level_completed("keen1_01"))

func test_episode_load_overworld_from_path():
	# Build a tiny overworld .tres, point an Episode at it, load.
	var ow := LevelData.new()
	ow.level_id = "ow_test"
	ow.level_name = "Test Overworld"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var path := "res://tests/tmp_overworld.tres"
	# Save into res:// so ResourceLoader.load(path) works headless.
	DirAccess.make_dir_recursive_absolute("res://tests/")
	assert_eq(ResourceSaver.save(ow, path), OK)
	var ep := Episode.new()
	ep.id = "t"
	ep.title = "T"
	ep.overworld_level_id = "ow_test"
	ep.overworld_path = path
	var loaded := ep.load_overworld()
	assert_not_null(loaded)
	assert_eq(loaded.level_id, "ow_test")
	assert_eq(loaded.map_kind, LevelData.MapKind.OVERWORLD)

func test_start_episode_sets_overworld_state():
	var ow := LevelData.new()
	ow.level_id = "ow_s"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	GameManager.register_level(ow)
	# start_episode_no_scene_swap takes the resolved overworld directly so the
	# test avoids directory scanning + scene swaps.
	GameManager.start_episode_no_scene_swap("fake", ow)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.current_overworld, ow)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.current_episode_id, "fake")
