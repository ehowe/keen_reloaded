extends GutTest

func test_level_matches_manifest_entry():
	# Build and save a level as a pack would expect.
	var ld := LevelData.new()
	ld.level_id = "keen1_01"
	ld.level_name = "Border Village"
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 8
	ld.height = 4
	ld.fill_blank()
	ld.set_geometry_tile(0, 3, 1)
	ld.player_spawn = Vector2i(1, 2)
	ld.entities.append(EntityDef.new("vorticon", 5, 1))

	var dir := "user://tests/integration/"
	DirAccess.make_dir_recursive_absolute(dir)
	var level_path := dir + "keen1_01.tres"
	assert_eq(ResourceSaver.save(ld, level_path), OK)

	# A manifest that references it.
	var manifest_text := """{
		"pack_id": "keen1", "name": "Keen 1", "author": "me", "version": "1.0",
		"levels": [{"level_id": "keen1_01", "file": "keen1_01.tres", "name": "Border Village", "order": 1}]
	}"""
	var pack := LevelPack.from_json(manifest_text)
	assert_not_null(pack)
	assert_eq(pack.levels.size(), 1)

	# Load the level the manifest points to and confirm id matches.
	var entry: Dictionary = pack.levels[0]
	var loaded := ResourceLoader.load(level_path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	assert_not_null(loaded)
	assert_eq(loaded.level_id, entry["level_id"])
	assert_eq(loaded.entities.size(), 1)
