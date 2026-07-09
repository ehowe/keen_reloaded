extends GutTest

const TMP_ROOT := "user://tmp_importtest/"

func before_each():
	PackLoader.root_dir = TMP_ROOT
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader.scan()

func after_each():
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader._remove_dir_recursive(PackLoader.TMP_IMPORT)
	PackLoader.root_dir = "user://levelpacks/"
	_clean_res_tmp()

func _clean_res_tmp() -> void:
	for f in ["tmp_zip_ow.tres", "tmp_zip_l1.tres"]:
		var p: String = "res://tests/" + f
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _make_level(lid: String, is_ow: bool) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = lid
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	if is_ow:
		ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

const MANIFEST := """{
	"pack_id": "ztest", "name": "Zip Test", "author": "qa", "version": "1.0", "episode": "keen1",
	"levels": [
		{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0},
		{"level_id": "l1", "file": "01.tres", "name": "One", "order": 1}
	]
}"""

## Build a zip at zip_path from { relpath: PackedByteArray }.
func _make_zip(zip_path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	assert_eq(packer.open(zip_path), OK)
	for path in entries:
		assert_eq(packer.start_file(path), OK)
		assert_eq(packer.write_file(entries[path]), OK)
		packer.close_file()
	packer.close()

func _valid_entries() -> Dictionary:
	var e: Dictionary = {}
	e["manifest.json"] = MANIFEST.to_utf8_buffer()
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["overworld.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	var l1 := _make_level("l1", false)
	ResourceSaver.save(l1, "res://tests/tmp_zip_l1.tres")
	e["01.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_l1.tres")
	return e

func test_import_zip_valid_pack():
	var zip_path := "user://tmp_valid.zip"
	_make_zip(zip_path, _valid_entries())
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_true(r.ok, "import should succeed: %s" % r.error)
	assert_eq(r.pack_id, "ztest")
	assert_true(PackLoader.is_installed("ztest"))
	var ow := PackLoader.get_overworld("ztest")
	assert_not_null(ow)
	assert_eq(ow.map_kind, LevelData.MapKind.OVERWORLD)
	assert_eq(PackLoader.get_levels("ztest").size(), 2)

func test_import_zip_rejects_traversal():
	var zip_path := "user://tmp_trav.zip"
	_make_zip(zip_path, {"../evil.tres": "x".to_utf8_buffer()})
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)
	assert_eq(PackLoader.get_packs().size(), 0, "nothing installed")

func test_import_zip_rejects_absolute_path():
	var zip_path := "user://tmp_abs.zip"
	_make_zip(zip_path, {"res://hack.tres": "x".to_utf8_buffer()})
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)

func test_import_zip_rejects_disallowed_type():
	var zip_path := "user://tmp_type.zip"
	_make_zip(zip_path, {"hack.gd": "extends Node".to_utf8_buffer()})
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)

func test_import_zip_rejects_no_manifest():
	var zip_path := "user://tmp_noman.zip"
	var e: Dictionary = {}
	# only a level, no manifest
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["overworld.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	_make_zip(zip_path, e)
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok)
	assert_eq(r.error, "no manifest.json")

func test_import_zip_reimport_overwrites():
	var zip_path := "user://tmp_re.zip"
	_make_zip(zip_path, _valid_entries())
	assert_true(PackLoader.import_zip(zip_path).ok)
	# import again — must overwrite cleanly, still exactly one pack
	var r2: Dictionary = PackLoader.import_zip(zip_path)
	assert_true(r2.ok)
	assert_eq(r2.pack_id, "ztest")
	assert_eq(PackLoader.get_packs().size(), 1)

func test_import_zip_rejects_traversal_pack_id():
	# Manifest pack_id "../evil" must NOT escape root_dir (C1 regression).
	var manifest := """{
		"pack_id": "../evil", "name": "Evil", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}]
	}"""
	var e: Dictionary = {}
	e["manifest.json"] = manifest.to_utf8_buffer()
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["overworld.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	var zip_path := "user://tmp_evilid.zip"
	_make_zip(zip_path, e)
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_false(r.ok, "traversal pack_id must be rejected")
	assert_eq(r.error, "invalid pack_id")
	# nothing must have been created outside the temp root
	assert_false(DirAccess.dir_exists_absolute("user://evil"), "no escape dir created")

func test_import_zip_allows_uppercase_extension():
	# .TRES must pass the case-insensitive allowlist and import successfully.
	var manifest := """{
		"pack_id": "upper", "name": "Upper", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "ow", "file": "overworld.TRES", "name": "OW", "order": 0}]
	}"""
	var e: Dictionary = {}
	e["manifest.json"] = manifest.to_utf8_buffer()
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["overworld.TRES"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	var zip_path := "user://tmp_upper.zip"
	_make_zip(zip_path, e)
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_true(r.ok, "uppercase .TRES should import: %s" % r.error)
	assert_eq(r.pack_id, "upper")

func test_import_zip_handles_nested_directory_entry():
	# A zip with a nested path extracts into the right subdir.
	var manifest := """{
		"pack_id": "nested", "name": "Nested", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "ow", "file": "data/overworld.tres", "name": "OW", "order": 0}]
	}"""
	var e: Dictionary = {}
	e["manifest.json"] = manifest.to_utf8_buffer()
	var ow := _make_level("ow", true)
	ResourceSaver.save(ow, "res://tests/tmp_zip_ow.tres")
	e["data/overworld.tres"] = FileAccess.get_file_as_bytes("res://tests/tmp_zip_ow.tres")
	var zip_path := "user://tmp_nested.zip"
	_make_zip(zip_path, e)
	var r: Dictionary = PackLoader.import_zip(zip_path)
	assert_true(r.ok, "nested entry should import: %s" % r.error)
	assert_eq(r.pack_id, "nested")
	assert_not_null(PackLoader.get_overworld("nested"))
