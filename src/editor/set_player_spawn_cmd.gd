class_name SetPlayerSpawnCmd
extends EditorCommand
## Sets the player spawn tile coordinate. Undo restores the previous spawn.

var new_spawn: Vector2i
var _prev: Vector2i = Vector2i.ZERO

func _init(p_new_spawn: Vector2i) -> void:
	new_spawn = p_new_spawn

func apply(level: LevelData) -> void:
	_prev = level.player_spawn
	level.player_spawn = new_spawn

func undo(level: LevelData) -> void:
	level.player_spawn = _prev

func describe() -> String:
	return "SetPlayerSpawn(%s)" % str(new_spawn)
