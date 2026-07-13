extends Control

const EDITOR_SCENE := preload("res://src/editor/level_editor.tscn")
const PACK_SELECT := preload("res://src/ui/pack_select.tscn")
const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")

func _ready() -> void:
	AudioManager.play_music(AudioManager.MUSIC_THEME)
	_ensure_play_button()
	_wire_button(%ContinueButton, _continue)
	_wire_button(%NewGameButton, _new_game)
	%CustomPacksButton.pressed.connect(_open_pack_select)
	%EditorButton.pressed.connect(_open_editor)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	_wire_ui_sfx()
	_update_continue_enabled()


func _wire_ui_sfx() -> void:
	for b in find_children("*", "Button", true, false):
		(b as Button).focus_entered.connect(_on_button_focus)
		(b as Button).pressed.connect(_on_button_select)


func _wire_button(btn: Button, fn: Callable) -> void:
	if btn != null:
		btn.pressed.connect(fn)


func _on_button_focus() -> void:
	AudioManager.play_sfx("menu_move")


func _on_button_select() -> void:
	AudioManager.play_sfx("menu_select")


## Continue is only meaningful if at least one slot holds a valid save.
func _update_continue_enabled() -> void:
	if has_node("%ContinueButton"):
		var has_occupied := false
		for s in SaveSystem.list_slots():
			if s["status"] == "occupied":
				has_occupied = true
				break
		(%ContinueButton as Button).disabled = not has_occupied


func _ensure_play_button() -> void:
	if has_node("%PlayButton"):
		(%PlayButton as Button).pressed.connect(_play)
		return
	var play := Button.new()
	play.name = "PlayButton"
	play.text = "Play (dev)"
	play.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(play)
	play.set("theme_type_variation", "Button")
	play.pressed.connect(_play)


## Dev fast-path: start keen1 in the first empty slot (or slot 1).
func _play() -> void:
	_start_new_game_in_first_empty_slot("keen1")


func _start_new_game_in_first_empty_slot(scope_id: String) -> void:
	var slot := _first_empty_slot()
	if slot == 0:
		slot = 1
	SaveSystem.active_slot = slot
	GameManager.clear_progress()
	GameManager.current_scope_kind = "episode"
	GameManager.start_episode(scope_id)
	SaveSystem.save_active()


func _first_empty_slot() -> int:
	for s in SaveSystem.list_slots():
		if s["status"] == "empty":
			return int(s["slot"])
	return 0


func _new_game() -> void:
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)  # @onready vars (title, grid) resolve here
	ss.set_mode("new_game")
	ss.title.text = "New Game — Choose Slot"
	ss.slot_chosen.connect(_on_new_game_slot_chosen)


func _on_new_game_slot_chosen(slot: int, _mode: String) -> void:
	SaveSystem.active_slot = slot
	# For v1 New Game defaults to the only bundled episode (keen1). When a
	# second episode ships, insert an episode-select step here.
	GameManager.clear_progress()
	GameManager.current_scope_kind = "episode"
	GameManager.start_episode("keen1")
	SaveSystem.save_active()


func _continue() -> void:
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	ss.set_mode("continue")
	ss.title.text = "Continue — Choose Slot"
	ss.slot_chosen.connect(_on_continue_slot_chosen)


func _on_continue_slot_chosen(slot: int, _mode: String) -> void:
	if not SaveSystem.load_slot(slot):
		push_warning("MainMenu: failed to load slot %d" % slot)
		return
	GameManager.resume_overworld()


func _open_editor() -> void:
	get_tree().change_scene_to_packed(EDITOR_SCENE)


func _open_pack_select() -> void:
	get_tree().change_scene_to_packed(PACK_SELECT)
