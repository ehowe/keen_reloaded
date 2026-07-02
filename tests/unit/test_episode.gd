extends GutTest

func test_keen1_registers_expected_types():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	for tid in ["keen1.vorticon", "keen1.yorp", "keen1.butler", "keen1.candy",
			"keen1.raygun", "keen1.exit_door", "keen1.player_spawn"]:
		assert_true(EntityRegistry.has(tid), "%s registered" % tid)

func test_keen1_categories():
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)
	assert_eq(EntityRegistry.get_entry("keen1.vorticon")["category"], EntityRegistry.CATEGORY_ENEMY)
	assert_eq(EntityRegistry.get_entry("keen1.butler")["category"], EntityRegistry.CATEGORY_HAZARD)
	assert_eq(EntityRegistry.get_entry("keen1.candy")["category"], EntityRegistry.CATEGORY_ITEM)
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

func after_each():
	GameManager.register_episodes()
