class_name TeddyBear
extends Collectible
## Teddy bear — a rare score pickup worth 5000 points.


func _ready() -> void:
	super._ready()
	score_value = 5000
