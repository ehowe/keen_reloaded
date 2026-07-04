class_name Yorp
extends Enemy
## Keen 1 Yorp: slow patrol biased toward Keen; on side contact knocks the player
## back (no damage — classic Yorp is harmless); a stomp from above stuns it
## (recoverable); 1 blaster hit to defeat. Tuning + seek-biased wander override only.

@export var seek_chance: float = 0.7


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 100
	patrol_speed = 70.0
	contact_damage = 0  # classic Yorp: knockback only, no contact damage
	turns_at_ledges = false


func _choose_walk_dir() -> int:
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group("player") as Node2D
		if p != null:
			if randf() < seek_chance:
				return 1 if p.global_position.x > global_position.x else -1
			return -1 if randf() < 0.5 else 1
	return -_dir


func _walk_phase_time() -> float:
	return randf_range(walk_time * 0.5, walk_time * 1.5)


func _idle_phase_time() -> float:
	return randf_range(idle_time * 0.5, idle_time * 1.5)
