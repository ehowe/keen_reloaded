extends GutTest

func after_each():
	# Clear first: register_episodes() only re-runs each episode's
	# register_entities() (add/overwrite), so a non-episode type_id registered
	# by a test (e.g. keen1.exit_sign) would otherwise leak into later scripts.
	EntityRegistry.clear()
	GameManager.register_episodes()


func test_sprite_entity_is_node2d_with_setup():
	var s := add_child_autofree(SpriteEntity.new()) as SpriteEntity
	s.setup("keen1.exit_sign", {"foo": 1})
	assert_true(s is Node2D, "SpriteEntity is a Node2D")
	assert_eq(s.type_id, "keen1.exit_sign")
	assert_eq(s.properties.get("foo"), 1)


func test_register_sprite_adds_decor_entry():
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.exit_sign", EntityRegistry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	assert_true(EntityRegistry.has("keen1.exit_sign"))
	var e: Dictionary = EntityRegistry.get_entry("keen1.exit_sign")
	assert_eq(e["category"], EntityRegistry.CATEGORY_DECOR)
	assert_eq(e["label"], "Exit Sign")
	assert_eq(e["scene_path"], "res://assets/sprites/Exit Sign.tscn")
	assert_eq(e.get("properties"), [], "properties defaults to empty array")
	# Surfaced in the palette, grouped under decor.
	var entries := EntityRegistry.get_palette_entries()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["type_id"], "keen1.exit_sign")


func test_instantiate_sprite_wraps_scene_in_sprite_entity():
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.exit_sign", EntityRegistry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.exit_sign", Vector2(100, 200))) as Node2D
	assert_not_null(node)
	assert_true(node is SpriteEntity, "sprite entry instantiates a SpriteEntity wrapper")
	assert_eq(node.position, Vector2(100, 200))
	assert_eq(node.type_id, "keen1.exit_sign")
	assert_true(node.is_in_group("entity"))
	# The raw sprite scene is the wrapper's only child.
	assert_eq(node.get_child_count(), 1)
	assert_true(node.get_child(0) is Node)


func test_instantiate_sprite_missing_path_returns_null():
	EntityRegistry.clear()
	EntityRegistry.register_sprite("bogus", EntityRegistry.CATEGORY_DECOR, "Bogus",
		"res://assets/sprites/does_not_exist.tscn")
	assert_null(EntityRegistry.instantiate("bogus", Vector2.ZERO))


func test_instantiate_scripted_entity_not_wrapped():
	# Real default-roster scripted entity must still instantiate via its
	# PackedScene branch, NOT the sprite wrapper.
	var y := add_child_autofree(EntityRegistry.instantiate("keen1.yorp", Vector2.ZERO)) as Node2D
	assert_not_null(y)
	assert_false(y is SpriteEntity, "scripted entity is not wrapped in SpriteEntity")
