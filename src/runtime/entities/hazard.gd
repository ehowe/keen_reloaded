class_name Hazard
extends Entity
## Damages the player on contact (spikes, fire, etc.).

var damage: int = 1


func _color() -> Color:
	return Color(1.0, 0.2, 0.2, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(damage)


## Drain the player's entire current health on contact (instakill). Shared by
## the instakill hazard family (Spike/Fire/Clapper) so the contract lives in
## one place. No-op when the body lacks the player damage contract.
func _instakill(player: Node) -> void:
	if player.has_method("take_damage") and "health" in player:
		player.take_damage(player.health)
