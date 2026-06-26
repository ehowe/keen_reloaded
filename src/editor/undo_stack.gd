class_name UndoStack
extends RefCounted
## Linear undo/redo of EditorCommands applied to a LevelData.

signal changed

var _undo: Array[EditorCommand] = []
var _redo: Array[EditorCommand] = []

## Applies the command now, pushes it to undo history, and clears redo.
func execute(level: LevelData, cmd: EditorCommand) -> void:
	cmd.apply(level)
	_push(cmd)

## Records an already-applied command (e.g. a paint stroke applied live) without
## re-applying. Pushes to undo history and clears redo.
func push_applied(_level: LevelData, cmd: EditorCommand) -> void:
	_push(cmd)

func _push(cmd: EditorCommand) -> void:
	_undo.append(cmd)
	_redo.clear()
	changed.emit()

func undo(level: LevelData) -> void:
	if _undo.is_empty():
		return
	var cmd: EditorCommand = _undo.pop_back()
	cmd.undo(level)
	_redo.append(cmd)
	changed.emit()

func redo(level: LevelData) -> void:
	if _redo.is_empty():
		return
	var cmd: EditorCommand = _redo.pop_back()
	cmd.apply(level)
	_undo.append(cmd)
	changed.emit()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func clear() -> void:
	_undo.clear()
	_redo.clear()
	changed.emit()
