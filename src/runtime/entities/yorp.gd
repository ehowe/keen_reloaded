class_name Yorp
extends Enemy
## Keen 1 Yorp: slow patrol; on side contact knocks the player back and deals
## minor damage; a stomp from above stuns it (recoverable); 1 blaster hit to
## defeat. All behaviour comes from the Enemy base; this class only tunes knobs.


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 100
	patrol_speed = 70.0
	contact_damage = 1
