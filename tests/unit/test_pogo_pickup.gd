extends GutTest

class FakePlayer extends Node:
	func _ready() -> void:
		add_to_group("player")

func before_each():
	Inventory.clear()

func after_each():
	Inventory.clear()
	GameManager.register_episodes()

func test_pogo_pickup_grants_inventory_item():
	var pogo: PogoStick = add_child_autofree(load("res://src/runtime/entities/pogo_stick.tscn").instantiate())
	assert_false(Inventory.has_item("keen1.pogo"), "pogo not owned before pickup")
	var p := FakePlayer.new()
	add_child_autofree(p)
	pogo._on_body_entered(p)
	assert_true(Inventory.has_item("keen1.pogo"), "pogo owned after pickup")
	assert_true(pogo.is_queued_for_deletion(), "pickup frees after use")

func test_pogo_stick_registered_as_level_item():
	var entry: Dictionary = EntityRegistry.get_entry("keen1.pogo_stick")
	assert_eq(entry.get("category", ""), "item")
	var kinds: Array = entry.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "available on LEVEL maps")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "not available on OVERWORLD")

func test_pogo_stick_palette_hidden_on_overworld():
	var level_entries := EntityRegistry.get_palette_entries_for_kind(LevelData.MapKind.LEVEL)
	var overworld_entries := EntityRegistry.get_palette_entries_for_kind(LevelData.MapKind.OVERWORLD)
	var has_level := false
	for e in level_entries:
		if String(e.get("type_id", "")) == "keen1.pogo_stick":
			has_level = true
	assert_true(has_level, "pogo_stick in LEVEL palette")
	var has_ow := false
	for e in overworld_entries:
		if String(e.get("type_id", "")) == "keen1.pogo_stick":
			has_ow = true
	assert_false(has_ow, "pogo_stick NOT in OVERWORLD palette")

func test_pogo_stick_instantiates_as_entity():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.pogo_stick", Vector2.ZERO)) as Node2D
	assert_not_null(node)
	assert_true(node is PogoStick)
	assert_eq(node.type_id, "keen1.pogo_stick")
	assert_true(node.is_in_group("entity"))
