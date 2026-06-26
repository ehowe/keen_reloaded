class_name RemoveEntityCmd
extends EditorCommand
## Removes the entity at a given index. Undo re-inserts it (with its properties).

var index: int
var _entity: EntityDef = null

func _init(p_index: int) -> void:
	index = p_index

func apply(level: LevelData) -> void:
	if index >= 0 and index < level.entities.size():
		_entity = level.entities[index]
		level.entities.remove_at(index)

func undo(level: LevelData) -> void:
	if _entity != null and index >= 0 and index <= level.entities.size():
		level.entities.insert(index, _entity)

func describe() -> String:
	return "RemoveEntity(@%d)" % index
