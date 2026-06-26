extends GutTest

func _make_level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 3
	ld.height = 2
	ld.fill_blank()
	return ld

func test_layer_name_constants_exist():
	assert_eq(LevelData.LAYER_GEOMETRY, "geometry")
	assert_eq(LevelData.LAYER_FOREGROUND, "foreground")
	assert_eq(LevelData.LAYER_BACKGROUND, "background")

func test_get_tile_and_set_tile_geometry():
	var ld := _make_level()
	ld.set_tile(LevelData.LAYER_GEOMETRY, 1, 0, 7)
	assert_eq(ld.get_tile(LevelData.LAYER_GEOMETRY, 1, 0), 7)
	assert_eq(ld.get_geometry_tile(1, 0), 7, "generic setter writes the same backing array")

func test_get_tile_and_set_tile_foreground():
	var ld := _make_level()
	ld.set_tile(LevelData.LAYER_FOREGROUND, 2, 1, 5)
	assert_eq(ld.get_tile(LevelData.LAYER_FOREGROUND, 2, 1), 5)
	assert_eq(ld.get_foreground_tile(2, 1), 5)

func test_get_tile_and_set_tile_background():
	var ld := _make_level()
	ld.set_tile(LevelData.LAYER_BACKGROUND, 0, 0, 9)
	assert_eq(ld.get_tile(LevelData.LAYER_BACKGROUND, 0, 0), 9)
	assert_eq(ld.get_background_tile(0, 0), 9)

func test_unknown_layer_get_returns_zero():
	var ld := _make_level()
	assert_eq(ld.get_tile("nope", 0, 0), 0)

func test_out_of_bounds_get_returns_zero():
	var ld := _make_level()
	assert_eq(ld.get_tile(LevelData.LAYER_GEOMETRY, 99, 99), 0)
