class_name Yorp
extends Enemy
## Keen 1 Yorp: slow patrol; on contact knocks the player back and deals minor
## damage; 1 hit to defeat.

@export var knockback_x: float = 400.0
@export var knockback_y: float = 300.0


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 100
	patrol_speed = 70.0
	contact_damage = 1


func _handle_player(player: Node) -> void:
	var d := 1
	if player is CharacterBody2D:
		d = signi(player.global_position.x - global_position.x)
		player.velocity = Vector2(d * knockback_x, -knockback_y)
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)
