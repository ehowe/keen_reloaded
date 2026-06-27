class_name Special
extends Entity
## Base for exits / triggers / doors. Concrete behavior is Plan 4 content; this
## class is a visible no-op placeholder so registered special types spawn safely.


func _color() -> Color:
	return Color(0.4, 0.9, 1.0, 1)
