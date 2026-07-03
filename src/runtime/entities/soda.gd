class_name Soda
extends Collectible
## Soda can — a score pickup worth 200 points.


func _ready() -> void:
	super._ready()
	score_value = 200
