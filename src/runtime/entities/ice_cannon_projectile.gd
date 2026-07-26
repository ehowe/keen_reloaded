class_name IceCannonProjectile
extends Area2D
## Icicle fired by IceCannon. Straight-line motion at constant velocity;
## despawns instantly on touching a solid (non-one-way) tile, or instakills
## Keen on contact. Reuses Projectile.is_solid_tile_at() for the tile probe
## so one-way platforms (jump-through floors) remain passable — no logic
## duplication with the raygun bolt.
##
## The collision shape is built at _ready (codebase pattern: scenes carry
## visuals, scripts build physics). mask = player bit only: the projectile
## senses the player for the kill trigger but does not physically collide
## with anything, so it never blocks or is blocked.

const _HITBOX_SIZE := 32.0  # half of the 64px frame; tight hitbox, dodge room

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # player bit -> body_entered fires only for Keen
	_add_hitbox()
	if body_entered.is_connected(_on_body_entered) == false:
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	# Per-frame solid-tile probe: body_entered fires once per TileMapLayer,
	# so a fast projectile could tunnel past the entry frame into a solid
	# cell. Mirrors the player Projectile's defense; honors one-way skip.
	for body in get_overlapping_bodies():
		if body is TileMapLayer and Projectile.is_solid_tile_at(body, global_position):
			queue_free()
			return


func launch(p_velocity: Vector2) -> void:
	velocity = p_velocity


func _on_body_entered(body: Node) -> void:
	# Only the player is on the mask, but guard for the contract anyway.
	# Drain all health — mirrors Hazard._instakill verbatim. Cannot call
	# _instakill directly because this node extends Area2D, not Hazard.
	if body != null and body.is_in_group("player") \
			and body.has_method("take_damage") and "health" in body:
		body.take_damage(body.health)


func _add_hitbox() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_HITBOX_SIZE, _HITBOX_SIZE)
	shape.shape = rect
	add_child(shape)
