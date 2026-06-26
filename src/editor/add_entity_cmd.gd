class_name AddEntityCmd
extends EditorCommand
## Appends one entity to the level. Undo removes it at its recorded index.

var entity: EntityDef
var _index: int = -1

func _init(p_entity: EntityDef) -> void:
	entity = p_entity

func apply(level: LevelData) -> void:
	_index = level.entities.size()
	level.entities.append(entity)

func undo(level: LevelData) -> void:
	if _index >= 0 and _index < level.entities.size():
		level.entities.remove_at(_index)

func describe() -> String:
	return "AddEntity(%s @ %d,%d)" % [entity.type, entity.x, entity.y]
