extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")

func _ready() -> void:
	_ensure_play_button()
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())

func _ensure_play_button() -> void:
	if has_node("%PlayButton"):
		(%PlayButton as Button).pressed.connect(_play)
		return
	var play := Button.new()
	play.name = "PlayButton"
	play.text = "Play"
	play.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(play)
	play.set("theme_type_variation", "Button")
	(%PlayButton as Button).pressed.connect(_play)

func _play() -> void:
	GameManager.start_episode("keen1")

func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)
