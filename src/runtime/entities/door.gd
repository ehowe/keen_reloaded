class_name Door
extends Entity
## Color-locked door. Solid (collision on the tiles bit) until the player
## carries a matching keycard; on contact the door consumes one keycard of its
## variant color, disables both its CollisionPolygon2D and contact Area2D so
## the player can walk through WHILE the "Retract" animation plays, then leaves
## the door open. Variant sprite is selected via EntityVariant (Red/Blue/Yellow/Green).


var variant: String = "red"
var _opened: bool = false


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _ready() -> void:
	# Build only the contact Area2D — skip Entity's ColorRect visual fallback
	# (the door's sprites live at DoorMask/Visual, not as a direct child).
	_area = _build_contact_area()
	# Widen the contact sensor beyond the door's solid CollisionPolygon2D.
	# The door is the first entity that is BOTH solid (tiles layer) AND uses
	# the Area2D contact sensor pattern; if the sensor's shape matched the
	# door's collision width, the player would be stopped at the tile boundary
	# and their body would never enter the Area2D's region — body_entered
	# would never fire and the door would never open. Extending the sensor 1
	# tile outward on each side gives the player room to enter the detection
	# zone before being blocked by the solid collision.
	var col := _area.get_child(0) as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		(col.shape as RectangleShape2D).size = Vector2(TILE * 1.1, TILE)
	add_child(_area)
	# Door sits on the tiles layer (bit 3 = value 4) so its CollisionPolygon2D
	# actually blocks the player (player.collision_mask = 4). Default items bit
	# (8) would let the player walk through.
	collision_layer = 4
	collision_mask = 0


func _handle_player(player: Node) -> void:
	if _opened:
		return
	if not player.has_method("has_keycard") or not player.has_keycard(variant):
		return  # Locked — door stays solid, player bumped.
	_opened = true
	player.consume_keycard(variant)
	# Disable collision BEFORE playing the animation so the player can walk
	# through the door while the Retract anim is still running, instead of
	# being blocked until animation_finished fires.
	_disable_collision()
	AudioManager.play_sfx("door_open")  # warns gracefully until asset exists
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("Retract"):
		anim.play("Retract")


func _disable_collision() -> void:
	# Use set_deferred because this runs inside the Area2D's body_entered
	# physics-signal callback — Godot forbids mutating physics state
	# (disabled/monitoring) synchronously during the query flush. Mirrors
	# enemy.gd and level_entrance.gd. The deferred call applies at end of frame.
	var poly := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if poly != null:
		poly.set_deferred("disabled", true)
	if _area != null:
		_area.set_deferred("monitoring", false)
