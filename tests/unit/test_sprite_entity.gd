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
