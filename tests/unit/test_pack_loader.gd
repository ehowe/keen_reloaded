extends GutTest

const TMP_ROOT := "user://tmp_packtest/"

func before_each():
	PackLoader.root_dir = TMP_ROOT
	_clean(TMP_ROOT)

func after_each():
	_clean(TMP_ROOT)
	PackLoader.root_dir = "user://levelpacks/"

func _clean(path: String) -> void:
	PackLoader._remove_dir_recursive(path)

func _ow() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "ow"
	ld.level_name = "OW"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

func _lvl(id: String) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = id
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	return ld

const MANIFEST_VALID := """{
	"pack_id": "p1", "name": "Pack One", "author": "qa", "version": "1.0", "episode": "keen1",
	"levels": [
		{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0},
		{"level_id": "l1", "file": "01.tres", "name": "One", "order": 1}
	]
}"""

func _install(pack_id: String, manifest_text: String, files: Dictionary) -> void:
	var d := TMP_ROOT + pack_id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	var mf := FileAccess.open(d + "manifest.json", FileAccess.WRITE)
	mf.store_string(manifest_text)
	mf.close()
	for fname in files:
		var v = files[fname]
		if v is LevelData:
			assert_eq(ResourceSaver.save(v, d + fname), OK, "failed to save test level %s" % fname)
		else:
			var f := FileAccess.open(d + fname, FileAccess.WRITE)
			f.store_string(String(v))
			f.close()

func test_scan_finds_pack_with_overworld_and_levels():
	_install("p1", MANIFEST_VALID, {"overworld.tres": _ow(), "01.tres": _lvl("l1")})
	PackLoader.scan()
	assert_true(PackLoader.is_installed("p1"))
	assert_eq(PackLoader.get_pack("p1").pack_name, "Pack One")
	var levels := PackLoader.get_levels("p1")
	assert_eq(levels.size(), 2)
	var ow := PackLoader.get_overworld("p1")
	assert_not_null(ow)
	assert_eq(ow.map_kind, LevelData.MapKind.OVERWORLD)
	assert_eq(PackLoader.get_level("p1", "l1").level_id, "l1")
	assert_eq(PackLoader.get_packs().size(), 1)

func test_scan_missing_manifest_skipped():
	# A subdir with no manifest.json must not crash scan.
	DirAccess.make_dir_recursive_absolute(TMP_ROOT + "empty/")
	PackLoader.scan()
	assert_false(PackLoader.is_installed("empty"))
	assert_eq(PackLoader.get_packs().size(), 0)

func test_scan_malformed_manifest_skipped():
	_install("bad", "{ not json", {"overworld.tres": _ow()})
	PackLoader.scan()
	assert_false(PackLoader.is_installed("bad"))

func test_scan_no_overworld_rejected():
	var no_ow := """{
		"pack_id": "noow", "name": "NoOW", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "l1", "file": "01.tres", "name": "One", "order": 1}]
	}"""
	_install("noow", no_ow, {"01.tres": _lvl("l1")})
	PackLoader.scan()
	assert_false(PackLoader.is_installed("noow"))

func test_scan_multiple_overworlds_first_wins():
	var two_ow := """{
		"pack_id": "two", "name": "Two", "author": "qa", "version": "1.0",
		"levels": [
			{"level_id": "ow1", "file": "a.tres", "name": "A", "order": 0},
			{"level_id": "ow2", "file": "b.tres", "name": "B", "order": 1}
		]
	}"""
	var a := _ow()
	a.level_id = "ow1"
	var b := _ow()
	b.level_id = "ow2"
	_install("two", two_ow, {"a.tres": a, "b.tres": b})
	PackLoader.scan()
	assert_true(PackLoader.is_installed("two"))
	assert_eq(PackLoader.get_overworld("two").level_id, "ow1")

func test_scan_bad_level_file_skipped_but_pack_loads():
	var manifest := """{
		"pack_id": "p2", "name": "P2", "author": "qa", "version": "1.0",
		"levels": [
			{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0},
			{"level_id": "missing", "file": "ghost.tres", "name": "Ghost", "order": 1}
		]
	}"""
	_install("p2", manifest, {"overworld.tres": _ow()})
	PackLoader.scan()
	assert_true(PackLoader.is_installed("p2"))
	assert_eq(PackLoader.get_levels("p2").size(), 1, "missing level skipped")
	assert_null(PackLoader.get_level("p2", "missing"))
