class_name LevelEditor
extends Control
## Integrated level editor controller. Single source of truth: holds the active
## LevelData, active layer, active tool, selection, and the UndoStack. Builds the
## 3-panel layout in code; child panels read state and call back via methods here.

signal level_changed
signal selection_changed
signal status_changed(text: String)

const TOOLS := {
	"paint": "Paint",
	"erase": "Eraser",
	"fill": "Fill",
	"entity": "Entity",
	"select": "Select",
	"pick": "Pick",
}
const PALETTE_TILE_COUNT := 8   # ids 1..N shown in the tile picker
const DEFAULT_WIDTH := 32
const DEFAULT_HEIGHT := 24
const SETTINGS_PATH := "user://editor.cfg"
const SETTINGS_SECTION := "editor"
const SETTINGS_KEY := "last_level_path"

var level: LevelData
var undo_stack: UndoStack
var active_layer: String = LevelData.LAYER_GEOMETRY
var active_tool: String = "paint"
var selected_tile_id: int = 1
var selected_entity_type: String = "keen1.vorticon"
var selected_entity_index: int = -1
var tile_selection: Rect2i = Rect2i()  # active tile marquee; zero-area = none

var _canvas: CanvasEditor
var _palette: PalettePanel
var _inspector: InspectorPanel
var _status: Label
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _last_path: String = ""


func _ready() -> void:
	undo_stack = UndoStack.new()
	undo_stack.changed.connect(_on_history_changed)
	_restore_or_new()
	_build_ui()


## On a fresh open, start a blank level. When returning from Test ▶, restore the
## level that was stashed in GameManager.pending_level.
func _restore_or_new() -> void:
	if GameManager != null and GameManager.pending_level != null:
		level = GameManager.pending_level
		undo_stack.clear()
		selected_entity_index = -1
		_last_path = ""
		# Consume the stash so a later non-Test editor open starts fresh.
		GameManager.pending_level = null
		GameManager.return_scene = null
	elif not _try_reopen_last():
		_new_level()


# ------------------------------------------------------------------ state API

func _new_level() -> void:
	level = LevelData.new()
	level.level_id = "new_level"
	level.level_name = "Untitled"
	level.width = DEFAULT_WIDTH
	level.height = DEFAULT_HEIGHT
	level.fill_blank()
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = ""
	_broadcast()


## Public entry used by the toolbar "New" button.
func new_level() -> void:
	_new_level()


## Public entry used by the toolbar "Save" button.
func save_level() -> void:
	_save_dialog.popup_centered_clamped(Vector2i(700, 500))


## Public entry used by the toolbar "Load" button.
func load_level() -> void:
	_load_dialog.popup_centered_clamped(Vector2i(700, 500))


## Public entry used by the toolbar "Test ▶" button. Stashes the current level
## and swaps to the runtime scene for live play; Esc in the runtime returns here.
func test_run() -> void:
	GameManager.pending_level = level
	GameManager.return_scene = preload("res://src/editor/level_editor.tscn")
	get_tree().change_scene_to_packed(preload("res://src/runtime/level_runtime.tscn"))


func set_active_layer(layer: String) -> void:
	active_layer = layer
	_broadcast()


func set_tool(tool: String) -> void:
	active_tool = tool
	_broadcast()


func set_selected_tile_id(id: int) -> void:
	selected_tile_id = id
	_broadcast()


func set_selected_entity_type(type_id: String) -> void:
	selected_entity_type = type_id
	_broadcast()


## Paint/erase/fill at a tile cell, honoring the active tool. Pushes one command.
func edit_at_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return
	match active_tool:
		"paint":
			var cmd := PaintCellsCmd.new(active_layer, selected_tile_id)
			cmd.paint(level, cell.x, cell.y)
			undo_stack.push_applied(level, cmd)
		"erase":
			var cmd := PaintCellsCmd.new(active_layer, 0)
			cmd.paint(level, cell.x, cell.y)
			undo_stack.push_applied(level, cmd)
		"fill":
			# Shift+click flood-erases the region (fill with id 0).
			var fill_id := selected_tile_id
			if Input.is_physical_key_pressed(KEY_SHIFT):
				fill_id = 0
			undo_stack.execute(level, FloodFillCmd.new(active_layer, cell, fill_id))
		"entity":
			_place_entity(cell)
	_broadcast()


