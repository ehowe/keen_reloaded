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
