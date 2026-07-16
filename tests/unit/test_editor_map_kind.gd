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
	assert_true(level_ids.has("keen1.player_spawn"), "level palette shows player spawn")
	assert_false(level_ids.has("keen1.level_entrance"), "level palette hides overworld-only entrance")

	ed_level.level.map_kind = LevelData.MapKind.OVERWORLD
	ed_level._palette.refresh(ed_level)
	var ow_ids := ed_level._palette.get_entity_ids_for_test()
	assert_true(ow_ids.has("keen1.level_entrance"), "overworld palette shows the entrance")
	assert_true(ow_ids.has("keen1.player_spawn"), "overworld palette shows player spawn")
	assert_false(ow_ids.has("keen1.vorticon"), "overworld palette hides gameplay entities")


func test_inspector_edits_level_id_and_bool_props():
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	var def := EntityDef.new("keen1.level_entrance", 1, 1,
		{"target_level_id": "lvl1", "blocks_until_completed": true})
	ed.level.entities.append(def)
	ed.select_entity(ed.level.entities.size() - 1)
	# target_level_id is a level_id type -> OptionButton dropdown of scanned levels.
	var ob: OptionButton = ed._inspector.find_child("Prop_target_level_id", true, false)
	assert_not_null(ob, "level_id property renders an OptionButton")
	assert_true(ob.item_count > 1, "dropdown includes scanned levels plus current 'lvl1'")
	ob.select(0)
	ob.item_selected.emit(0)
	assert_eq(def.properties["target_level_id"], ob.get_item_text(0))
	# blocks_until_completed is a bool -> CheckBox.
	var cb: CheckBox = ed._inspector.find_child("Prop_blocks_until_completed", true, false)
	assert_not_null(cb, "Bool property should render as a CheckBox")
	cb.set_pressed_no_signal(false)
	cb.toggled.emit(false)
	assert_eq(def.properties["blocks_until_completed"], false)


func test_inspector_enum_option_button_writes_back():
	# A registered type with an enum schema renders an OptionButton; selecting
	# an item writes the chosen option into EntityDef.properties.
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.spike", EntityRegistry.CATEGORY_HAZARD, "Spike",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]}])
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	var def := EntityDef.new("keen1.spike", 1, 1, {"facing": "right"})
	ed.level.entities.append(def)
	ed.select_entity(ed.level.entities.size() - 1)
	var ob: OptionButton = ed._inspector.find_child("Prop_facing", true, false)
	assert_not_null(ob, "enum property renders an OptionButton")
	assert_eq(ob.selected, 0, "default 'right' is item 0")
	# Select 'left' (item 1) and emit the signal.
	ob.select(1)
	ob.item_selected.emit(1)
	assert_eq(def.properties["facing"], "left", "OptionButton writes chosen option back")

func test_inspector_two_enums_each_write_independently():
	# Two enum properties on one type: each OptionButton closure must capture its
	# own key/options (regression guard for per-iteration capture in the loop).
	EntityRegistry.clear()
	EntityRegistry.register_sprite("keen1.gadget", EntityRegistry.CATEGORY_HAZARD, "Gadget",
		"res://assets/sprites/Spike.tscn",
		[{name = "facing", default = "right", type = "enum", options = ["right", "left"]},
		 {name = "mode", default = "off", type = "enum", options = ["off", "on", "blink"]}])
	var ed := LevelEditor.new()
	add_child_autofree(ed)
	ed._ready()
	var def := EntityDef.new("keen1.gadget", 1, 1, {"facing": "right", "mode": "off"})
	ed.level.entities.append(def)
	ed.select_entity(ed.level.entities.size() - 1)
	var ob_facing: OptionButton = ed._inspector.find_child("Prop_facing", true, false)
	var ob_mode: OptionButton = ed._inspector.find_child("Prop_mode", true, false)
	assert_not_null(ob_facing)
	assert_not_null(ob_mode)
	# Change facing -> mode must be untouched, and vice versa.
	ob_facing.select(1)
	ob_facing.item_selected.emit(1)
	assert_eq(def.properties["facing"], "left")
	assert_eq(def.properties["mode"], "off", "changing facing did not touch mode")
	ob_mode.select(2)
	ob_mode.item_selected.emit(2)
	assert_eq(def.properties["mode"], "blink")
	assert_eq(def.properties["facing"], "left", "changing mode did not touch facing")


# --- Tile size sync ---

func _tileset_with_region(region: Vector2i) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = region
	var src := TileSetAtlasSource.new()
	src.texture_region_size = region
	ts.add_source(src)
	return ts

func test_source_select_syncs_tile_size():
	var ed := _make_editor()
	ed.level.tile_size = 64
	ed.level.tileset_ref = _tileset_with_region(Vector2i(32, 32))
	ed._inspector.refresh(ed)
	ed._inspector._on_source_selected(0)
	assert_eq(ed.level.tile_size, 32, "tile_size synced to source region 32")

func test_tileset_select_syncs_tile_size():
	var ed := _make_editor()
	ed.level.tile_size = 64
	var ts := _tileset_with_region(Vector2i(8, 8))
	ed.level.tileset_ref = ts
	ed._inspector.refresh(ed)
	# Simulate selecting the tileset: refresh already populated the picker with
	# the current tileset. Trigger source 0 selection to fire the sync.
	ed._inspector._on_source_selected(0)
	assert_eq(ed.level.tile_size, 8, "tile_size synced to source region 8")

func test_null_tileset_does_not_change_tile_size():
	var ed := _make_editor()
	ed.level.tile_size = 64
	ed._inspector._apply_tile_size_for_source(null, 0)
	assert_eq(ed.level.tile_size, 64, "null tileset leaves tile_size unchanged")

func test_multi_source_syncs_per_source():
	var ed := _make_editor()
	var ts := TileSet.new()
	var s0 := TileSetAtlasSource.new()
	s0.texture_region_size = Vector2i(64, 64)
	ts.add_source(s0)
	var s1 := TileSetAtlasSource.new()
	s1.texture_region_size = Vector2i(32, 32)
	ts.add_source(s1)
	ed.level.tileset_ref = ts
	ed.level.tile_size = 8
	ed._inspector.refresh(ed)
	ed._inspector._on_source_selected(1)
	assert_eq(ed.level.tile_size, 32, "source 1 sets 32px tiles")
	ed._inspector._on_source_selected(0)
	assert_eq(ed.level.tile_size, 64, "source 0 sets 64px tiles")
