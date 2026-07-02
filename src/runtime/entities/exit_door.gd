class_name ExitDoor
extends Special
## Level exit. On player contact, emits level_completed exactly once.


var _triggered: bool = false


func _handle_player(_player: Node) -> void:
	if _triggered:
		return
	_triggered = true
	level_completed.emit()
