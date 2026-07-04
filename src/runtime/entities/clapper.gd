class_name Clapper
extends Hazard
## Stationary, invincible obstacle. Any contact with the player — from the side
## or by jumping on top — instantly kills Keen (drains current health to 0,
## triggering Player.died). Cannot be destroyed: it has no take_damage method,
## so blaster bolts pass through harmlessly (see projectile.gd's has_method guard)
## and stomping deals no damage to it, only to Keen.

func _handle_player(player: Node) -> void:
	if player.has_method("take_damage") and "health" in player:
		player.take_damage(player.health)
