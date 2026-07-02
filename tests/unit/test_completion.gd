extends GutTest

func _level_with_exit() -> LevelData:
	var ld := LevelData.new()
	ld.width = 8
	ld.height = 4
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	ld.entities.append(EntityDef.new("keen1.exit_door", 6, 1))
	return ld


func test_exit_door_emits_once():
	var door: ExitDoor = add_child_autofree(load("res://src/runtime/entities/exit_door.tscn").instantiate())
	watch_signals(door)
	var stub := Node.new()
	stub.add_to_group("player")
	add_child_autofree(stub)
	door._handle_player(stub)
	door._handle_player(stub)  # second contact must not re-emit
	assert_signal_emit_count(door, "level_completed", 1, "level_completed emitted exactly once")


func test_runtime_completion_shows_overlay_and_pauses():
	GameManager.pending_level = null
	GameManager.return_scene = preload("res://src/editor/level_editor.tscn")
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level_with_exit())
	assert_false(rt._completed, "not completed before exit")
	rt._on_level_completed()
	assert_true(rt._completed, "marked completed")
	assert_not_null(rt.find_child("CompletionOverlay", true, false), "overlay added")
	assert_true(get_tree().paused, "tree paused")
	get_tree().paused = false  # reset for the test harness
	GameManager.return_scene = null


func after_each():
	GameManager.register_episodes()
