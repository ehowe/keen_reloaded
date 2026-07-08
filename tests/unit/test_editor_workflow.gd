extends GutTest

const G := "geometry"

func before_each():
	# Each editor-memory test must start with no leftover cfg on disk.
	DirAccess.remove_absolute("user://editor.cfg")

func after_each():
	# Restore the autoload's default roster so clearing here doesn't leak an
	# empty registry into later test scripts (e.g. test_level_runtime).
	GameManager.register_episodes()

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

func test_remember_then_recall_path_round_trips():
	var ed := LevelEditor.new()
	ed._remember_path("user://tests/some_level.tres")
	assert_eq(ed._recall_path(), "user://tests/some_level.tres")


func test_recall_with_no_config_returns_empty():
	var ed := LevelEditor.new()
	assert_eq(ed._recall_path(), "")


func test_load_from_path_loads_valid_level_and_sets_last_path():
	var ld := _level()
	var path := "user://tests/test_remember_load.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_true(ed._load_from_path(path))
	assert_not_null(ed.level)
	assert_eq(ed._last_path, path)


func test_load_from_path_returns_false_for_missing_file():
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_false(ed._load_from_path("user://tests/does_not_exist_12345.tres"))
	assert_null(ed.level)


func test_load_from_path_returns_false_for_non_leveldata():
	var path := "user://tests/test_remember_notlevel.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	# A real, savable resource that is NOT a LevelData (Gradient). Loading it and
	# casting `as LevelData` yields null without emitting engine errors.
	var r := Gradient.new()
	assert_eq(ResourceSaver.save(r, path), OK)
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_false(ed._load_from_path(path))


func test_try_reopen_last_returns_false_with_no_memory():
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	assert_false(ed._try_reopen_last())
	assert_null(ed.level)


func test_try_reopen_last_opens_remembered_valid_file():
	var ld := _level()
	var path := "user://tests/test_remember_reopen.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	ed._remember_path(path)
	assert_true(ed._try_reopen_last())
	assert_not_null(ed.level)
	assert_eq(ed._last_path, path)


func test_try_reopen_last_falls_back_when_file_missing():
	var ed := LevelEditor.new()
	ed.undo_stack = UndoStack.new()
	ed._remember_path("user://tests/gone_12345.tres")
	assert_false(ed._try_reopen_last())
	assert_null(ed.level)

func test_place_entity_seeds_schema_defaults():
	# A registered type with an enum schema should place with the default
	# written into EntityDef.properties (self-describing data).
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	ed.selected_entity_type = "keen1.spike"
	ed._place_entity(Vector2i(3, 4))
	assert_eq(ed.level.entities.size(), 1)
	var def: EntityDef = ed.level.entities[0]
	assert_eq(def.x, 3)
	assert_eq(def.y, 4)
	assert_eq(def.properties.get("facing"), "right", "schema default seeded on placement")

func test_place_entity_empty_schema_yields_empty_props():
	# A schemaless type places with an empty properties dict (unchanged).
	EntityRegistry.clear()
	EntityRegistry.register("keen1.vorticon", EntityRegistry.CATEGORY_ENEMY, "Vorticon")
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	ed.selected_entity_type = "keen1.vorticon"
	ed._place_entity(Vector2i(1, 2))
	assert_eq(ed.level.entities.size(), 1)
	assert_eq(ed.level.entities[0].properties, {}, "no schema -> empty props")
