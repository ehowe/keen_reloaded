class_name Hazard
extends Entity
## Damages the player on contact (spikes, fire, etc.).

var damage: int = 1


func _color() -> Color:
	return Color(1.0, 0.2, 0.2, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(damage)
