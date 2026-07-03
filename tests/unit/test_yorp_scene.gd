extends GutTest


func test_yorp_scene_has_four_named_sprites_no_placeholder():
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	assert_false(y.has_node("Visual"), "no ColorRect placeholder")
	for pname in ["Walking", "Idle", "Stunned", "Shot"]:
		var n := y.get_node_or_null(pname)
		assert_not_null(n, "%s node present" % pname)
		assert_true(n is AnimatedSprite2D, "%s is AnimatedSprite2D" % pname)


func test_yorp_shot_animation_is_one_shot():
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	var shot := y.get_node("Shot") as AnimatedSprite2D
	assert_not_null(shot.sprite_frames, "Shot has SpriteFrames")
	var loop: bool = shot.sprite_frames.get_animation_loop(&"default")
	assert_false(loop, "Shot must be non-looping (one-shot)")
