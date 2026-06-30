class_name CanvasEditor
extends Control
## Editable tile canvas for the level editor. Renders tiles via _draw() (colored
## cells) and translates mouse input into editor commands via the LevelEditor.

var editor: LevelEditor

var zoom: float = 0.5
var _last_cell: Vector2i = Vector2i(-1, -1)


func _level() -> LevelData:
	return editor.level


func _tile_size() -> int:
	return _level().tile_size


func _cell_size() -> float:
	return float(_tile_size()) * zoom


func refresh(_e: LevelEditor) -> void:
	var w := _level().width * _cell_size()
	var h := _level().height * _cell_size()
	# Only relayout when the canvas size actually changed (painting doesn't).
	if custom_minimum_size != Vector2(w, h):
		custom_minimum_size = Vector2(w, h)
	queue_redraw()


func _draw() -> void:
	if _level() == null:
		return
	var cs := _cell_size()
	var tint_bg := EditorColors.layer_tint(LevelData.LAYER_BACKGROUND)
	var tint_fg := EditorColors.layer_tint(LevelData.LAYER_FOREGROUND)
	var tint_geo := EditorColors.layer_tint(LevelData.LAYER_GEOMETRY)

	_layer_pass(LevelData.LAYER_BACKGROUND, cs, tint_bg)
	_layer_pass(LevelData.LAYER_FOREGROUND, cs, tint_fg)
	_layer_pass(LevelData.LAYER_GEOMETRY, cs, tint_geo)

	# grid
	var grid := Color(1, 1, 1, 0.08)
	for x in range(_level().width + 1):
		draw_line(Vector2(x * cs, 0), Vector2(x * cs, _level().height * cs), grid)
	for y in range(_level().height + 1):
		draw_line(Vector2(0, y * cs), Vector2(_level().width * cs, y * cs), grid)

	# entities
	for e in _level().entities:
		var rect := Rect2(e.x * cs + 2, e.y * cs + 2, cs - 4, cs - 4)
		draw_rect(rect, Color(1, 0.4, 0.2, 0.9), false, 2.0)
		draw_string(get_theme_default_font(), rect.position + Vector2(2, 12), e.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))

	# selection highlight
	if editor.selected_entity_index >= 0 and editor.selected_entity_index < _level().entities.size():
		var se: EntityDef = _level().entities[editor.selected_entity_index]
		draw_rect(Rect2(se.x * cs, se.y * cs, cs, cs), Color(1, 1, 0.4, 1.0), false, 2.0)

	# player spawn
	var ps := _level().player_spawn
	var psz := Vector2(ps.x * cs, ps.y * cs)
	draw_rect(Rect2(psz.x + 3, psz.y + 3, cs - 6, cs - 6), Color(0.3, 0.8, 1, 1), false, 2.0)
	draw_line(psz, psz + Vector2(cs, cs), Color(0.3, 0.8, 1, 1), 1.5)


func _layer_pass(layer: String, cs: float, tint: Color) -> void:
	var ts: TileSet = _level().tileset_ref
	var has_art := ts != null and ts.get_source_count() > 0
	var tex: Texture2D = null
	if has_art:
		tex = TileAtlas.atlas_texture(ts)
	for y in range(_level().height):
		for x in range(_level().width):
			var id := _level().get_tile(layer, x, y)
			if id <= 0:
				continue
			if has_art:
				var region := TileAtlas.tile_region(ts, id)
				draw_texture_rect_region(tex, Rect2(x * cs, y * cs, cs, cs), region, tint)
			else:
				draw_rect(Rect2(x * cs, y * cs, cs, cs), EditorColors.tile_color(id) * tint, true)


func _gui_input(event: InputEvent) -> void:
	if _level() == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		var cell := _mouse_to_cell(mb.position)
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_set_zoom(zoom * 1.25)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_set_zoom(zoom / 1.25)
					accept_event()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_on_left_down(cell)
				else:
					_on_left_up()
				accept_event()
			# Right-click intentionally ignored: erasing is done with the Eraser
			# tool so it is properly undoable and doesn't mutate the active tool.
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var cell := _mouse_to_cell(mm.position)
		if cell != _last_cell:
			editor._set_status(_status_at(cell))
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if editor.active_tool == "paint" or editor.active_tool == "erase":
				editor.stroke_to(cell)
		_last_cell = cell


func _on_left_down(cell: Vector2i) -> void:
	_last_cell = cell
	match editor.active_tool:
		"select":
			editor.select_entity(editor.entity_at_cell(cell))
		"entity":
			if editor.selected_entity_type == "player_spawn":
				editor.edit_at_cell(cell)
			else:
				editor.select_entity(editor.entity_at_cell(cell))
				if editor.selected_entity_index < 0:
					editor.edit_at_cell(cell)
		"paint", "erase":
			editor.begin_stroke()
			editor.stroke_to(cell)
		"fill":
			editor.edit_at_cell(cell)


func _on_left_up() -> void:
	editor.end_stroke()


func _mouse_to_cell(p: Vector2) -> Vector2i:
	var cs := _cell_size()
	if cs <= 0:
		return Vector2i(-1, -1)
	return Vector2i(int(p.x / cs), int(p.y / cs))


func _set_zoom(z: float) -> void:
	zoom = clampf(z, 0.25, 8.0)
	refresh(editor)


func _status_at(cell: Vector2i) -> String:
	return "(%d, %d) | Tool: %s | Layer: %s" % [cell.x, cell.y, editor.active_tool, editor.active_layer]
