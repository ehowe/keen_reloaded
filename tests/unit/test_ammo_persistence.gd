extends GutTest
## Ammo is a persistent GameManager field (source of truth across levels). It
## serializes with the session, deserializes back, and resets on clear_progress
## (new game). The blaster is a find-to-own inventory item (granted by the
## keen1.raygun pickup) tracked separately via the Inventory autoload; its
## persistence is covered by test_inventory.gd and test_pickups.gd.

const BLASTER := "keen1.blaster"


func before_each() -> void:
	GameManager.clear_progress()
	Inventory.clear()


func after_each() -> void:
	GameManager.clear_progress()
	Inventory.clear()


func test_ammo_defaults_to_zero() -> void:
	assert_eq(GameManager.ammo, 0, "fresh session starts with 0 ammo")


func test_clear_progress_resets_ammo() -> void:
	GameManager.ammo = 5
	GameManager.clear_progress()
	assert_eq(GameManager.ammo, 0, "clear_progress zeroes ammo (new game)")


func test_serialize_includes_ammo() -> void:
	GameManager.ammo = 3
	var data := GameManager.serialize()
	assert_true(data.has("ammo"), "payload has ammo key")
	assert_eq(data["ammo"], 3, "ammo serialized")


func test_deserialize_restores_ammo() -> void:
	var data := GameManager.serialize()
	data["ammo"] = 4
	GameManager.ammo = 0
	GameManager.deserialize(data)
	assert_eq(GameManager.ammo, 4, "ammo restored from payload")


func test_ammo_round_trip_through_save_load() -> void:
	GameManager.ammo = 5
	var data := GameManager.serialize()
	GameManager.clear_progress()
	assert_eq(GameManager.ammo, 0, "cleared before load")
	GameManager.deserialize(data)
	assert_eq(GameManager.ammo, 5, "ammo survived serialize -> clear -> deserialize")
