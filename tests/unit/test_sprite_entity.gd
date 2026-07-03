extends GutTest

func after_each():
	# Restore the autoload's default roster so clearing here doesn't leak an
	# empty registry into later test scripts (e.g. test_level_runtime).
	GameManager.register_episodes()


func test_sprite_entity_is_node2d_with_setup():
	var s := add_child_autofree(SpriteEntity.new()) as SpriteEntity
	s.setup("keen1.exit_sign", {"foo": 1})
	assert_true(s is Node2D, "SpriteEntity is a Node2D")
	assert_eq(s.type_id, "keen1.exit_sign")
	assert_eq(s.properties.get("foo"), 1)
