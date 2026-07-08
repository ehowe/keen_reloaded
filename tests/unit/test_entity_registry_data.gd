extends GutTest

func after_each():
	# Restore the autoload's default roster so clearing here doesn't leak an
	# empty registry into later test scripts (e.g. test_level_runtime).
	GameManager.register_episodes()

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

func test_get_properties_schema_returns_declared_array():
	EntityRegistry.clear()
	var schema := [{name = "facing", default = "right", type = "enum", options = ["right", "left"]}]
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn", schema)
	var got := EntityRegistry.get_properties_schema("keen1.spike")
	assert_eq(got.size(), 1)
	assert_eq(String(got[0].get("name")), "facing")
	assert_eq(String(got[0].get("default")), "right")

func test_get_properties_schema_empty_for_unknown_and_schemaless():
	EntityRegistry.clear()
	assert_eq(EntityRegistry.get_properties_schema("nope"), [], "unknown type -> empty")
	EntityRegistry.register("vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	assert_eq(EntityRegistry.get_properties_schema("vorticon"), [], "schemaless type -> empty")

func test_enum_invalid_default_coerced_to_first_option():
	EntityRegistry.clear()
	var bad := [{name = "mood", default = "angry", type = "enum", options = ["happy", "sad"]}]
	EntityRegistry.register("thing", EntityRegistry.CATEGORY_ITEM, "Thing", bad)
	var s := EntityRegistry.get_properties_schema("thing")
	assert_eq(String(s[0].get("default")), "happy", "bad default coerced to options[0]")
	assert_eq(s[0].get("options"), ["happy", "sad"], "options preserved")
