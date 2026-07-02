class_name AmmoPickup
extends Collectible
## Raygun ammo pickup. Grants ammo_value to the player on contact, then frees.


@export var ammo_value: int = 5


func _handle_player(player: Node) -> void:
	if player.has_method("add_ammo"):
		player.add_ammo(ammo_value)
	queue_free()
