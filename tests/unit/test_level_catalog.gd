extends GutTest

const TMP := "user://tests/catalog/"

func before_each() -> void:
	_make_dir(TMP)


func after_each() -> void:
	_remove_dir(TMP)


func _make_level(id: String) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = id
	ld.level_name = id
	ld.episode = "keen1"
	ld.order = 1
	ld.width = 4
	ld.height = 4
	ld.fill_blank()
	return ld


func test_scan_returns_level_id_from_tres() -> void:
	var ld := _make_level("alpha")
	assert_eq(ResourceSaver.save(ld, TMP + "alpha.tres"), OK)
	var ids := LevelCatalog.scan_level_ids([TMP])
	assert_eq(ids, ["alpha"])


func test_scan_sorts_and_dedupes() -> void:
	assert_eq(ResourceSaver.save(_make_level("delta"), TMP + "d.tres"), OK)
	assert_eq(ResourceSaver.save(_make_level("beta"), TMP + "b.tres"), OK)
	# same id in two files → listed once
	assert_eq(ResourceSaver.save(_make_level("beta"), TMP + "b2.tres"), OK)
	var ids := LevelCatalog.scan_level_ids([TMP])
	assert_eq(ids, ["beta", "delta"])


func test_scan_descends_into_subdirs() -> void:
	_make_dir(TMP + "sub/")
	assert_eq(ResourceSaver.save(_make_level("gamma"), TMP + "sub/g.tres"), OK)
	var ids := LevelCatalog.scan_level_ids([TMP])
	assert_eq(ids, ["gamma"])


func test_scan_skips_non_level_resources() -> void:
	# A non-LevelData resource must not break the scan.
	var other := Resource.new()
	assert_eq(ResourceSaver.save(other, TMP + "junk.tres"), OK)
	assert_eq(ResourceSaver.save(_make_level("epsilon"), TMP + "e.tres"), OK)
	var ids := LevelCatalog.scan_level_ids([TMP])
	assert_eq(ids, ["epsilon"])


func test_scan_skips_empty_level_id() -> void:
	var ld := _make_level("")
	assert_eq(ResourceSaver.save(ld, TMP + "empty.tres"), OK)
	var ids := LevelCatalog.scan_level_ids([TMP])
	assert_eq(ids, [])


func test_scan_handles_missing_dir() -> void:
	# A non-existent directory is silently skipped (returns empty).
	var ids := LevelCatalog.scan_level_ids(["user://nonexistent_xyz/"])
	assert_eq(ids, [])


func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	_remove_recursive(path.get_base_dir(), path.get_file())
	DirAccess.remove_absolute(path)


func _remove_recursive(base: String, name: String) -> void:
	var full := base.path_join(name)
	var d := DirAccess.open(full + "/")
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			if d.dir_exists(n):
				_remove_recursive(full, n)
			else:
				d.remove(n)
		n = d.get_next()
	d.list_dir_end()
