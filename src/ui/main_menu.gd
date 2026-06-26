extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")

func _ready() -> void:
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())

func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)
