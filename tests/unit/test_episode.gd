extends GutTest

func test_keen1_registers_expected_types():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	for tid in ["keen1.vorticon", "keen1.yorp", "keen1.garg", "keen1.butler", "keen1.clapper",
			"keen1.lollipop", "keen1.soda", "keen1.pizza", "keen1.book",
			"keen1.teddy", "keen1.raygun", "keen1.exit_door", "keen1.player_spawn"]:
		assert_true(EntityRegistry.has(tid), "%s registered" % tid)

func test_keen1_categories():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_eq(EntityRegistry.get_entry("keen1.vorticon")["category"], EntityRegistry.CATEGORY_ENEMY)
	assert_eq(EntityRegistry.get_entry("keen1.butler")["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_eq(EntityRegistry.get_entry("keen1.garg")["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_eq(EntityRegistry.get_entry("keen1.clapper")["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_eq(EntityRegistry.get_entry("keen1.lollipop")["category"], EntityRegistry.CATEGORY_ITEM)
	assert_eq(EntityRegistry.get_entry("keen1.exit_door")["category"], EntityRegistry.CATEGORY_SPECIAL)

func test_register_episodes_populates_catalog_via_disk_scan():
	EntityRegistry.clear()
	GameManager.register_episodes()
	assert_true(EntityRegistry.has("keen1.vorticon"), "disk scan registered keen1.vorticon")
	assert_true(EntityRegistry.has("keen1.exit_door"), "disk scan registered keen1.exit_door")

func test_player_spawn_has_no_scene():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	var entry: Dictionary = EntityRegistry.get_entry("keen1.player_spawn")
	assert_null(entry.get("scene", null), "player_spawn is a marker with no scene")

func test_exit_sign_registered_as_decor():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.exit_sign"), "keen1.exit_sign registered")
	var e: Dictionary = EntityRegistry.get_entry("keen1.exit_sign")
	assert_eq(e["category"], EntityRegistry.CATEGORY_DECOR)
	assert_eq(e["scene_path"], "res://assets/sprites/Exit Sign.tscn")

func test_spike_registered_as_hazard_with_facing_schema():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.spike"), "keen1.spike registered")
	var e: Dictionary = EntityRegistry.get_entry("keen1.spike")
	assert_eq(e["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_true(e.get("scene", null) is PackedScene, "spike binds a runtime PackedScene")
	var schema := EntityRegistry.get_properties_schema("keen1.spike")
	assert_eq(schema.size(), 1)
	assert_eq(String(schema[0].get("name")), "facing")
	assert_eq(String(schema[0].get("type")), "enum")
	assert_eq(String(schema[0].get("default")), "right")
	assert_eq(schema[0].get("options"), ["right", "left"])

func test_level_entrance_has_variant_schema():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_true(EntityRegistry.has("keen1.level_entrance"), "keen1.level_entrance registered")
	var schema := EntityRegistry.get_properties_schema("keen1.level_entrance")
	assert_eq(schema.size(), 3)
	assert_eq(String(schema[0].get("name")), "target_level_id")
	assert_eq(String(schema[0].get("type")), "level_id")
	assert_eq(String(schema[1].get("name")), "blocks_until_completed")
	assert_eq(String(schema[1].get("type")), "bool")
	assert_eq(String(schema[2].get("name")), "variant")
	assert_eq(String(schema[2].get("type")), "enum")
	assert_eq(schema[2].get("options"),
		["City", "Blue Shrine", "Emerald", "Gray Shrine", "Crystal", "Castle", "Treasury"])

func test_keen1_load_levels_finds_level1():
	var ep := GameManager._find_episode("keen1")
	assert_not_null(ep, "_find_episode found keen1")
	if ep == null:
		return
	assert_eq(ep.id, "keen1")
	assert_eq(ep.overworld_path, "res://assets/levels/keen1/overworld.tres")
	var levels := ep.load_levels()
	assert_gt(levels.size(), 0, "load_levels found at least one level")
	var found_01 := false
	for lvl in levels:
		if lvl.level_id == "keen1_01":
			found_01 = true
	assert_true(found_01, "keen1_01 found in load_levels output")


func test_bundled_overworld_tres_carries_tile_data():
	# Regression: the authored overworld.tres is the source of truth (the
	# convert_levels_to_res tool regenerates the .res sibling from it, and the
	# in-game editor loads it directly). Its tile arrays must match w*h. An
	# earlier commit stripped these arrays, leaving the editor blank.
	var ld := load("res://assets/levels/keen1/overworld.tres") as LevelData
	assert_not_null(ld, "overworld.tres loads as LevelData")
	var want := ld.width * ld.height
	assert_eq(ld.geometry_tiles.size(), want, "geometry_tiles present in overworld.tres")
	assert_eq(ld.foreground_tiles.size(), want, "foreground_tiles present in overworld.tres")
	assert_eq(ld.background_tiles.size(), want, "background_tiles present in overworld.tres")
	var non_empty := 0
	for t in ld.background_tiles:
		if t != 0:
			non_empty += 1
			break
	assert_gt(non_empty, 0, "overworld.tres has at least one painted tile (not blank)")


func after_each():
	GameManager.register_episodes()
