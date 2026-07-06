extends GutTest

const TILE := 64

func before_each():
	GameManager.clear_progress()

func _make_entrance(target := "keen1_01", gate := false) -> Node2D:
	var e := LevelEntrance.new()
	add_child_autofree(e)
	e.setup("keen1.level_entrance", {"target_level_id": target, "blocks_until_completed": gate})
	e.set_tile(Vector2i(3, 4))
	return e

func test_setup_reads_properties():
	var e := _make_entrance("lvl2", true)
	assert_eq(e.target_level_id, "lvl2")
	assert_true(e.blocks_until_completed)

func test_set_tile_records_position():
	var e := _make_entrance()
	assert_eq(e.tile, Vector2i(3, 4))

func test_non_gate_never_blocks():
	var e := _make_entrance("a", false)
	assert_false(e.is_blocking())

func test_gate_blocks_when_uncompleted():
	var e := _make_entrance("a", true)
	assert_true(e.is_blocking())

func test_gate_unblocks_when_completed():
	GameManager.mark_completed("a")
	var e := _make_entrance("a", true)
	assert_false(e.is_blocking())

func test_gate_with_empty_target_never_blocks():
	# A gate pointing at no level must not wall off the overworld forever.
	var e := _make_entrance("", true)
	assert_false(e.is_blocking())

func test_attempt_enter_requires_nearby():
	var e := _make_entrance("a", false)
	assert_false(e.attempt_enter(true))
	e._set_nearby_for_test(true)
	assert_true(e.attempt_enter(true))

func test_attempt_enter_requires_interact():
	var e := _make_entrance("a", false)
	e._set_nearby_for_test(true)
	assert_false(e.attempt_enter(false))

func test_attempt_enter_emits_signal():
	var e := _make_entrance("lvl_x", false)
	e._set_nearby_for_test(true)
	var captured := {"target": "", "tile": Vector2i(-1, -1)}
	e.enter_requested.connect(func(t: String, tile: Vector2i) -> void:
		captured["target"] = t
		captured["tile"] = tile)
	e.attempt_enter(true)
	assert_eq(captured["target"], "lvl_x")
	assert_eq(captured["tile"], Vector2i(3, 4))

func test_refresh_blocking_clears_after_completion():
	var e := _make_entrance("a", true)
	assert_true(e.is_blocking())
	GameManager.mark_completed("a")
	e.refresh_blocking()
	assert_false(e.is_blocking())
