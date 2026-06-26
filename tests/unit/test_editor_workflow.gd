extends GutTest

const G := "geometry"

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "keen1_01"
	ld.level_name = "Border Village"
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 6
	ld.height = 4
	ld.fill_blank()
	return ld

func test_full_editor_workflow_then_serialize():
	var ld := _level()
	var s := UndoStack.new()

	# paint a floor
	var stroke := PaintCellsCmd.new(G, 1)
	for x in range(6):
		stroke.paint(ld, x, 3)
	s.push_applied(ld, stroke)

	# flood-fill the area above the floor with id 2
	s.execute(ld, FloodFillCmd.new(G, Vector2i(0, 0), 2))

	# place entities + spawn
	s.execute(ld, AddEntityCmd.new(EntityDef.new("vorticon", 2, 1, {"speed": 20})))
	s.execute(ld, AddEntityCmd.new(EntityDef.new("candy", 4, 2)))
	s.execute(ld, SetPlayerSpawnCmd.new(Vector2i(0, 2)))

	# sanity-check the model
	assert_eq(ld.get_tile(G, 0, 3), 1)
	assert_eq(ld.get_tile(G, 0, 0), 2)
	assert_eq(ld.entities.size(), 2)
	assert_eq(ld.player_spawn, Vector2i(0, 2))

	# undo the spawn + one entity
	s.undo(ld)
	s.undo(ld)
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.player_spawn, Vector2i.ZERO)

	# redo one
	s.redo(ld)
	assert_eq(ld.entities.size(), 2)

	# serialize round-trip and confirm
	var path := "user://tests/test_editor_workflow.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded)
	assert_eq(loaded.get_tile(G, 0, 3), 1)
	assert_eq(loaded.entities.size(), 2)
	assert_eq(loaded.entities[0].type, "vorticon")
	assert_eq(loaded.entities[0].properties.get("speed"), 20)

func test_clear_then_re_register_entities_for_palette():
	# The editor palette depends on registry ordering; verify a fresh registration
	# set still sorts deterministically.
	EntityRegistry.clear()
	EntityRegistry.register("z", EntityRegistry.CATEGORY_ITEM, "Zed")
	EntityRegistry.register("a", EntityRegistry.CATEGORY_ITEM, "Ay")
	var entries := EntityRegistry.get_palette_entries()
	assert_eq(entries[0]["type_id"], "a")
	assert_eq(entries[1]["type_id"], "z")
