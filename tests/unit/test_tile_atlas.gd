extends GutTest

## 4 cols x 2 rows, cell 16, margins (2,2), separation (1,1), 8 tiles.
## texture size = 4*16 + 2 + 3*1 = 69 wide, 2*16 + 2 + 1*1 = 35 tall.
func _fixture() -> TileSet:
	var img := Image.create(69, 35, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	src.margins = Vector2i(2, 2)
	src.separation = Vector2i(1, 1)
	ts.add_source(src)
	for i in range(8):
		src.create_tile(Vector2i(i % 4, i / 4))
	return ts


func test_columns_from_atlas_geometry():
	assert_eq(TileAtlas.columns(_fixture()), 4)


func test_rows_from_atlas_geometry():
	assert_eq(TileAtlas.rows(_fixture()), 2)


func test_tile_count_is_grid_size():
	assert_eq(TileAtlas.tile_count(_fixture()), 8)


func test_atlas_coords_row_major_with_wrap():
	var ts := _fixture()
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 1), Vector2i(0, 0))
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 4), Vector2i(3, 0), "end of row 1")
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 5), Vector2i(0, 1), "wraps to row 2")
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 8), Vector2i(3, 1))


func test_atlas_coords_invalid_ids():
	var ts := _fixture()
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 0), Vector2i(-1, -1))
	assert_eq(TileAtlas.atlas_coords_for_id(ts, -3), Vector2i(-1, -1))
	assert_eq(TileAtlas.atlas_coords_for_id(null, 1), Vector2i(-1, -1))


func test_tile_region_accounts_for_margins_and_separation():
	var ts := _fixture()
	# id 5 -> idx 4 -> coords (0,1): x = 2 + 0*(16+1) = 2, y = 2 + 1*(16+1) = 19
	assert_eq(TileAtlas.tile_region(ts, 5), Rect2(2, 19, 16, 16))
	# id 4 -> idx 3 -> coords (3,0): x = 2 + 3*(16+1) = 53, y = 2
	assert_eq(TileAtlas.tile_region(ts, 4), Rect2(53, 2, 16, 16))


func test_tile_icon_is_atlas_texture_with_region():
	var ts := _fixture()
	var icon: AtlasTexture = TileAtlas.tile_icon(ts, 5)
	assert_not_null(icon)
	assert_eq(icon.region, Rect2(2, 19, 16, 16))


func test_tile_icon_null_for_null_tileset():
	assert_null(TileAtlas.tile_icon(null, 1))


## Common real-world config: zero separation, single row -> columns == tile_count.
func test_zero_separation_single_row():
	var img := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	src.margins = Vector2i.ZERO
	src.separation = Vector2i.ZERO
	ts.add_source(src)
	for i in range(3):
		src.create_tile(Vector2i(i, 0))
	assert_eq(TileAtlas.columns(ts), 3)
	assert_eq(TileAtlas.rows(ts), 1)
	assert_eq(TileAtlas.tile_count(ts), 3)
