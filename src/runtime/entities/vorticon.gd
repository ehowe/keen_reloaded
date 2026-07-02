class_name Vorticon
extends Enemy
## Keen 1 Vorticon: patrols and randomly hops, takes 3 hits, deadly on contact,
## high score on death.

@export var hop_force: float = 700.0
@export var hop_chance: float = 0.5  # expected hops per second


func _ready() -> void:
	super._ready()
	health = 3
	score_value = 300
	patrol_speed = 140.0


func _ai_tick(delta: float) -> void:
	if is_on_floor() and randf() < hop_chance * delta:
		velocity.y = -hop_force
