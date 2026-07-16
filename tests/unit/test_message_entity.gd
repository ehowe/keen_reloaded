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

func test_base_always_visible():
	var e := _make()
	var base := e.get_node_or_null("Base") as CanvasItem
	assert_not_null(base, "Base sprite exists")
	assert_true(base.visible, "Base visible by default")
	e._handle_player(_player_stub())
	assert_true(base.visible, "Base still visible after read")

func test_unread_visible_and_playing_by_default():
	var e := _make()
	var unread := e.get_node_or_null("Unread") as CanvasItem
	assert_not_null(unread, "Unread sprite exists")
	assert_true(unread.visible, "Unread visible by default")
	if unread is AnimatedSprite2D:
		assert_true((unread as AnimatedSprite2D).is_playing(), "Unread animation playing")

func test_read_hidden_by_default():
	var e := _make()
	var read := e.get_node_or_null("Read") as CanvasItem
	assert_not_null(read, "Read sprite exists")
	assert_false(read.visible, "Read hidden by default")

func test_one_shot_swaps_unread_to_read():
	var e := _make("m", false)
	e._handle_player(_player_stub())
	assert_false((e.get_node("Unread") as CanvasItem).visible, "Unread hidden after one-shot read")
	assert_true((e.get_node("Read") as CanvasItem).visible, "Read shown after one-shot read")
	if e.get_node("Unread") is AnimatedSprite2D:
		assert_false((e.get_node("Unread") as AnimatedSprite2D).is_playing(), "Unread animation stopped")

func test_repeat_stays_unread():
	var e := _make("m", true)
	e._handle_player(_player_stub())
	assert_true((e.get_node("Unread") as CanvasItem).visible, "Unread stays visible for repeatable")
	assert_false((e.get_node("Read") as CanvasItem).visible, "Read stays hidden for repeatable")


func test_runtime_message_overlay_builds_and_dismisses():
	# Register a fake MESSAGE level that GameManager can resolve.
	var msg_level := LevelData.new()
	msg_level.level_id = "test_msg_level"
	msg_level.width = 4
	msg_level.height = 2
	msg_level.tile_size = 16
	msg_level.fill_blank()
	msg_level.map_kind = LevelData.MapKind.MESSAGE
	GameManager.register_level(msg_level)

	# Build a runtime with a Message entity.
	var level := LevelData.new()
	level.width = 6
	level.height = 4
	level.tile_size = 16
	level.fill_blank()
	level.player_spawn = Vector2i(1, 1)
	level.entities.append(EntityDef.new("keen1.message", 3, 1, {"target_level_id": "test_msg_level"}))
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(level)

	# Simulate contact by calling the handler directly.
	rt._on_message_requested("test_msg_level")
	assert_not_null(rt.find_child("MessageOverlay", true, false), "overlay added")
	assert_true(get_tree().paused, "tree paused")

	# Verify the MessageContent node exists and is centered/scaled.
	var content := rt.find_child("MessageContent", true, false) as Node2D
	assert_not_null(content, "MessageContent node exists")
	assert_eq(content.scale, Vector2.ONE, "small message not upscaled (fit capped at 1.0)")

	# Dismiss.
	rt._on_message_dismissed()
	assert_false(get_tree().paused, "tree unpaused after dismiss")
	assert_null(rt.find_child("MessageOverlay", true, false), "overlay removed")


func test_runtime_message_overlay_scales_large_message():
	# A message larger than the viewport should be scaled down to fit.
	var msg_level := LevelData.new()
	msg_level.level_id = "big_msg"
	msg_level.width = 200
	msg_level.height = 200
	msg_level.tile_size = 16
	msg_level.fill_blank()
	msg_level.map_kind = LevelData.MapKind.MESSAGE
	GameManager.register_level(msg_level)

	var level := LevelData.new()
	level.width = 6
	level.height = 4
	level.tile_size = 16
	level.fill_blank()
	level.player_spawn = Vector2i(1, 1)
	level.entities.append(EntityDef.new("keen1.message", 3, 1, {"target_level_id": "big_msg"}))
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(level)

	rt._on_message_requested("big_msg")
	var content := rt.find_child("MessageContent", true, false) as Node2D
	assert_not_null(content, "MessageContent exists for large message")
	assert_true(content.scale.x < 1.0 and content.scale.y < 1.0, "large message scaled down to fit viewport")
	rt._on_message_dismissed()


func test_runtime_message_unknown_level_no_crash():
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt._on_message_requested("nonexistent_level_id")
	assert_false(get_tree().paused, "no pause when message level not found")
	assert_null(rt.find_child("MessageOverlay", true, false), "no overlay for unknown level")
