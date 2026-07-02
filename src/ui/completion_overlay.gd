class_name CompletionOverlay
extends Control
## Full-screen "Level Complete" overlay shown on exit. Runs under pause
## (process_mode = ALWAYS) so it can receive input while the tree is frozen.
## Emits `dismissed` on any key/mouse press; LevelRuntime returns to the editor
## (Test ▶) or main menu.

signal dismissed

func _unhandled_input(event: InputEvent) -> void:
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var click: bool = event is InputEventMouseButton and event.pressed
	if key or click:
		dismissed.emit()
		get_viewport().set_input_as_handled()
