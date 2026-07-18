extends GutTest


class FakePlayer extends Node:
	var granted: Dictionary = {}  # color -> count
	func _ready() -> void:
		add_to_group("player")
	func add_keycard(color: String) -> void:
		granted[color] = int(granted.get(color, 0)) + 1
	func has_keycard(color: String) -> bool:
		return int(granted.get(color, 0)) > 0
	func consume_keycard(color: String) -> bool:
		if not has_keycard(color):
			return false
		granted[color] = int(granted[color]) - 1
		return true


func after_each():
	# Re-register the autoload's default roster so a clear() inside a test
	# doesn't leak an empty registry into later test scripts.
	GameManager.register_episodes()


func test_keycard_grants_matching_color():
	var kc: Keycard = add_child_autofree(load("res://src/runtime/entities/Keycard.tscn").instantiate())
	kc.variant = "blue"
	var p := FakePlayer.new()
	add_child_autofree(p)
	kc._on_body_entered(p)
	assert_true(p.has_keycard("blue"), "blue keycard granted")
	assert_false(p.has_keycard("red"), "only blue granted")


func test_keycard_pickup_frees_after_contact():
	var kc: Keycard = add_child_autofree(load("res://src/runtime/entities/Keycard.tscn").instantiate())
	kc.variant = "red"
	var p := FakePlayer.new()
	add_child_autofree(p)
	kc._on_body_entered(p)
	assert_true(kc.is_queued_for_deletion(), "keycard queue_frees after pickup")


func test_keycard_registered_as_level_item():
	var entry: Dictionary = EntityRegistry.get_entry("keen1.keycard")
	assert_eq(entry.get("category", ""), "item")
	var kinds: Array = entry.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "available on LEVEL maps")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "not available on OVERWORLD")


func test_keycard_variant_schema_has_four_colors():
	var schema := EntityRegistry.get_properties_schema("keen1.keycard")
	assert_eq(schema.size(), 1, "one property (variant)")
	assert_eq(String(schema[0].get("name")), "variant")
	assert_eq(String(schema[0].get("type")), "enum")
	assert_eq(String(schema[0].get("default")), "red")
	assert_eq(schema[0].get("options"), ["red", "blue", "yellow", "green"])


func test_keycard_instantiates_as_entity():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO)) as Node2D
	assert_not_null(node)
	assert_true(node is Keycard)
	assert_eq(node.type_id, "keen1.keycard")
	assert_true(node.is_in_group("entity"))


func test_keycard_variant_property_propagates_from_props():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO, {"variant": "yellow"})) as Keycard
	assert_eq(node.variant, "yellow", "variant property bound from props")


func test_keycard_variant_selects_matching_sprite():
	# Default variant = red; the Red sprite should be the only visible one
	# among the four color siblings under Visual.
	var kc: Keycard = add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO)) as Keycard
	assert_true(kc.get_node("Visual/Red").visible, "Red visible for default variant")
	assert_false(kc.get_node("Visual/Blue").visible, "Blue hidden")
	assert_false(kc.get_node("Visual/Yellow").visible, "Yellow hidden")
	assert_false(kc.get_node("Visual/Green").visible, "Green hidden")


func test_keycard_variant_selects_non_default_sprite():
	# Set variant=green via props; EntityVariant.apply must toggle visibility
	# (default scene state has Red visible — this test fails if apply is a no-op).
	var kc: Keycard = add_child_autofree(EntityRegistry.instantiate("keen1.keycard", Vector2.ZERO, {"variant": "green"})) as Keycard
	assert_true(kc.get_node("Visual/Green").visible, "Green visible for variant=green")
	assert_false(kc.get_node("Visual/Red").visible, "Red hidden")
	assert_false(kc.get_node("Visual/Blue").visible, "Blue hidden")
	assert_false(kc.get_node("Visual/Yellow").visible, "Yellow hidden")
