class_name CanvasEditor
extends Control
## Editable tile canvas for the level editor. Renders tiles via _draw() (colored
## cells) and translates mouse input into editor commands via the LevelEditor.

var editor: LevelEditor

var zoom: float = 0.5
var _last_cell: Vector2i = Vector2i(-1, -1)

# Select-tool drag state. Marquee draws a new box; move relocates the box.
var _marquee_anchor: Vector2i = Vector2i(-1, -1)
var _marquee_dragging: bool = false
var _move_dragging: bool = false
var _move_delta: Vector2i = Vector2i.ZERO


## Inclusive tile rect spanning two corner cells (any order). Godot's Rect2i
## constructor takes (position, size), not two corners, so the min corner and
## positive cell-count size are computed explicitly.
static func rect_from_corners(a: Vector2i, b: Vector2i) -> Rect2i:
	return Rect2i(
		Vector2i(mini(a.x, b.x), mini(a.y, b.y)),
		Vector2i(absi(b.x - a.x) + 1, absi(b.y - a.y) + 1)
	)


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
	# Composite non-active layers first (dimmed), then the active layer on top at
	# full opacity. An opaque, densely-filled layer (e.g. a geometry layer full of
	# sky tiles) would otherwise cover every foreground/background tile, making
	# edits on those layers invisible. Drawing the active layer last guarantees
	# painted tiles are always seen.
	var dim := Color(1, 1, 1, 0.5)
	for layer in [LevelData.LAYER_BACKGROUND, LevelData.LAYER_FOREGROUND, LevelData.LAYER_GEOMETRY]:
		if layer == editor.active_layer:
			continue
		_layer_pass(layer, cs, EditorColors.layer_tint(layer) * dim)
	_layer_pass(editor.active_layer, cs, EditorColors.layer_tint(editor.active_layer))

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

	# tile marquee selection (Select tool)
	if editor.tile_selection.size != Vector2i.ZERO:
		var sp := editor.tile_selection.position
		var sz := editor.tile_selection.size
		var sel_rect := Rect2(sp.x * cs, sp.y * cs, sz.x * cs, sz.y * cs)
		# Ghost outline at the drag destination while moving.
		if _move_dragging:
			var gp := sp + _move_delta
			draw_rect(Rect2(gp.x * cs, gp.y * cs, sz.x * cs, sz.y * cs), Color(1, 1, 0.4, 0.5), false, 2.0)
		draw_rect(sel_rect, Color(1, 1, 0.4, 1.0), false, 2.0)


func _layer_pass(layer: String, cs: float, tint: Color) -> void:
	var ts: TileSet = _level().tileset_ref
	var has_art := ts != null and ts.get_source_count() > 0
	# Cache each source's texture so tiles from any source render correctly.
	var tex_by_source: Dictionary = {}
	if has_art:
		for i in range(ts.get_source_count()):
			var src := ts.get_source(ts.get_source_id(i))
			if src.texture != null:
				tex_by_source[i] = src.texture
	for y in range(_level().height):
		for x in range(_level().width):
			var id := _level().get_tile(layer, x, y)
			if id <= 0:
				continue
			if has_art:
				var region := TileAtlas.tile_region(ts, id)
				var tex: Texture2D = tex_by_source.get(TileAtlas.source_index_for_id(id))
				if tex != null:
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
					# Alt+click eyedrops the tile under the cursor from any tool.
					if mb.alt_pressed:
						editor.pick_tile_at(cell)
					elif editor.active_tool == "select":
						_on_select_down(cell)
					else:
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
			if editor.active_tool == "select":
				if _move_dragging:
					_move_delta = cell - _marquee_anchor
					queue_redraw()
				elif _marquee_dragging and cell != _marquee_anchor:
					editor.tile_selection = rect_from_corners(_marquee_anchor, cell)
					queue_redraw()
			elif editor.active_tool == "paint" or editor.active_tool == "erase":
				editor.stroke_to(cell)
		_last_cell = cell


func _on_left_down(cell: Vector2i) -> void:
	_last_cell = cell
	match editor.active_tool:
		"entity":
			if editor.selected_entity_type == "keen1.player_spawn":
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
		"pick":
			editor.pick_tile_at(cell)


## Select-tool press: if the press lands inside an active tile selection, start a
## move drag; otherwise start a fresh marquee (clearing any old selection first).
## Entity-select is deferred to mouse-up so a click (no drag) still selects an
## entity instead of starting a marquee.
func _on_select_down(cell: Vector2i) -> void:
	_last_cell = cell
	if editor.tile_selection.size != Vector2i.ZERO and editor.tile_selection.has_point(cell):
		_move_dragging = true
		_marquee_anchor = cell
		_move_delta = Vector2i.ZERO
	else:
		editor.clear_tile_selection()
		_marquee_dragging = true
		_marquee_anchor = cell


## Select-tool release: finalize a move (commit if the delta is non-zero) or, if
## the press never left its cell, fall back to entity-select (the original
## behavior of the Select tool).
func _on_select_up() -> void:
	if _move_dragging:
		if _move_delta != Vector2i.ZERO:
			editor.move_selection(_move_delta)
		_move_dragging = false
		_move_delta = Vector2i.ZERO
		_marquee_anchor = Vector2i(-1, -1)
		queue_redraw()
	elif _marquee_dragging:
		var was_click := (_last_cell == _marquee_anchor)
		_marquee_dragging = false
		_marquee_anchor = Vector2i(-1, -1)
		if was_click:
			editor.select_entity(editor.entity_at_cell(_last_cell))
		queue_redraw()


func _on_left_up() -> void:
	if editor.active_tool == "select":
		_on_select_up()
	else:
		editor.end_stroke()


func _unhandled_input(event: InputEvent) -> void:
	if editor == null or editor.active_tool != "select":
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if editor.tile_selection.size != Vector2i.ZERO:
			editor.clear_tile_selection()
			get_viewport().set_input_as_handled()


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
