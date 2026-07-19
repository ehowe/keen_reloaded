class_name BatteryPickup
extends Entity
## Battery pickup. Grants the "keen1.battery" inventory item on contact, then
## frees. Registered as a LEVEL-only item (like the pogo stick) so it cannot
## be placed on the overworld. Visual is a placeholder ColorRect supplied by
## Entity._build_contact() via _color() until real art lands.

func _handle_player(_player: Node) -> void:
	Inventory.add_item(ItemIDs.BATTERY)
	AudioManager.play_sfx("pickup_score")
	queue_free()


func _color() -> Color:
	return Color(0.18, 0.45, 0.95, 0.8)