## Eyedropper: grab the tile on the active layer at `cell` and make it the active
## brush, then switch to the Paint tool so it can be reused immediately. No-op on
## empty or out-of-bounds cells. UI state only -- not recorded on the UndoStack.
func pick_tile_at(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return
	var id := level.get_tile(active_layer, cell.x, cell.y)
	if id <= 0:
		_set_status("Nothing to pick (empty cell)")
		return
	set_selected_tile_id(id)
	set_tool("paint")


## Move every filled tile inside `tile_selection` (across all three layers) by
## `delta`. Returns false (no-op) when: no active selection, zero delta, nothing
## filled to move, or any filled tile would land out of bounds. On success pushes
## one MoveTilesCmd and advances the selection to follow the moved tiles.
func move_selection(delta: Vector2i) -> bool:
	if tile_selection.size == Vector2i.ZERO:
		return false
	if delta == Vector2i.ZERO:
		return false
	var layers := [LevelData.LAYER_GEOMETRY, LevelData.LAYER_FOREGROUND, LevelData.LAYER_BACKGROUND]
	var end := tile_selection.end  # exclusive
	# Bounds check: every filled cell's destination must be in-bounds.
	for layer in layers:
		for y in range(tile_selection.position.y, end.y):
			for x in range(tile_selection.position.x, end.x):
				if level.get_tile(layer, x, y) <= 0:
					continue
				var d := Vector2i(x, y) + delta
				if d.x < 0 or d.y < 0 or d.x >= level.width or d.y >= level.height:
					_set_status("Move blocked: out of bounds")
					return false
	# Gather filled cells per layer into one command.
	var cmd := MoveTilesCmd.new()
	cmd.set_delta(delta)
	for layer in layers:
		var cells := {}
		for y in range(tile_selection.position.y, end.y):
			for x in range(tile_selection.position.x, end.x):
				var id := level.get_tile(layer, x, y)
				if id > 0:
					cells[Vector2i(x, y)] = id
		if not cells.is_empty():
			cmd.add_layer(layer, cells)
	if cmd.is_empty():
		return false
	undo_stack.execute(level, cmd)
	tile_selection.position += delta
	_broadcast()
	return true


## Clears the active tile marquee (UI state; not recorded on the UndoStack).
func clear_tile_selection() -> void:
	tile_selection = Rect2i()
	_broadcast()


## Called repeatedly by the canvas during a paint/erase drag. Coalesces the whole
## stroke into one PaintCellsCmd that is recorded once on mouse-up.
var _stroke: PaintCellsCmd = null

func begin_stroke() -> void:
	if active_tool == "paint":
		_stroke = PaintCellsCmd.new(active_layer, selected_tile_id)
	elif active_tool == "erase":
		_stroke = PaintCellsCmd.new(active_layer, 0)


func stroke_to(cell: Vector2i) -> void:
	if _stroke == null:
		return
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return
	_stroke.paint(level, cell.x, cell.y)
	_refresh_canvas_and_status()


func end_stroke() -> void:
	if _stroke != null:
		undo_stack.push_applied(level, _stroke)
		_stroke = null
		_broadcast()


func _place_entity(cell: Vector2i) -> void:
	if selected_entity_type == "keen1.player_spawn":
		undo_stack.execute(level, SetPlayerSpawnCmd.new(cell))
		return
	undo_stack.execute(level, AddEntityCmd.new(EntityDef.new(selected_entity_type, cell.x, cell.y)))


## Returns the index of the entity occupying `cell`, or -1 if none.
func entity_at_cell(cell: Vector2i) -> int:
	for i in range(level.entities.size()):
		var e: EntityDef = level.entities[i]
		if e.x == cell.x and e.y == cell.y:
			return i
	return -1


func select_entity(index: int) -> void:
	selected_entity_index = index
	selection_changed.emit()
	_inspector.refresh(self)
	_set_status(_cursor_status())


func remove_selected_entity() -> void:
	if selected_entity_index >= 0 and selected_entity_index < level.entities.size():
		undo_stack.execute(level, RemoveEntityCmd.new(selected_entity_index))
		selected_entity_index = -1
		_broadcast()


func undo() -> void:
	undo_stack.undo(level)
	_broadcast()


func redo() -> void:
	undo_stack.redo(level)
	_broadcast()


# ------------------------------------------------------------------ UI build

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_toolbar())

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	_palette = preload("res://src/editor/palette_panel.gd").new()
	_palette.build(self)
	_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var palette_scroll := ScrollContainer.new()
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.custom_minimum_size = Vector2(190, 0)
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette_scroll.add_child(_palette)
	columns.add_child(palette_scroll)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas = preload("res://src/editor/canvas_editor.gd").new()
	_canvas.editor = self
	scroll.add_child(_canvas)
	columns.add_child(scroll)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.custom_minimum_size = Vector2(250, 0)
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector = preload("res://src/editor/inspector_panel.gd").new()
	_inspector.build(self)
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(_inspector)
	columns.add_child(inspector_scroll)

	_status = Label.new()
	_status.text = ""
	root.add_child(_status)

	_save_dialog = _make_file_dialog(FileDialog.FILE_MODE_SAVE_FILE)
	_save_dialog.file_selected.connect(_on_save_path)
	add_child(_save_dialog)

	_load_dialog = _make_file_dialog(FileDialog.FILE_MODE_OPEN_FILE)
	_load_dialog.file_selected.connect(_on_load_path)
	add_child(_load_dialog)

	_broadcast()


