extends GutTest

## Battery pickup tests. Mirrors test_pogo_pickup.gd structure: contact grants
## the keen1.battery inventory item and frees the pickup; registration is
## LEVEL-only under the keen1 episode.

class FakePlayer extends Node:
	func _ready() -> void:
		add_to_group("player")

func before_each():
	Inventory.clear()

func after_each():
	Inventory.clear()
	GameManager.register_episodes()


func test_battery_pickup_grants_inventory_item():
	var battery: BatteryPickup = add_child_autofree(load("res://src/runtime/entities/battery_pickup.tscn").instantiate())
	assert_false(Inventory.has_item(ItemIDs.BATTERY), "battery not owned before pickup")
	var p := FakePlayer.new()
	add_child_autofree(p)
	battery._on_body_entered(p)
	assert_true(Inventory.has_item(ItemIDs.BATTERY), "battery owned after pickup")
	assert_true(battery.is_queued_for_deletion(), "pickup frees after use")


func test_battery_pickup_registered_as_level_item():
	var entry: Dictionary = EntityRegistry.get_entry("keen1.battery")
	assert_eq(entry.get("category", ""), "item")
	var kinds: Array = entry.get("map_kinds", [])
	assert_true(kinds.has(LevelData.MapKind.LEVEL), "available on LEVEL maps")
	assert_false(kinds.has(LevelData.MapKind.OVERWORLD), "not available on OVERWORLD")


func test_battery_pickup_instantiates_as_entity():
	var node := add_child_autofree(EntityRegistry.instantiate("keen1.battery", Vector2.ZERO)) as Node2D
	assert_not_null(node)
	assert_true(node is BatteryPickup)
	assert_eq(node.type_id, "keen1.battery")
	assert_true(node.is_in_group("entity"))
