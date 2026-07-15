extends GutTest


func test_garg_scene_has_named_sprites_no_placeholder():
	var g: Garg = add_child_autofree(load("res://src/runtime/entities/garg.tscn").instantiate())
	assert_false(g.has_node("Visual"), "no ColorRect placeholder")
	for pname in ["Walking", "Idle", "Shot"]:
		var n := g.get_node_or_null(pname)
		assert_not_null(n, "%s node present" % pname)
		assert_true(n is AnimatedSprite2D, "%s is AnimatedSprite2D" % pname)
	assert_false(g.has_node("Stunned"), "garg cannot be stunned -> no Stunned sprite")


func test_garg_shot_animation_is_one_shot():
	var g: Garg = add_child_autofree(load("res://src/runtime/entities/garg.tscn").instantiate())
	var shot := g.get_node("Shot") as AnimatedSprite2D
	assert_not_null(shot.sprite_frames, "Shot has SpriteFrames")
	var loop: bool = shot.sprite_frames.get_animation_loop(&"default")
	assert_false(loop, "Shot must be non-looping (one-shot)")
