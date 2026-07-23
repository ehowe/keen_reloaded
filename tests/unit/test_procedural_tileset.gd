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

func test_procedural_tileset_tags_ice_custom_data():
	# tile id 2 -> ICE1, tile id 3 -> ICE2, others NONE.
	var ts := ProceduralTileSet.build(4, 16, false, [2], [3])
	assert_eq(ts.get_custom_data_layers_count(), 1, "one custom-data layer added")
	var layer: int = ts.get_custom_data_layer_by_name("surface_type")
	assert_gte(layer, 0, "surface_type layer exists by name")
	var src: TileSetAtlasSource = ts.get_source(ts.get_source_id(0))
	# tile id 1 -> atlas coords (0,0); id 2 -> (1,0); id 3 -> (2,0).
	var td_normal: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	var td_ice1: TileData = src.get_tile_data(Vector2i(1, 0), 0)
	var td_ice2: TileData = src.get_tile_data(Vector2i(2, 0), 0)
	assert_eq(int(td_normal.get_custom_data("surface_type")), SurfaceType.Kind.NONE, "tile 1 normal")
	assert_eq(int(td_ice1.get_custom_data("surface_type")), SurfaceType.Kind.ICE1, "tile 2 ice1")
	assert_eq(int(td_ice2.get_custom_data("surface_type")), SurfaceType.Kind.ICE2, "tile 3 ice2")


func test_procedural_tileset_no_ice_ids_has_layer_all_none():
	# Backward-compat: even with no ice ids, a surface_type layer exists and
	# every tile reads NONE (so the player contract is uniform).
	var ts := ProceduralTileSet.build(3, 16, true, [], [])
	var src: TileSetAtlasSource = ts.get_source(ts.get_source_id(0))
	for x in 3:
		var td: TileData = src.get_tile_data(Vector2i(x, 0), 0)
		assert_eq(int(td.get_custom_data("surface_type")), SurfaceType.Kind.NONE, "tile %d is NONE" % (x + 1))
