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
	# The sprite's visual is the wrapper's only child (reparented from the
	# scene's bare-Node root so it inherits the wrapper's transform).
	assert_eq(node.get_child_count(), 1)
	assert_true(node.get_child(0) is Node)


func test_instantiate_sprite_visual_inherits_wrapper_position():
	# Regression: a sprite scene whose root is a bare Node (not a CanvasItem)
	# must still render at the wrapper's position. A non-CanvasItem between the
	# wrapper and the sprite severs the canvas transform chain, so the sprite
	# would otherwise render at the world origin (0, 0) instead of here.
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.exit_sign", EntityRegistry.CATEGORY_DECOR, "Exit Sign",
		"res://assets/sprites/Exit Sign.tscn")
	var cell_center := Vector2(224, 224)
	var wrapper := add_child_autofree(EntityRegistry.instantiate("keen1.exit_sign", cell_center)) as Node2D
	assert_not_null(wrapper)
	var visual := _first_canvas_descendant(wrapper)
	assert_not_null(visual, "sprite scene contributed a CanvasItem visual")
	assert_eq(visual.global_position, cell_center, "sprite visual renders at the wrapper's position")


func _register_spike_ad_hoc() -> void:
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])

func test_variant_right_shows_right_child_hides_left():
	_register_spike_ad_hoc()
	var n := add_child_autofree(EntityRegistry.instantiate("keen1.spike", Vector2.ZERO,
		{"facing": "right"})) as Node2D
	assert_not_null(n)
	assert_true(_find_child_named(n, "Spike Right").visible, "right variant visible")
	assert_false(_find_child_named(n, "SpikeLeft").visible, "left variant hidden")

func test_variant_left_shows_left_child_hides_right():
	_register_spike_ad_hoc()
	var n := add_child_autofree(EntityRegistry.instantiate("keen1.spike", Vector2.ZERO,
		{"facing": "left"})) as Node2D
	assert_not_null(n)
	assert_true(_find_child_named(n, "SpikeLeft").visible, "left variant visible")
	assert_false(_find_child_named(n, "Spike Right").visible, "right variant hidden")

func test_variant_default_applied_when_property_absent():
	# No facing key -> schema default "right" applies.
	_register_spike_ad_hoc()
	var n := add_child_autofree(EntityRegistry.instantiate("keen1.spike", Vector2.ZERO)) as Node2D
	assert_not_null(n)
	assert_true(_find_child_named(n, "Spike Right").visible, "default right variant visible")
	assert_false(_find_child_named(n, "SpikeLeft").visible, "non-default left variant hidden")

func _find_child_named(root: Node, want: String) -> CanvasItem:
	for c in root.get_children():
		if c is CanvasItem and String(c.name) == want:
			return c
		var deeper := _find_child_named(c, want)
		if deeper != null:
			return deeper
	return null


func _first_canvas_descendant(n: Node) -> CanvasItem:
	for c in n.get_children():
		if c is CanvasItem:
			return c
		var deeper := _first_canvas_descendant(c)
		if deeper != null:
			return deeper
	return null


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
