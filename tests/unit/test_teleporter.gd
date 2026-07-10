extends GutTest

const SCENE := preload("res://src/runtime/entities/teleporter.tscn")

func _teleporter(tid := "a", dlevel := "lvl1", dtp := "b") -> Node2D:
	var t := SCENE.instantiate()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {
		"teleporter_id": tid,
		"destination_level_id": dlevel,
		"destination_teleporter_id": dtp,
	})
	return t

func _anim(t: Node) -> AnimatedSprite2D:
	return t.get_node("AnimatedSprite2D") as AnimatedSprite2D

func _visual(t: Node) -> CanvasItem:
	return t.get_node("Visual") as CanvasItem


func test_setup_reads_properties():
	var t := _teleporter("alpha", "lvl2", "beta")
	assert_eq(t.teleporter_id, "alpha")
	assert_eq(t.destination_level_id, "lvl2")
	assert_eq(t.destination_teleporter_id, "beta")

func test_setup_defaults_empty():
	var t := SCENE.instantiate()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {})
	assert_eq(t.teleporter_id, "")
	assert_eq(t.destination_level_id, "")
	assert_eq(t.destination_teleporter_id, "")

func test_idle_shows_visual_hides_anim():
	var t := _teleporter()
	assert_true(_visual(t).visible, "static Visual shown when idle")
	assert_false(_anim(t).visible, "AnimatedSprite2D hidden when idle")

func test_attempt_teleport_requires_nearby():
	var t := _teleporter()
	assert_false(t.attempt_teleport(true))
	t._set_nearby_for_test(true)
	assert_true(t.attempt_teleport(true))

func test_attempt_teleport_requires_interact():
	var t := _teleporter()
	t._set_nearby_for_test(true)
	assert_false(t.attempt_teleport(false))

func test_attempt_teleport_requires_destination_fields():
	var t := SCENE.instantiate()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {"teleporter_id": "a", "destination_level_id": "", "destination_teleporter_id": ""})
	t._set_nearby_for_test(true)
	assert_false(t.attempt_teleport(true))

func test_departure_starts_anim_and_hides_player():
	var t := _teleporter()
	var p := Node2D.new()
	add_child_autofree(p)
	p.visible = true
	t._set_player_for_test(p)
	t._set_nearby_for_test(true)
	assert_true(t.attempt_teleport(true))
	assert_true(_anim(t).visible, "anim shown on departure")
	assert_true(_anim(t).is_playing(), "anim playing on departure")
	assert_false(_visual(t).visible, "static Visual hidden on departure")
	assert_false(p.visible, "player hidden on departure")
	assert_eq(p.process_mode, Node.PROCESS_MODE_DISABLED, "player frozen on departure")

func test_departure_does_not_emit_until_anim_finishes():
	var t := _teleporter("a", "lvl_x", "b")
	t._set_nearby_for_test(true)
	var captured := {"l": "", "tp": ""}
	t.teleport_requested.connect(func(l: String, tp: String) -> void:
		captured["l"] = l
		captured["tp"] = tp)
	t.attempt_teleport(true)  # starts the anim; must NOT emit yet
	assert_eq(captured["l"], "", "no emit until anim finishes")
	# Simulate the animation completing.
	t._on_animation_finished()
	assert_eq(captured["l"], "lvl_x")
	assert_eq(captured["tp"], "b")

func test_play_arrival_hides_player_and_restores_on_finish():
	var t := _teleporter()
	var p := Node2D.new()
	add_child_autofree(p)
	p.visible = true
	p.set_process_mode(Node.PROCESS_MODE_INHERIT)
	var state := {"done": false}
	t.arrival_finished.connect(func() -> void: state["done"] = true)
	t.play_arrival(p)
	assert_false(p.visible, "player hidden on arrival")
	assert_eq(p.process_mode, Node.PROCESS_MODE_DISABLED, "player frozen on arrival")
	assert_true(_anim(t).is_playing(), "arrival anim playing")
	assert_false(_visual(t).visible, "static Visual hidden during arrival anim")
	# Simulate the animation completing.
	t._on_animation_finished()
	assert_true(state["done"], "arrival_finished emitted")
	assert_true(p.visible, "player shown again after arrival")
	assert_eq(p.process_mode, Node.PROCESS_MODE_INHERIT, "player unfrozen after arrival")
	assert_true(_visual(t).visible, "static Visual restored after arrival")
	assert_false(_anim(t).visible, "anim hidden again after arrival")

func test_restore_after_failed_departure_restores_player_and_visual():
	var t := _teleporter()
	var p := Node2D.new()
	add_child_autofree(p)
	t._set_player_for_test(p)
	t._set_nearby_for_test(true)
	t.attempt_teleport(true)  # depart: player hidden+frozen, anim playing
	assert_false(p.visible, "player hidden during departure")
	t.restore_after_failed_departure()
	assert_true(p.visible, "player shown again after failed departure")
	assert_eq(p.process_mode, Node.PROCESS_MODE_INHERIT, "player unfrozen after failed departure")
	assert_true(_visual(t).visible, "static Visual restored")
	assert_false(_anim(t).visible, "anim hidden after restore")
