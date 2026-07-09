extends Control

const MAIN_MENU := preload("res://src/ui/main_menu.tscn")

@onready var list: ItemList = %PackList
@onready var status: Label = %StatusLabel
var dialog: FileDialog


func _ready() -> void:
	%LoadZipButton.pressed.connect(_open_dialog)
	%BackButton.pressed.connect(_back)
	list.item_activated.connect(_on_item_activated)
	_repopulate()


func _repopulate() -> void:
	list.clear()
	var packs := PackLoader.get_packs()
	if packs.is_empty():
		list.add_item("No packs installed. Click Load .zip…")
		return
	for p in packs:
		list.add_item("%s  —  %s  (%d)" % [p.pack_name, p.author, p.levels.size()])


func _open_dialog() -> void:
	if dialog == null:
		dialog = FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.filters = PackedStringArray(["*.zip ; Level Pack"])
		add_child(dialog)
		dialog.file_selected.connect(_on_zip_selected)
	dialog.popup_centered()


func _on_zip_selected(path: String) -> void:
	var r: Dictionary = PackLoader.import_zip(path)
	if r.ok:
		status.text = "Installed %s" % r.pack_id
		status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		status.text = "Error: %s" % r.error
		status.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_repopulate()


func _on_item_activated(idx: int) -> void:
	var packs := PackLoader.get_packs()
	if packs.is_empty() or idx < 0 or idx >= packs.size():
		return
	GameManager.start_pack(packs[idx].pack_id)


func _back() -> void:
	get_tree().change_scene_to_packed(MAIN_MENU)
