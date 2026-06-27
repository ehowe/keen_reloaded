extends GutTest

func test_solid_tileset_has_tiles_and_collision():
	var ts: TileSet = ProceduralTileSet.build(4, 16, true)
	assert_eq(ts.tile_size, Vector2i(16, 16))
	assert_eq(ts.get_source_count(), 1, "one atlas source")
	var src: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 4, "4 tiles for ids 1..4")
	assert_eq(ts.get_physics_layers_count(), 1, "solid has 1 physics layer")
	assert_eq(ts.get_physics_layer_collision_layer(0), 4, "tiles collision layer bit")
	assert_eq(ts.get_physics_layer_collision_mask(0), 1, "player collision mask bit")
	var td: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	assert_eq(td.get_collision_polygon_points(0, 0).size(), 4, "tile 1 has a 4-pt collision rect")

func test_decor_tileset_has_no_collision():
	var ts: TileSet = ProceduralTileSet.build(3, 16, false)
	var src: TileSetAtlasSource = ts.get_source(0) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 3)
	assert_eq(ts.get_physics_layers_count(), 0, "decor has no physics layer")

func test_max_id_zero_returns_empty_tileset():
	var ts: TileSet = ProceduralTileSet.build(0, 16, true)
	assert_eq(ts.get_source_count(), 0)
	assert_eq(ts.get_physics_layers_count(), 0)
