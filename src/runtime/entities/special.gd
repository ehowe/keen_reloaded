class_name Special
extends Entity
## Base for exits / triggers / doors. Emits `level_completed` (LevelRuntime
## connects it to show the completion overlay). Default is a visible no-op.


signal level_completed

func _color() -> Color:
	return Color(0.4, 0.9, 1.0, 1)
