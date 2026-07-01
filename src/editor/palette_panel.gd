class_name PalettePanel
extends VBoxContainer
## Left panel: tile picker, layer toggles, tool toggles, entity list.
## IMPORTANT: build() creates the static Layer/Tool/Entities nodes ONCE; only
## the tile grid is rebuildable. refresh() may rebuild the tile grid, but ONLY
## when `tileset_ref` changed (inspector-driven, never mid tile-click). The
## `_last_tileset` gate enforces this: rebuilding during a tile button's
## `pressed` emission (click -> set_selected_tile_id -> broadcast -> refresh)
## would free the emitting button and crash, so refresh() skips the rebuild
## whenever `tileset_ref == _last_tileset` (the click path).

var _tile_buttons: Array[Button] = []
var _tile_grid: GridContainer
var _tile_scroll: ScrollContainer
var _last_tileset: TileSet = null
var _layer_buttons: Dictionary = {}  # layer -> Button
var _tool_buttons: Dictionary = {}   # tool -> Button
var _entity_list: ItemList
var _entity_ids: Array[String] = []
var _preview_bg: ColorRect
var _preview_icon: TextureRect
var _preview_label: Label


func build(e: LevelEditor) -> void:
	custom_minimum_size = Vector2(190, 0)

	add_child(_section_label("Tiles"))
	add_child(_build_preview())
	_tile_scroll = ScrollContainer.new()
	_tile_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tile_scroll.custom_minimum_size = Vector2(0, 220)
	_tile_grid = GridContainer.new()
	_tile_grid.columns = 4
	_tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_scroll.add_child(_tile_grid)
	add_child(_tile_scroll)

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
	for tool: String in ["paint", "erase", "fill", "entity", "select", "pick"]:
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
	_entity_list.custom_minimum_size = Vector2(0, 100)
	_entity_list.item_selected.connect(func(idx: int) -> void:
		e.set_selected_entity_type(_entity_ids[idx]))
	add_child(_entity_list)
	_populate_entities()
	_rebuild_tile_grid(e)
	refresh(e)


func _rebuild_tile_grid(e: LevelEditor) -> void:
	for c in _tile_grid.get_children():
		c.queue_free()
	_tile_buttons.clear()
	_last_tileset = e.level.tileset_ref
	var ts: TileSet = _last_tileset
	var count := _tile_count(e)
	var tile_group := ButtonGroup.new()
	for id in range(1, count + 1):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = tile_group
		b.custom_minimum_size = Vector2(40, 40)
		if ts != null and ts.get_source_count() > 0:
			var icon: AtlasTexture = TileAtlas.tile_icon(ts, id)
			if icon != null:
				b.icon = icon
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.expand_icon = true
				b.tooltip_text = "Tile %d" % id
			else:
				b.text = str(id)
				b.add_theme_color_override("font_color", EditorColors.tile_color(id))
				b.add_theme_color_override("font_hover_color", EditorColors.tile_color(id))
		else:
			b.text = str(id)
			b.add_theme_color_override("font_color", EditorColors.tile_color(id))
			b.add_theme_color_override("font_hover_color", EditorColors.tile_color(id))
		var idv := id
		b.pressed.connect(func() -> void: e.set_selected_tile_id(idv))
		_tile_grid.add_child(b)
		_tile_buttons.append(b)


## Tile count for the palette: the atlas grid size when a TileSet is assigned,
## else the fixed Plan 2 default.
func _tile_count(e: LevelEditor) -> int:
	var ts: TileSet = e.level.tileset_ref
	if ts != null and ts.get_source_count() > 0:
		return TileAtlas.tile_count(ts)
	return LevelEditor.PALETTE_TILE_COUNT


func _populate_entities() -> void:
	_entity_list.clear()
	_entity_ids.clear()
	for entry in EntityRegistry.get_palette_entries():
		var cat: String = entry.get("category", "")
		var label: String = entry.get("label", "")
		_entity_ids.append(entry.get("type_id", ""))
		_entity_list.add_item("[%s] %s" % [cat.left(3), label])


## Lightweight: toggle states only. Rebuilds the tile grid exclusively when the
## level's TileSet changed (which happens via the inspector, never a tile click),
## so it never frees a button during its own pressed emission.
func refresh(e: LevelEditor) -> void:
	if e.level.tileset_ref != _last_tileset:
		_rebuild_tile_grid(e)
	for i in range(_tile_buttons.size()):
		_tile_buttons[i].set_pressed_no_signal((i + 1) == e.selected_tile_id)
	# Scroll the active tile into view so a picked/selected tile is easy to find.
	var id := e.selected_tile_id
	if id >= 1 and id <= _tile_buttons.size():
		_tile_scroll.ensure_control_visible(_tile_buttons[id - 1])
	for layer in _layer_buttons:
		_layer_buttons[layer].set_pressed_no_signal(layer == e.active_layer)
	for tool in _tool_buttons:
		_tool_buttons[tool].set_pressed_no_signal(tool == e.active_tool)
	_entity_list.deselect_all()
	for i in range(_entity_ids.size()):
		if _entity_ids[i] == e.selected_entity_type:
			_entity_list.select(i)
			break
	_update_preview(e)


## "Current tile" thumbnail at the top of the Tiles section: shows the active
## brush tile so a picked tile is obvious at a glance.
func _build_preview() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_bg = ColorRect.new()
	_preview_bg.custom_minimum_size = Vector2(64, 64)
	_preview_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview_icon = TextureRect.new()
	_preview_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_bg.add_child(_preview_icon)
	box.add_child(_preview_bg)
	_preview_label = Label.new()
	_preview_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_preview_label)
	return box


func _update_preview(e: LevelEditor) -> void:
	var tile_id := e.selected_tile_id
	_preview_bg.color = EditorColors.tile_color(tile_id)
	var ts: TileSet = e.level.tileset_ref
	if ts != null and ts.get_source_count() > 0:
		_preview_icon.texture = TileAtlas.tile_icon(ts, tile_id)
	else:
		_preview_icon.texture = null
	_preview_label.text = "Tile %d" % tile_id


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l