func _build_toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "keen_reloaded — Editor"
	title.custom_minimum_size = Vector2(220, 0)
	bar.add_child(title)
	bar.add_child(_tool_button("New", new_level))
	bar.add_child(_tool_button("Save", save_level))
	bar.add_child(_tool_button("Load", load_level))
	bar.add_child(_tool_button("Test ▶", test_run))
	bar.add_child(_tool_button("Undo", undo))
	bar.add_child(_tool_button("Redo", redo))
	return bar


func _tool_button(label: String, callable: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(callable)
	return b


func _make_file_dialog(mode: int) -> FileDialog:
	var d := FileDialog.new()
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.file_mode = mode
	d.add_filter("*.tres", "Level Resource")
	d.title = "Level file"
	return d


# ------------------------------------------------------------------ save/load

func _on_save_path(path: String) -> void:
	_last_path = path
	var err := ResourceSaver.save(level, path)
	if err == OK:
		_remember_path(path)
		_set_status("Saved: %s" % path)
	else:
		_set_status("Save FAILED (error %d): %s" % [err, path])


func _on_load_path(path: String) -> void:
	if _load_from_path(path):
		_remember_path(path)
		_set_status("Loaded: %s" % path)
	else:
		_set_status("Load FAILED (not a LevelData): %s" % path)


## Loads a .tres into the editor without touching the dialog. Returns true on
## success. Does not set status (callers choose their own message) and does not
## touch disk memory (the dialog caller remembers on success; auto-reopen does
## not, since the path is unchanged).
func _load_from_path(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if loaded == null:
		return false
	level = loaded
	undo_stack.clear()
	selected_entity_index = -1
	_last_path = path
	_broadcast()
	return true


# ------------------------------------------------------------------ persistence

## Best-effort: remember the last file path so the next fresh editor open can
## reopen it. Never raises — memory is a convenience, not a requirement.
func _remember_path(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, path)
	cfg.save(SETTINGS_PATH)


## Returns the last remembered file path, or "" if none/unreadable.
func _recall_path() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return ""
	return cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, "") as String


## On a fresh open (no Test ▶ round-trip), reopen the last remembered file if it
## still exists and loads cleanly. Returns true when a level was loaded, false
## when the editor should fall back to a blank level.
func _try_reopen_last() -> bool:
	var path := _recall_path()
	if path.is_empty():
		return false
	if not ResourceLoader.exists(path):
		_set_status("Last level not found, started blank: %s" % path)
		return false
	if _load_from_path(path):
		_set_status("Reopened: %s" % path)
		return true
	_set_status("Last level not loadable, started blank: %s" % path)
	return false


# ------------------------------------------------------------------ refresh

func _on_history_changed() -> void:
	_broadcast()


func _broadcast() -> void:
	level_changed.emit()
	if _canvas:
		_canvas.refresh(self)
	if _palette:
		_palette.refresh(self)
	if _inspector:
		_inspector.refresh(self)
	_set_status(_cursor_status())


func _refresh_canvas_and_status() -> void:
	if _canvas:
		_canvas.refresh(self)
	_set_status(_cursor_status())


func _set_status(text: String) -> void:
	status_changed.emit(text)
	if _status:
		_status.text = text


func _cursor_status() -> String:
	var hint := ""
	if active_tool == "fill":
		hint = " | Shift+click = flood erase"
	return "Tool: %s | Layer: %s | Tile: %d | Entity: %s | Undo: %d Redo: %d%s" % [
		active_tool, active_layer, selected_tile_id, selected_entity_type,
		undo_stack._undo.size(), undo_stack._redo.size(), hint]
