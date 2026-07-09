extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")
const PACK_SELECT := preload("res://src/ui/pack_select.tscn")

func _ready() -> void:
	_ensure_play_button()
	%CustomPacksButton.pressed.connect(_open_pack_select)
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
	play.pressed.connect(_play)

func _play() -> void:
	GameManager.start_episode("keen1")

func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)

func _open_pack_select() -> void:
	get_tree().change_scene_to_packed(PACK_SELECT)
