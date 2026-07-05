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


## Two-source fixture: source 0 = 4x1, source 1 = 3x1 (all 16px, no margin/sep).
func _multi_fixture() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img0 := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	img0.fill(Color(1, 0, 0, 1))
	var s0 := TileSetAtlasSource.new()
	s0.texture = ImageTexture.create_from_image(img0)
	s0.texture_region_size = Vector2i(16, 16)
	ts.add_source(s0)
	for i in range(4):
		s0.create_tile(Vector2i(i, 0))
	var img1 := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	img1.fill(Color(0, 1, 0, 1))
	var s1 := TileSetAtlasSource.new()
	s1.texture = ImageTexture.create_from_image(img1)
	s1.texture_region_size = Vector2i(16, 16)
	ts.add_source(s1)
	for i in range(3):
		s1.create_tile(Vector2i(i, 0))
	return ts


func test_source_count():
	assert_eq(TileAtlas.source_count(_multi_fixture()), 2)
	assert_eq(TileAtlas.source_count(null), 0)


func test_source_index_for_id_packs_stride():
	assert_eq(TileAtlas.source_index_for_id(0), -1, "empty id has no source")
	assert_eq(TileAtlas.source_index_for_id(1), 0)
	assert_eq(TileAtlas.source_index_for_id(TileAtlas.SOURCE_STRIDE), 0, "last source-0 id")
	assert_eq(TileAtlas.source_index_for_id(TileAtlas.SOURCE_STRIDE + 1), 1, "first source-1 id")


func test_source_id_for_id_resolves_each_source():
	var ts := _multi_fixture()
	assert_eq(TileAtlas.source_id_for_id(ts, 1), ts.get_source_id(0))
	assert_eq(TileAtlas.source_id_for_id(ts, TileAtlas.SOURCE_STRIDE + 1), ts.get_source_id(1))
	assert_eq(TileAtlas.source_id_for_id(ts, 2 * TileAtlas.SOURCE_STRIDE + 1), -1, "no source 2")


func test_atlas_coords_for_second_source():
	var ts := _multi_fixture()
	# source 1 is 3 wide; cell idx 2 -> (2, 0)
	assert_eq(TileAtlas.atlas_coords_for_id(ts, TileAtlas.SOURCE_STRIDE + 3), Vector2i(2, 0))
	# source 0 still resolves via the primary path.
	assert_eq(TileAtlas.atlas_coords_for_id(ts, 4), Vector2i(3, 0))


func test_tile_count_total_sums_all_sources():
	assert_eq(TileAtlas.tile_count_total(_multi_fixture()), 7)
	assert_eq(TileAtlas.tile_count_total(null), 0)


func test_all_tile_ids_lists_every_source_contiguously():
	var ids := TileAtlas.all_tile_ids(_multi_fixture())
	assert_eq(ids.size(), 7)
	assert_eq(ids[0], 1, "source 0 starts at 1")
	assert_eq(ids[3], 4, "source 0 ends at 4")
	assert_eq(ids[4], TileAtlas.SOURCE_STRIDE + 1, "source 1 starts after stride")


func test_tile_icon_uses_second_source_texture():
	var ts := _multi_fixture()
	var icon: AtlasTexture = TileAtlas.tile_icon(ts, TileAtlas.SOURCE_STRIDE + 1)
	assert_not_null(icon)
	# source 1, cell (0,0), no margin/sep -> Rect2(0,0,16,16)
	assert_eq(icon.region, Rect2(0, 0, 16, 16))


func test_id_for_coords_roundtrips():
	var ts := _multi_fixture()
	var id := TileAtlas.id_for_coords(1, 2, 0, 3)
	assert_eq(id, TileAtlas.SOURCE_STRIDE + 3)
	assert_eq(TileAtlas.atlas_coords_for_id(ts, id), Vector2i(2, 0))


func test_tile_ids_for_one_source():
	var ts := _multi_fixture()
	var ids0 := TileAtlas.tile_ids_for_source(ts, 0)
	assert_eq(ids0.size(), 4)
	assert_eq(ids0[0], 1)
	var ids1 := TileAtlas.tile_ids_for_source(ts, 1)
	assert_eq(ids1.size(), 3)
	assert_eq(ids1[0], TileAtlas.SOURCE_STRIDE + 1, "source 1 ids start after stride")
	assert_eq(TileAtlas.tile_ids_for_source(ts, 99), [], "missing source -> empty")


func test_source_name_uses_authored_name_with_fallback():
	var ts := _multi_fixture()
	assert_eq(TileAtlas.source_name(ts, 0), "Source 0", "unnamed -> fallback")
	var src1 := ts.get_source(ts.get_source_id(1))
	src1.resource_name = "Blocks"
	assert_eq(TileAtlas.source_name(ts, 1), "Blocks")
	assert_eq(TileAtlas.source_name(ts, 99), "", "missing source -> empty")
