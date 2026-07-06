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


func test_inspector_edits_string_and_bool_props():
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	var def := EntityDef.new("keen1.level_entrance", 1, 1,
		{"target_level_id": "lvl1", "blocks_until_completed": true})
	ed.level.entities.append(def)
	ed.select_entity(ed.level.entities.size() - 1)
	# Find the LineEdit for target_level_id and change it.
	var le: LineEdit = ed._inspector.find_child("Prop_target_level_id", true, false)
	assert_not_null(le, "String property should render as a LineEdit")
	le.text = "lvl2"
	le.text_changed.emit("lvl2")
	assert_eq(def.properties["target_level_id"], "lvl2")
	# Find the CheckBox for blocks_until_completed and toggle it.
	var cb: CheckBox = ed._inspector.find_child("Prop_blocks_until_completed", true, false)
	assert_not_null(cb, "Bool property should render as a CheckBox")
	cb.set_pressed_no_signal(false)
	cb.toggled.emit(false)
	assert_eq(def.properties["blocks_until_completed"], false)
