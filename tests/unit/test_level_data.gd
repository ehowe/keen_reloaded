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
	assert_eq(ld.tile_size, 16)
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
