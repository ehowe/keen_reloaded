class_name PalettePanel
extends VBoxContainer
## Left panel: tile picker, layer toggles, tool toggles, entity list.
## IMPORTANT: build() creates all nodes ONCE; refresh() only updates toggle
## states. Rebuilding the tile grid in refresh() would free a button while it is
## emitting its `pressed` signal (click tile -> set_selected_tile_id -> broadcast
## -> rebuild) and crash. So refresh() must never recreate nodes.

var _tile_buttons: Array[Button] = []
var _layer_buttons: Dictionary = {}  # layer -> Button
var _tool_buttons: Dictionary = {}   # tool -> Button
var _entity_list: ItemList
var _entity_ids: Array[String] = []


func build(e: LevelEditor) -> void:
	custom_minimum_size = Vector2(190, 0)

	add_child(_section_label("Tiles"))
	var grid := GridContainer.new()
	grid.columns = 4
	var tile_group := ButtonGroup.new()
	for id in range(1, LevelEditor.PALETTE_TILE_COUNT + 1):
		var b := Button.new()
		b.text = str(id)
		b.toggle_mode = true
		b.button_group = tile_group
		b.add_theme_color_override("font_color", EditorColors.tile_color(id))
		b.add_theme_color_override("font_hover_color", EditorColors.tile_color(id))
		var idv := id
		b.pressed.connect(func() -> void: e.set_selected_tile_id(idv))
		grid.add_child(b)
		_tile_buttons.append(b)
	add_child(grid)

	add_child(_section_label("Layer"))
	var layer_group := ButtonGroup.new()
	for layer: String in [LevelData.LAYER_GEOMETRY, LevelData.LAYER_FOREGROUND, LevelData.LAYER_BACKGROUND]:
		var b := Button.new()
		b.text = layer.capitalize()
		b.toggle_mode = true
		b.button_group = layer_group
		var lv := layer
		b.toggled.connect(func(_p: bool) -> void: e.set_active_layer(lv))
		_layer_buttons[layer] = b
		add_child(b)

	add_child(_section_label("Tool"))
	var tool_group := ButtonGroup.new()
	for tool: String in ["paint", "erase", "fill", "entity", "select"]:
		var b := Button.new()
		b.text = LevelEditor.TOOLS[tool]
		b.toggle_mode = true
		b.button_group = tool_group
		var tv := tool
		b.toggled.connect(func(_p: bool) -> void: e.set_tool(tv))
		_tool_buttons[tool] = b
		add_child(b)

	add_child(_section_label("Entities"))
	_entity_list = ItemList.new()
	_entity_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entity_list.item_selected.connect(func(idx: int) -> void:
		e.set_selected_entity_type(_entity_ids[idx]))
	add_child(_entity_list)
	_populate_entities()
	refresh(e)


func _populate_entities() -> void:
	_entity_list.clear()
	_entity_ids.clear()
	for entry in EntityRegistry.get_palette_entries():
		var cat: String = entry.get("category", "")
		var label: String = entry.get("label", "")
		_entity_ids.append(entry.get("type_id", ""))
		_entity_list.add_item("[%s] %s" % [cat.left(3), label])


## Lightweight: only toggle states. Never recreates nodes (see class doc).
func refresh(e: LevelEditor) -> void:
	for i in range(_tile_buttons.size()):
		_tile_buttons[i].set_pressed_no_signal((i + 1) == e.selected_tile_id)
	for layer in _layer_buttons:
		_layer_buttons[layer].set_pressed_no_signal(layer == e.active_layer)
	for tool in _tool_buttons:
		_tool_buttons[tool].set_pressed_no_signal(tool == e.active_tool)
	_entity_list.deselect_all()
	for i in range(_entity_ids.size()):
		if _entity_ids[i] == e.selected_entity_type:
			_entity_list.select(i)
			break


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l
