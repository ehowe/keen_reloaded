class_name Book
extends Collectible
## Book — a score pickup worth 1000 points.


func _ready() -> void:
	super._ready()
	score_value = 1000
