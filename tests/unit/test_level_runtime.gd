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
	ld.entities.append(EntityDef.new("keen1.lollipop", 3, 1))
	ld.entities.append(EntityDef.new("keen1.butler", 1, 0))
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
	assert_eq(rt.player.position, Vector2(lvl.player_spawn.x * ts + ts / 2.0, lvl.player_spawn.y * ts + ts / 2.0), "player at spawn cell center")
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
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), TileAtlas.source_id(ts), "source id resolved by index")
	assert_true(ts.get_physics_layers_count() >= 1, "TileSet carries a physics (collision) layer")


func test_build_creates_perimeter_bounds():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	# 3 solid walls (left/right/top), 1 kill zone (bottom) — found by name prefix
	# so unrelated entity nodes don't pollute the count.
	var walls := rt.find_children("BoundsWall*", "StaticBody2D", true, false)
	var kill_zones := rt.find_children("BoundsKillZone*", "Area2D", true, false)
	assert_eq(walls.size(), 3, "three perimeter walls")
	assert_eq(kill_zones.size(), 1, "one bottom kill zone")
	# Walls must sit on the tiles collision layer (4) so the player (mask 4) hits them.
	for w in walls:
		assert_eq(w.collision_layer, 4, "wall on tiles layer")
	# Kill zone must monitor the player layer (1).
	assert_eq(kill_zones[0].collision_mask, 1, "kill zone detects player")


func test_build_clamps_camera_to_map_bounds():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	var cam := rt.player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(cam, "player has a camera")
	var ts := lvl.tile_size
	assert_eq(cam.limit_left, 0, "left clamped to map origin")
	assert_eq(cam.limit_top, 0, "top clamped to map origin")
	assert_eq(cam.limit_right, lvl.width * ts, "right clamped to map width")
	assert_eq(cam.limit_bottom, lvl.height * ts, "bottom clamped to map height")


## Two-source TileSet: source 0 = 2x1, source 1 = 2x1 (16px cells).
func _two_source_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img0 := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img0.fill(Color(0.2, 0.7, 0.3, 1))
	var s0 := TileSetAtlasSource.new()
	s0.texture = ImageTexture.create_from_image(img0)
	s0.texture_region_size = Vector2i(16, 16)
	ts.add_source(s0)
	s0.create_tile(Vector2i(0, 0))
	s0.create_tile(Vector2i(1, 0))
	var img1 := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img1.fill(Color(0.7, 0.2, 0.3, 1))
	var s1 := TileSetAtlasSource.new()
	s1.texture = ImageTexture.create_from_image(img1)
	s1.texture_region_size = Vector2i(16, 16)
	ts.add_source(s1)
	s1.create_tile(Vector2i(0, 0))
	s1.create_tile(Vector2i(1, 0))
	return ts


func test_build_renders_second_source_cell():
	GameManager.pending_level = null
	var ts := _two_source_tileset()
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	# source 1, cell idx 1 -> atlas (1, 0)
	ld.set_geometry_tile(0, 0, TileAtlas.SOURCE_STRIDE + 2)
	ld.tileset_ref = ts
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), ts.get_source_id(1), "cell resolves to source 1")
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(1, 0), "source-1 cell coords")


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
