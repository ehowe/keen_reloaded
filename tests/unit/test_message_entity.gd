extends GutTest

const SCENE := preload("res://src/runtime/entities/message.tscn")

func after_each():
	GameManager.register_episodes()

func _make(target := "msg_level_1", p_repeat := false) -> Message:
	var e: Message = SCENE.instantiate()
	add_child_autofree(e)
	e.setup("keen1.message", {"target_level_id": target, "repeat": p_repeat})
	return e

func _player_stub() -> Node:
	var n := Node.new()
	n.add_to_group("player")
	add_child_autofree(n)
	return n

func test_setup_reads_properties():
	var e := _make("lvl_x", true)
	assert_eq(e.target_level_id, "lvl_x")
	assert_true(e.repeat)

func test_setup_defaults():
	var e := _make()
	assert_eq(e.target_level_id, "msg_level_1")
	assert_false(e.repeat)

func test_contact_emits_signal():
	var e := _make("the_msg")
	watch_signals(e)
	e._handle_player(_player_stub())
	assert_signal_emit_count(e, "message_requested", 1)
	assert_signal_emitted_with_parameters(e, "message_requested", ["the_msg"])

func test_one_shot_blocks_reread():
	var e := _make("m", false)
	watch_signals(e)
	e._handle_player(_player_stub())
	e._handle_player(_player_stub())
	assert_signal_emit_count(e, "message_requested", 1, "one-shot emits only once")

func test_repeat_allows_reread():
	var e := _make("m", true)
	watch_signals(e)
	e._handle_player(_player_stub())
	e._handle_player(_player_stub())
	assert_signal_emit_count(e, "message_requested", 2, "repeatable emits every contact")

func test_fallback_visual_is_unread_color():
	var e := _make()
	var vis := e.get_node_or_null("Visual")
	assert_not_null(vis, "fallback Visual ColorRect exists")
	assert_true(vis is ColorRect)
	# Yellow-ish (unread default)
	assert_true((vis as ColorRect).color.r > 0.9, "unread fallback is yellow-ish")

func test_fallback_visual_swaps_to_read_color():
	var e := _make("m", false)
	e._handle_player(_player_stub())
	var vis := e.get_node("Visual") as ColorRect
	# Gray-ish (read state)
	assert_true(vis.color.r < 0.7, "read fallback is gray-ish")
	assert_true(vis.color.g < 0.7, "read fallback is gray-ish")

func test_repeat_stays_unread_color():
	var e := _make("m", true)
	e._handle_player(_player_stub())
	var vis := e.get_node("Visual") as ColorRect
	assert_true(vis.color.r > 0.9, "repeatable stays unread (yellow)")
