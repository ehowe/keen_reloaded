extends Node
## Top-level game state singleton (autoload). Holds the Test ▶ round-trip state
## and registers player input actions in code (so we don't hand-edit the fragile
## [input] section of project.godot). Expanded in later plans.

var pending_level: LevelData = null
var return_scene: PackedScene = null


func _ready() -> void:
	_ensure_input_actions()


func _ensure_input_actions() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("pogo", KEY_P)


func _add_key_action(action_name: String, keycode: int) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
