class_name ExitDoor
extends Special
## Level exit. On player contact, locks control and drives Keen right: he walks
## in front of the door, then steps through (dropped behind + hidden, so he's
## gone past the doorway rather than visible against the background), then emits
## level_completed once.


const WALK_OUT_TIME := 0.3  # seconds Keen walks in front before stepping through
const EXIT_BEAT := 0.2      # pause after he vanishes before the overlay shows

var _triggered: bool = false


func _handle_player(player: Node) -> void:
	if _triggered:
		return
	_triggered = true
	# Force Keen to stride right toward the doorway at half speed.
	if player.has_method("lock_input"):
		player.lock_input(1.0, 0.5)
	await get_tree().create_timer(WALK_OUT_TIME).timeout
	# Step through: drop behind the door and hide Keen so he's no longer visible.
	var p := player as Node2D
	if p != null:
		p.z_index = 0
		p.visible = false
	await get_tree().create_timer(EXIT_BEAT).timeout
	level_completed.emit()
