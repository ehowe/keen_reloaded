extends GutTest

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 2, 1)
	ld.set_geometry_tile(1, 2, 1)
	ld.set_foreground_tile(2, 0, 3)
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("candy", 3, 1))
	ld.entities.append(EntityDef.new("butler", 1, 0))
	return ld


func test_build_assembles_three_tile_layers():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_eq(rt.layers.size(), 3)
	assert_true(rt.layers.has(LevelData.LAYER_GEOMETRY))
	assert_true(rt.layers.has(LevelData.LAYER_FOREGROUND))
	assert_true(rt.layers.has(LevelData.LAYER_BACKGROUND))


func test_build_sets_geometry_cells():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 2)), Vector2i(0, 0), "tile id 1 -> atlas (0,0)")
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), -1, "empty cell has no source")


func test_build_spawns_player_and_entities():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	assert_not_null(rt.player, "player spawned")
	assert_true(rt.player.is_in_group("player"))
	var ts := lvl.tile_size
	assert_eq(rt.player.position, Vector2(lvl.player_spawn) * float(ts), "player at spawn")
	assert_eq(rt.entities_spawned.size(), lvl.entities.size(), "all entities spawned")
	assert_true(rt.entities_spawned[0].is_in_group("entity"), "entity in group")


func test_ready_auto_builds_from_pending_level():
	var lvl := _level()
	GameManager.pending_level = lvl
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	# _ready fired on add_child and should have built from pending_level.
	assert_eq(rt.layers.size(), 3)
	assert_not_null(rt.player)
	GameManager.pending_level = null


## A minimal real TileSet: 2 cols x 1 row, cell 16, one physics layer.
func _tileset_fixture() -> TileSet:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.3, 1))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	ts.add_physics_layer()
	return ts


func test_build_uses_tileset_ref_when_assigned():
	GameManager.pending_level = null
	var ts := _tileset_fixture()
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 2)  # tile id 2 -> atlas (1,0)
	ld.tileset_ref = ts
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_eq(rt.layers[LevelData.LAYER_GEOMETRY].tile_set, ts, "geometry uses the real TileSet")
	assert_eq(rt.layers[LevelData.LAYER_FOREGROUND].tile_set, ts, "foreground uses the real TileSet")
	assert_eq(rt.layers[LevelData.LAYER_BACKGROUND].tile_set, ts, "background uses the real TileSet")
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(1, 0), "id 2 -> atlas (1,0) via TileAtlas")
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), TileAtlas.SOURCE_ID, "source id 0")
	assert_true(ts.get_physics_layers_count() >= 1, "TileSet carries a physics (collision) layer")


func test_build_falls_back_to_procedural_when_tileset_ref_null():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 1)
	assert_null(ld.tileset_ref)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	# Procedural fallback: geometry TileSet is NOT the (null) tileset_ref; it's built.
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_not_null(geo.tile_set)
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(0, 0), "procedural id 1 -> (0,0)")
