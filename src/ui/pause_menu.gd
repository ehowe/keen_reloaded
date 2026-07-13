extends CanvasLayer
## Pause overlay. Toggled by Esc (ui_cancel) via GameManager._unhandled_input.
## Save Game is gated to overworld + active slot. Load reopens slot-select.
## Quit to Menu auto-saves first (best-effort).

const MAIN_MENU := preload("res://src/ui/main_menu.tscn")
const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")

@onready var save_btn: Button = %SaveButton
@onready var status: Label = %StatusLabel


func _ready() -> void:
	layer = 100
	# PROCESS_MODE_ALWAYS so the overlay (and any slot-select child) still
	# receive input while get_tree().paused is true.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%ResumeButton.pressed.connect(_on_resume)
	%SaveButton.pressed.connect(_on_save)
	%LoadButton.pressed.connect(_on_load)
	%QuitButton.pressed.connect(_on_quit)
	_wire_ui_sfx()


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the menu. (GameManager opens it; it can't run while paused, so
	# the close path lives here on the ALWAYS overlay.)
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh_save_button()
	status.text = ""
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _refresh_save_button() -> void:
	# Save is only allowed on the overworld with an active slot chosen.
	var allowed := GameManager.state == GameManager.State.OVERWORLD and SaveSystem.active_slot != 0
	save_btn.disabled = not allowed


func _on_resume() -> void:
	close()


func _on_save() -> void:
	if SaveSystem.active_slot == 0:
		status.text = "No active slot."
		return
	if SaveSystem.save_slot(SaveSystem.active_slot):
		status.text = "Saved to slot %d." % SaveSystem.active_slot
	else:
		status.text = "Save failed."


func _on_load() -> void:
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)  # @onready vars resolve here
	ss.set_mode("continue")
	ss.title.text = "Load — Choose Slot"
	ss.slot_chosen.connect(_on_load_slot_chosen)
	ss.slot_chosen.connect(func(_s: int, _m: String) -> void: ss.queue_free())


func _on_load_slot_chosen(slot: int, _mode: String) -> void:
	if not SaveSystem.load_slot(slot):
		status.text = "Load failed."
		return
	close()
	GameManager.resume_overworld()


func _on_quit() -> void:
	# Best-effort auto-save before leaving.
	SaveSystem.save_active()
	SaveSystem.clear_active()
	get_tree().paused = false
	visible = false
	GameManager.state = GameManager.State.MENU
	get_tree().change_scene_to_packed(MAIN_MENU)


func _wire_ui_sfx() -> void:
	for b in find_children("*", "Button", true, false):
		(b as Button).focus_entered.connect(_on_button_focus)
		(b as Button).pressed.connect(_on_button_select)


func _on_button_focus() -> void:
	AudioManager.play_sfx("menu_move")


func _on_button_select() -> void:
	AudioManager.play_sfx("menu_select")
