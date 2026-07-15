class_name PogoStick
extends Entity
## Pogo stick pickup. Grants the "keen1.pogo" inventory item on contact, then
## frees. Registered as a LEVEL-only item so it cannot be placed on the overworld.

const POGO_ITEM_ID := "keen1.pogo"


func _handle_player(_player: Node) -> void:
	Inventory.add_item(POGO_ITEM_ID)
	AudioManager.play_sfx("pickup_score")
	queue_free()


func _color() -> Color:
	return Color(0.2, 0.9, 0.2, 0.8)
