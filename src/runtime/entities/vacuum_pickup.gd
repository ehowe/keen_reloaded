class_name VacuumPickup
extends Entity
## Vacuum Cleaner pickup. Grants the "keen1.vacuum" inventory item on
## contact, then frees. Registered as a LEVEL-only item. Visual is a
## placeholder ColorRect supplied by Entity._build_contact() via _color()
## until real art lands.

func _handle_player(_player: Node) -> void:
	Inventory.add_item(ItemIDs.VACUUM)
	AudioManager.play_sfx("pickup_score")
	queue_free()


func _color() -> Color:
	return Color(0.55, 0.55, 0.60, 0.8)
