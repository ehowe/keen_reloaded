extends GutTest

const TILE_EMPTY := 0
const TILE_SOLID := 1

func _make_level() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "keen1_01"
	ld.level_name = "Border Village"
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	return ld

func test_default_construction():
	var ld := LevelData.new()
	assert_eq(ld.level_id, "")
	assert_eq(ld.width, 0)
	assert_eq(ld.height, 0)
	assert_eq(ld.tile_size, 64)
	assert_eq(ld.geometry_tiles.size(), 0)
	assert_eq(ld.entities.size(), 0)
	assert_eq(ld.player_spawn, Vector2i.ZERO)

func test_tile_index_helpers():
	var ld := _make_level()
	# tile_at for (0,0) = index 0; (3,2) = index 3 + 2*4 = 11
	assert_eq(ld.tile_index_at(0, 0), 0)
	assert_eq(ld.tile_index_at(3, 2), 11)
	# out of bounds returns -1
	assert_eq(ld.tile_index_at(4, 0), -1)
	assert_eq(ld.tile_index_at(0, 3), -1)
	# negative coords return -1
	assert_eq(ld.tile_index_at(-1, 0), -1)
	assert_eq(ld.tile_index_at(0, -1), -1)

func test_fill_blank_tiles():
	var ld := _make_level()
	ld.fill_blank()
	assert_eq(ld.geometry_tiles.size(), 12, "4x3 = 12 tiles")
	assert_eq(ld.foreground_tiles.size(), 12)
	assert_eq(ld.background_tiles.size(), 12)
	# every element across all 3 layers must be 0
	for i in range(12):
		assert_eq(ld.geometry_tiles[i], TILE_EMPTY)
		assert_eq(ld.foreground_tiles[i], TILE_EMPTY)
		assert_eq(ld.background_tiles[i], TILE_EMPTY)

func test_set_get_geometry_tile():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_geometry_tile(2, 1, 1)
	assert_eq(ld.get_geometry_tile(2, 1), 1)
	assert_eq(ld.get_geometry_tile(0, 0), 0)

func test_set_tile_out_of_bounds_is_ignored():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_geometry_tile(99, 99, 1)
	assert_eq(ld.get_geometry_tile(99, 99), 0, "out-of-bounds get returns 0")

func test_serialization_round_trip():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_geometry_tile(1, 0, 1)
	ld.set_geometry_tile(0, 2, 1)
	ld.player_spawn = Vector2i(1, 1)
	ld.exit_type = "door"
	ld.exit_position = Vector2i(3, 2)
	ld.exit_target_level_id = "keen1_02"
	ld.entities.append(EntityDef.new("vorticon", 2, 1, {"speed": 25}))

	var path := "user://tests/test_level_data.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	var err := ResourceSaver.save(ld, path)
	assert_eq(err, OK, "save should return OK")

	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded, "loaded should not be null")
	assert_eq(loaded.level_id, "keen1_01")
	assert_eq(loaded.width, 4)
	assert_eq(loaded.height, 3)
	assert_eq(loaded.get_geometry_tile(1, 0), 1)
	assert_eq(loaded.get_geometry_tile(0, 2), 1)
	assert_eq(loaded.player_spawn, Vector2i(1, 1))
	assert_eq(loaded.exit_target_level_id, "keen1_02")
	assert_eq(loaded.entities.size(), 1)
	assert_eq(loaded.entities[0].type, "vorticon")
	assert_eq(loaded.entities[0].properties.get("speed"), 25)

func test_set_get_foreground_tile():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_foreground_tile(1, 1, 5)
	assert_eq(ld.get_foreground_tile(1, 1), 5)
	assert_eq(ld.get_foreground_tile(0, 0), 0)
	# out of bounds returns 0
	assert_eq(ld.get_foreground_tile(-1, 0), 0)

func test_set_get_background_tile():
	var ld := _make_level()
	ld.fill_blank()
	ld.set_background_tile(2, 0, 7)
	assert_eq(ld.get_background_tile(2, 0), 7)
	assert_eq(ld.get_background_tile(0, 0), 0)
	# out of bounds set is ignored (value unchanged)
	ld.set_background_tile(99, 99, 1)
	assert_eq(ld.get_background_tile(99, 99), 0)

