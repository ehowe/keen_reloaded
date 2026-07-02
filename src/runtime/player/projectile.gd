class_name Projectile
extends Area2D
## Raygun bolt. Linear motion in the launch direction; despawns on lifetime
## expiry, on hitting an enemy (deals 1 damage), or on hitting a wall/tile.
## Passes through items (entities without take_damage).

@export var speed: float = 600.0
@export var lifetime: float = 2.0

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if body_entered.is_connected(_on_body_entered) == false:
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


## Launch in facing direction (dir = +1 right / -1 left).
func launch(dir: int) -> void:
	velocity = Vector2(signi(dir) * speed, 0.0)


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(1)
		queue_free()
	elif not body.is_in_group("entity"):
		queue_free()
	# else: an entity without take_damage (e.g. an item) -> pass through
