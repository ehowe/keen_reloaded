extends GutTest


func _register_thing() -> void:
	EntityRegistry.clear()
	EntityRegistry.register("test.thing", EntityRegistry.CATEGORY_DECOR, "Thing",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])


## Build a synthetic variant tree: root -> "Thing right" + "Thing left" (both Node2D,
## which are CanvasItems). Mirrors the descendant structure a real sprite scene has.
func _build_tree() -> Node2D:
	var root := Node2D.new()
	add_child_autofree(root)
	var right := Node2D.new()
	right.name = "Thing right"
	var left := Node2D.new()
	left.name = "Thing left"
	root.add_child(right)
	root.add_child(left)
	return root


func test_apply_shows_matching_variant_hides_others():
	_register_thing()
	var root := _build_tree()
	EntityVariant.apply("test.thing", {"facing": "left"}, root)
	assert_true(root.get_node("Thing left").visible, "left variant visible")
	assert_false(root.get_node("Thing right").visible, "right variant hidden")


func test_apply_falls_back_to_schema_default_when_prop_absent():
	_register_thing()
	var root := _build_tree()
	EntityVariant.apply("test.thing", {}, root)
	assert_true(root.get_node("Thing right").visible, "default right variant visible")
	assert_false(root.get_node("Thing left").visible, "non-default left variant hidden")


func test_apply_finds_variant_grandchildren():
	# Variant sprites are often grandchildren (under a wrapper node). The walk
	# must descend, not just read direct children.
	_register_thing()
	var root := Node2D.new()
	add_child_autofree(root)
	var wrapper := Node2D.new()
	wrapper.name = "Visual"
	root.add_child(wrapper)
	var right := Node2D.new()
	right.name = "Thing right"
	var left := Node2D.new()
	left.name = "Thing left"
	wrapper.add_child(right)
	wrapper.add_child(left)
	EntityVariant.apply("test.thing", {"facing": "left"}, root)
	assert_true(left.visible, "grandchild left variant visible")
	assert_false(right.visible, "grandchild right variant hidden")
