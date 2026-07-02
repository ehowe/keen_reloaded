class_name Butler
extends Enemy
## Butler Robot: fast patrol hazard. ARMORED — projectiles do nothing (take_damage
## is a no-op), so it cannot be defeated by shooting.


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 0
	patrol_speed = 220.0
	contact_damage = 1


## Armored: ignore all projectile damage.
func take_damage(_amount: int) -> void:
	pass
