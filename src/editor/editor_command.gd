class_name EditorCommand
extends RefCounted
## Base class for an undoable editor action on a LevelData.
## Subclasses mutate the level in apply() and reverse it in undo().

func apply(_level: LevelData) -> void:
	push_warning("EditorCommand.apply not overridden: " + describe())

func undo(_level: LevelData) -> void:
	push_warning("EditorCommand.undo not overridden: " + describe())

func describe() -> String:
	return "EditorCommand"


## Restore every cell in `prev` (Vector2i -> int) to its recorded id on the
## given layer. Shared by the tile-editing commands' undo().
static func restore_tiles(level: LevelData, layer: String, prev: Dictionary) -> void:
	for cell: Vector2i in prev:
		level.set_tile(layer, cell.x, cell.y, int(prev[cell]))
