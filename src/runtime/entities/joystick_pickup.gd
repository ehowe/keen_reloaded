class_name JoystickPickup
extends Entity
## Joystick pickup. Grants the "keen1.joystick" inventory item on contact,
## then frees. Registered as a LEVEL-only item. Visual is a placeholder
## ColorRect supplied by Entity._build_contact() via _color() until real
## art lands.

func _handle_player(_player: Node) -> void:
	Inventory.add_item(ItemIDs.JOYSTICK)
	AudioManager.play_sfx("pickup_score")
	queue_free()


func _color() -> Color:
	return Color(0.85, 0.20, 0.20, 0.8)