# --- resize: rows added/removed at TOP, cols at RIGHT; bottom-left anchored ---

func test_resize_grow_height_adds_rows_at_top():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 7)  # top-left
	ld.set_geometry_tile(0, 2, 9)  # bottom-left
	ld.resize(4, 5)  # delta_h = +2
	assert_eq(ld.width, 4)
	assert_eq(ld.height, 5)
	assert_eq(ld.geometry_tiles.size(), 20)
	# new top rows blank
	assert_eq(ld.get_geometry_tile(0, 0), 0)
	assert_eq(ld.get_geometry_tile(0, 1), 0)
	# old top-left shifted down by 2 -> now y2
	assert_eq(ld.get_geometry_tile(0, 2), 7)
	# bottom-left stays bottom
	assert_eq(ld.get_geometry_tile(0, 4), 9)

func test_resize_shrink_height_removes_top_rows():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	for x in range(4):
		ld.set_geometry_tile(x, 0, 1)  # top row
		ld.set_geometry_tile(x, 1, 2)  # mid
		ld.set_geometry_tile(x, 2, 3)  # bottom
	ld.resize(4, 2)  # delta_h = -1, top row dropped
	assert_eq(ld.height, 2)
	# new y0 = old mid (2), new y1 = old bottom (3)
	for x in range(4):
		assert_eq(ld.get_geometry_tile(x, 0), 2)
		assert_eq(ld.get_geometry_tile(x, 1), 3)

func test_resize_grow_width_adds_cols_at_right():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 5)
	ld.resize(6, 3)
	assert_eq(ld.width, 6)
	assert_eq(ld.geometry_tiles.size(), 18)
	assert_eq(ld.get_geometry_tile(0, 0), 5, "left col preserved in place")
	assert_eq(ld.get_geometry_tile(4, 0), 0, "new right col blank")
	assert_eq(ld.get_geometry_tile(5, 0), 0)

func test_resize_shrink_width_removes_right_cols():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 5)
	ld.set_geometry_tile(3, 0, 8)  # rightmost col
	ld.resize(2, 3)
	assert_eq(ld.width, 2)
	assert_eq(ld.get_geometry_tile(0, 0), 5)
	assert_eq(ld.get_geometry_tile(3, 0), 0, "removed col reads 0")

func test_resize_preserves_all_layers():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.set_tile(LevelData.LAYER_GEOMETRY, 1, 1, 1)
	ld.set_tile(LevelData.LAYER_FOREGROUND, 1, 1, 2)
	ld.set_tile(LevelData.LAYER_BACKGROUND, 1, 1, 3)
	ld.resize(4, 5)  # delta_h = +2 -> old (1,1) -> new (1,3)
	assert_eq(ld.get_tile(LevelData.LAYER_GEOMETRY, 1, 3), 1)
	assert_eq(ld.get_tile(LevelData.LAYER_FOREGROUND, 1, 3), 2)
	assert_eq(ld.get_tile(LevelData.LAYER_BACKGROUND, 1, 3), 3)

func test_resize_shifts_entities_and_spawn():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.entities.append(EntityDef.new("vorticon", 1, 1))
	ld.player_spawn = Vector2i(0, 0)
	ld.resize(4, 5)  # delta_h = +2
	assert_eq(ld.entities[0].y, 3, "entity pushed down by delta")
	assert_eq(ld.entities[0].x, 1)
	assert_eq(ld.player_spawn, Vector2i(0, 2), "spawn pushed down")

func test_resize_shrink_drops_entities_in_removed_rows():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.entities.append(EntityDef.new("a", 0, 0))  # top row -> removed
	ld.entities.append(EntityDef.new("b", 0, 2))  # bottom -> kept, shifts to y1
	ld.resize(4, 2)  # delta_h = -1
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].type, "b")
	assert_eq(ld.entities[0].y, 1)

func test_resize_shrink_width_drops_entities_in_removed_cols():
	var ld := _make_level()  # 4x3
	ld.fill_blank()
	ld.entities.append(EntityDef.new("a", 3, 0))  # rightmost col -> removed
	ld.entities.append(EntityDef.new("b", 0, 0))  # kept
	ld.resize(2, 3)
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].type, "b")
