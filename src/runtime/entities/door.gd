class_name Door
extends Entity
## Color-locked door. Solid (collision on the tiles bit) until the player
## carries a matching keycard; on contact the door consumes one keycard of its
## variant color, plays the "Retract" animation, then disables both its
## CollisionPolygon2D and contact Area2D so the door stays open and cannot
## refire. Variant sprite is selected via EntityVariant (Red/Blue/Yellow/Green).


var variant: String = "red"
var _opened: bool = false


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _ready() -> void:
	# Build only the contact Area2D — skip Entity's ColorRect visual fallback
	# (the door's sprites live at DoorMask/Visual, not as a direct child).
	_area = _build_contact_area()
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
	AudioManager.play_sfx("door_open")  # warns gracefully until asset exists
	var anim := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null:
		_disable_collision()
		return
	if not anim.has_animation("Retract"):
		_disable_collision()
		return
	anim.animation_finished.connect(_on_retract_finished)
	anim.play("Retract")


func _on_retract_finished(_anim_name: String) -> void:
	_disable_collision()


func _disable_collision() -> void:
	var poly := get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if poly != null:
		poly.disabled = true
	if _area != null:
		_area.monitoring = false
