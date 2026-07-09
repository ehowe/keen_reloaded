extends GutTest

const PACK_SELECT := preload("res://src/ui/pack_select.tscn")
const TMP_ROOT := "user://tmp_ps_ui/"

func before_each():
	PackLoader.root_dir = TMP_ROOT
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader.scan()

func after_each():
	PackLoader._remove_dir_recursive(TMP_ROOT)
	PackLoader.root_dir = "user://levelpacks/"

func _ow() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "ow"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

func _install_pack(pack_id: String) -> void:
	var d := TMP_ROOT + pack_id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	ResourceSaver.save(_ow(), d + "overworld.tres")
	var manifest := """{
		"pack_id": "%s", "name": "UI Pack", "author": "qa", "version": "1.0",
		"levels": [{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}]
	}""" % pack_id
	var mf := FileAccess.open(d + "manifest.json", FileAccess.WRITE)
	mf.store_string(manifest)
	mf.close()

func test_empty_state_message():
	var ps := PACK_SELECT.instantiate()
	add_child(ps)
	assert_eq(ps.list.get_item_count(), 1)
	assert(ps.list.get_item_text(0).find("No packs") >= 0)
	ps.queue_free()

func test_repopulate_lists_installed_pack():
	_install_pack("uip1")
	PackLoader.scan()
	var ps := PACK_SELECT.instantiate()
	add_child(ps)
	assert_eq(ps.list.get_item_count(), 1)
	assert(ps.list.get_item_text(0).find("UI Pack") >= 0)
	ps.queue_free()
