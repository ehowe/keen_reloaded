class_name Enemy
extends Entity
## An enemy with health and contact damage. take_damage() reduces health and
## frees the enemy at 0. (No AI movement in Plan 3 — Plan 4 adds it.)

var health: int = 1
var contact_damage: int = 1


func _color() -> Color:
	return Color(0.9, 0.4, 0.6, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		queue_free()
