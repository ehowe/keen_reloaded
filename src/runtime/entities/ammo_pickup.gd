class_name AmmoPickup
extends Collectible
## Raygun pickup. On first contact, grants the keen1.blaster inventory item
## (the weapon); every contact grants ammo_value ammo. Idempotent: subsequent
## pickups silently no-op the inventory write (Inventory.add_item guards on
## first acquisition) and still grant ammo. Registered as keen1.raygun.


@export var ammo_value: int = 5


func _handle_player(player: Node) -> void:
	Inventory.add_item(ItemIDs.BLASTER)
	if player.has_method("add_ammo"):
		player.add_ammo(ammo_value)
	AudioManager.play_sfx("pickup_ammo")
	queue_free()
