extends Control
## Reusable slot-select screen. Modes:
##   "new_game" — all slots clickable; occupied → confirm overwrite; corrupt /
##               missing_pack / unsupported_version → delete-only.
##   "continue" — only valid occupied slots are clickable; rest greyed.
##
## On a successful pick, emits signal "slot_chosen(slot: int, mode: String)".
## The parent scene wires the consequence (start episode, load + resume, etc.).
## Back just removes this overlay so the parent underneath reappears.

signal slot_chosen(slot: int, mode: String)

@onready var grid: VBoxContainer = %SlotGrid
@onready var title: Label = %TitleLabel
@onready var back: Button = %BackButton

var mode: String = "new_game"


func _ready() -> void:
	%BackButton.pressed.connect(_on_back)
	_wire_ui_sfx()
	_repopulate()


func set_mode(m: String) -> void:
	mode = m
	if is_inside_tree():
		_repopulate()


## Pure function: build the human-readable label for one slot status entry.
## Unit-tested directly.
func _card_text(entry: Dictionary) -> String:
	var n := int(entry.get("slot", 0))
	var status: String = String(entry.get("status", "empty"))
	match status:
		"empty":
			return "Slot %d — Empty" % n
		"occupied":
			return "Slot %d — %s (%d cleared)" % [n, String(entry.get("scope_title", "?")), int(entry.get("completed_count", 0))]
		"corrupt":
			return "Slot %d — ⚠ Corrupt (click to delete)" % n
		"missing_pack":
			return "Slot %d — ⚠ Pack missing (click to delete)" % n
		"unsupported_version":
			return "Slot %d — ⚠ Unsupported save v%s (click to delete)" % [n, str(entry.get("version", "?"))]
	return "Slot %d — %s" % [n, status]


func _repopulate() -> void:
	for c in grid.get_children():
		c.queue_free()
	var slots := SaveSystem.list_slots()
	for entry in slots:
		var btn := Button.new()
		btn.text = _card_text(entry)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var status: String = entry["status"]
		var clickable := _is_clickable(status)
		btn.disabled = not clickable
		if clickable:
			btn.pressed.connect(_on_slot_pressed.bind(entry))
		btn.focus_entered.connect(_on_button_focus)
		btn.pressed.connect(_on_button_select)
		grid.add_child(btn)


func _is_clickable(status: String) -> bool:
	if mode == "new_game":
		return true  # empty (use), occupied (overwrite), corrupt/missing/unsupported (delete)
	# continue: only valid occupied slots
	return status == "occupied"


func _on_slot_pressed(entry: Dictionary) -> void:
	var status: String = entry["status"]
	var slot_num := int(entry["slot"])
	if status == "occupied" and mode == "new_game":
		# Confirm overwrite.
		var dlg := ConfirmationDialog.new()
		dlg.title = "Overwrite slot %d?" % slot_num
		dlg.dialog_text = "This slot already contains a save. Overwrite?"
		add_child(dlg)
		dlg.confirmed.connect(func() -> void:
			slot_chosen.emit(slot_num, mode)
			dlg.queue_free())
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		dlg.popup_centered()
		return
	if status in ["corrupt", "missing_pack", "unsupported_version"]:
		SaveSystem.delete_slot(slot_num)
		_repopulate()
		return
	# empty (new_game) or occupied (continue)
	slot_chosen.emit(slot_num, mode)


## Remove this overlay; the parent scene underneath reappears (main menu, pause
## menu, or pack select). Works in every context because the parent decides what
## is behind this screen.
func _on_back() -> void:
	queue_free()


func _wire_ui_sfx() -> void:
	for b in find_children("*", "Button", true, false):
		(b as Button).focus_entered.connect(_on_button_focus)
		(b as Button).pressed.connect(_on_button_select)


func _on_button_focus() -> void:
	AudioManager.play_sfx("menu_move")


func _on_button_select() -> void:
	AudioManager.play_sfx("menu_select")
