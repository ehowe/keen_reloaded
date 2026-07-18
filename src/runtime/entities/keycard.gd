class_name Keycard
extends Entity
## Color keycard pickup. Grants one count of its `variant` color to the player
## on contact, plays the pickup SFX, then frees itself. Variant sprite is
## selected via EntityVariant (mirrors the Door's variant system).


var variant: String = "red"


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _handle_player(player: Node) -> void:
	if player.has_method("add_keycard"):
		player.add_keycard(variant)
	AudioManager.play_sfx("pickup_score")
	queue_free()
