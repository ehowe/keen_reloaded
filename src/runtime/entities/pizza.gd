class_name Pizza
extends Collectible
## Slice of pizza — a score pickup worth 500 points.


func _ready() -> void:
	super._ready()
	score_value = 500
