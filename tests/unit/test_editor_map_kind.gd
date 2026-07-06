extends GutTest

func after_each():
	GameManager.register_episodes()

func _make_editor() -> LevelEditor:
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()  # builds blank level + UI
	return ed

func test_inspector_writes_map_kind():
	var ed := _make_editor()
	ed.level.map_kind = LevelData.MapKind.LEVEL
	ed._inspector.refresh(ed)
	var picker: OptionButton = ed._inspector.find_child("MapKindPicker", true, false)
	assert_not_null(picker)
	picker.select(int(LevelData.MapKind.OVERWORLD))
	picker.item_selected.emit(int(LevelData.MapKind.OVERWORLD))
	assert_eq(ed.level.map_kind, LevelData.MapKind.OVERWORLD)

func test_inspector_reflects_map_kind():
	var ed := _make_editor()
	ed.level.map_kind = LevelData.MapKind.OVERWORLD
	ed._inspector.refresh(ed)
	var picker: OptionButton = ed._inspector.find_child("MapKindPicker", true, false)
	assert_eq(picker.selected, int(LevelData.MapKind.OVERWORLD))


func test_palette_filters_by_map_kind():
	# keen1 entities are registered at autoload boot (GameManager.register_episodes).
	var ed_level := LevelEditor.new()
	add_child_autofree(ed_level)
	ed_level._ready()
	ed_level.level.map_kind = LevelData.MapKind.LEVEL
	ed_level._palette.refresh(ed_level)
	var level_ids := ed_level._palette.get_entity_ids_for_test()
	assert_true(level_ids.has("keen1.vorticon"), "level palette shows gameplay entities")
	assert_false(level_ids.has("keen1.level_entrance"), "level palette hides overworld-only entrance")

	ed_level.level.map_kind = LevelData.MapKind.OVERWORLD
	ed_level._palette.refresh(ed_level)
	var ow_ids := ed_level._palette.get_entity_ids_for_test()
	assert_true(ow_ids.has("keen1.level_entrance"), "overworld palette shows the entrance")
	assert_false(ow_ids.has("keen1.vorticon"), "overworld palette hides gameplay entities")
