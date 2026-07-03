extends GutTest


func before_each() -> void:
	if FileAccess.file_exists(LevelEditor.SETTINGS_PATH):
		DirAccess.remove_absolute(LevelEditor.SETTINGS_PATH)


func test_main_menu_has_editor_and_quit_buttons():
	var scene: PackedScene = load("res://src/ui/main_menu.tscn")
	var inst := scene.instantiate()
	add_child(inst)
	assert_not_null(inst.get_node_or_null("%EditorButton"), "EditorButton unique node resolves")
	assert_not_null(inst.get_node_or_null("%QuitButton"), "QuitButton unique node resolves")
	inst.queue_free()

func test_editor_scene_instantiates_without_error():
	var scene: PackedScene = load("res://src/editor/level_editor.tscn")
	var inst := scene.instantiate()
	add_child(inst)
	assert_not_null(inst.level, "level should be initialized in _ready")
	assert_eq(inst.level.width, LevelEditor.DEFAULT_WIDTH)
	assert_eq(inst.level.height, LevelEditor.DEFAULT_HEIGHT)
	assert_not_null(inst.undo_stack)
	assert_not_null(inst._canvas)
	assert_not_null(inst._palette)
	assert_not_null(inst._inspector)
	inst.queue_free()

func test_editor_place_select_undo_via_controller():
	var scene: PackedScene = load("res://src/editor/level_editor.tscn")
	var inst: LevelEditor = scene.instantiate()
	add_child(inst)
	# paint a single tile
	inst.set_tool("paint")
	inst.set_selected_tile_id(2)
	inst.begin_stroke()
	inst.stroke_to(Vector2i(1, 1))
	inst.end_stroke()
	assert_eq(inst.level.get_tile(LevelData.LAYER_GEOMETRY, 1, 1), 2)
	# place an entity
	inst.set_tool("entity")
	inst.set_selected_entity_type("keen1.vorticon")
	inst.edit_at_cell(Vector2i(3, 3))
	assert_eq(inst.level.entities.size(), 1)
	# select it -> inspector rebuilds with controls (more than the empty-state label)
	inst.select_entity(0)
	var entity_children := inst._inspector._entity_box.get_child_count()
	assert_gt(entity_children, 1, "entity box should show type/x/y/delete")
	# undo removes the entity
	inst.undo()
	assert_eq(inst.level.entities.size(), 0)
	# undo removes the paint
	inst.undo()
	assert_eq(inst.level.get_tile(LevelData.LAYER_GEOMETRY, 1, 1), 0)
	inst.queue_free()
