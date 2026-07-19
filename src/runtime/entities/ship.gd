class_name Ship
extends ProximityInteractable
## Overworld-only entity: Commander Keen's crashed ship. Player presses
## `interact` while nearby to request a ship-parts progress readout. Emits
## `progress_requested` (LevelRuntime wires it to a UI overlay once authored).
##
## Ship parts state is the Inventory autoload — each part has a {name, id}
## entry in REQUIRED_PARTS and is considered collected when Inventory.has_item(id)
## is true. The keen1.battery pickup is the only granter wired today; the other
## three ids are forward-declarations awaiting their own pickups.

signal progress_requested(collected: int, total: int, required_parts: Array)

const REQUIRED_PARTS := [
	{name = "Battery",              id = ItemIDs.BATTERY},
	{name = "Joystick",             id = ItemIDs.JOYSTICK},
	{name = "Vacuum Cleaner",       id = ItemIDs.VACUUM},
	{name = "Whisky Bottle (Fuel)", id = ItemIDs.EVERCLEAR},
]


func _process(_delta: float) -> void:
	attempt_show_progress(Input.is_action_just_pressed("interact"))


## Returns true and emits progress_requested when a player is nearby and the
## interact control is pressed. `interact_pressed` is a parameter (not read from
## Input) so tests are deterministic.
func attempt_show_progress(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	progress_requested.emit(collected_count(), REQUIRED_PARTS.size(), REQUIRED_PARTS)
	return true


func collected_count() -> int:
	var n := 0
	for part in REQUIRED_PARTS:
		if Inventory.has_item(part.id):
			n += 1
	return n


func total_count() -> int:
	return REQUIRED_PARTS.size()


func is_part_collected(part_name: String) -> bool:
	for part in REQUIRED_PARTS:
		if part.name == part_name:
			return Inventory.has_item(part.id)
	return false
