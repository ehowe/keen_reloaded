class_name Collectible
extends Entity
## A pickup that awards score on contact, then frees itself. score_value is an
## @export so each pickup scene (lollipop/pizza/soda/book/teddy) carries its own
## value in the .tscn — no per-value subclass needed.

@export var score_value: int = 100


func _color() -> Color:
	return Color(1.0, 0.85, 0.2, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("add_score"):
		player.add_score(score_value)
	AudioManager.play_sfx("pickup_score")
	queue_free()
