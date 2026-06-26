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

func test_fill_blank_tiles():
	var ld := _make_level()
	ld.fill_blank()
	assert_eq(ld.geometry_tiles.size(), 12, "4x3 = 12 tiles")
	assert_eq(ld.geometry_tiles[0], TILE_EMPTY)
