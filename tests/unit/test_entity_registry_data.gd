extends GutTest

func after_each():
	# Restore the autoload's default roster so clearing here doesn't leak an
	# empty registry into later test scripts (e.g. test_level_runtime).
	EntityRegistry.register_defaults()

func test_register_and_lookup():
	EntityRegistry.clear()
	EntityRegistry.register("vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	assert_true(EntityRegistry.has("vorticon"))
	var e: Dictionary = EntityRegistry.get_entry("vorticon")
	assert_eq(e["type_id"], "vorticon")
	assert_eq(e["category"], EntityRegistry.CATEGORY_ENEMY)
	assert_eq(e["label"], "Vorticon")

func test_get_entry_missing_returns_empty():
	EntityRegistry.clear()
	assert_false(EntityRegistry.has("nope"))
	assert_eq(EntityRegistry.get_entry("nope"), {})

func test_palette_entries_sorted_by_category_then_label():
	EntityRegistry.clear()
	EntityRegistry.register("yorp", EntityRegistry.CATEGORY_ENEMY, "Yorp")
	EntityRegistry.register("candy", EntityRegistry.CATEGORY_ITEM, "Candy")
	EntityRegistry.register("vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	var entries: Array = EntityRegistry.get_palette_entries()
	assert_eq(entries.size(), 3)
	# enemies (e) sort before items (i); within enemies: Vorticon before Yorp
	assert_eq(entries[0]["type_id"], "vorticon")
	assert_eq(entries[1]["type_id"], "yorp")
	assert_eq(entries[2]["type_id"], "candy")
