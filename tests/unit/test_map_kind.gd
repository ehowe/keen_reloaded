extends GutTest

func test_map_kind_enum_exists():
	assert_eq(LevelData.MapKind.LEVEL, 0)
	assert_eq(LevelData.MapKind.OVERWORLD, 1)

func test_default_map_kind_is_level():
	var ld := LevelData.new()
	assert_eq(ld.map_kind, LevelData.MapKind.LEVEL)

func test_map_kind_round_trip():
	var ld := LevelData.new()
	ld.level_id = "ow1"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	var path := "user://tests/test_map_kind.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	assert_eq(ResourceSaver.save(ld, path), OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded)
	assert_eq(loaded.map_kind, LevelData.MapKind.OVERWORLD)

func test_overworld_build_has_no_kill_zone():
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_null(rt.find_child("BoundsKillZone", true, false),
		"overworld must not add a kill zone")

func test_level_build_has_kill_zone():
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.LEVEL
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_not_null(rt.find_child("BoundsKillZone", true, false),
		"level keeps the kill zone")
