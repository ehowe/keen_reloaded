class_name Hud
extends Control
## Heads-up display. Two modes:
##   LEVEL     — hearts (health) + ammo shots + score
##   OVERWORLD — "Levels cleared: N / M" + inventory bar
## Instantiated by LevelRuntime._build_hud(). Setters are called both to seed
## initial values and from the player's score/ammo/health signals.

enum Mode { LEVEL, OVERWORLD }

const HEART_FULL  := preload("res://assets/sprites/hud/heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/hud/heart_empty.png")
const AMMO_FULL   := preload("res://assets/sprites/hud/ammo_full.png")
const AMMO_EMPTY  := preload("res://assets/sprites/hud/ammo_empty.png")
const ICON_SIZE   := 16

# --- Overworld inventory icons ---
const RAYGUN_TEX    := preload("res://assets/sprites/hud/raygun.png")
const KEEN_HEAD_TEX := preload("res://assets/sprites/hud/keen_head.png")
const POGO_TEX      := preload("res://assets/sprites/hud/pogo.png")
const JOYSTICK_TEX  := preload("res://assets/sprites/hud/joystick.png")
const BATTERY_TEX   := preload("res://assets/sprites/hud/battery.png")
const VACUUM_TEX    := preload("res://assets/sprites/hud/vacuum.png")
const EVERCLEAR_TEX := preload("res://assets/sprites/hud/everclear.png")

# Modulation for greyed-out (not-yet-owned) item icons.
const DIM_MODULATE := Color(0.22, 0.22, 0.25, 0.5)

# Ordered item-id -> texture map for the icon-only inventory slots.
const OVERWORLD_ITEM_TEX := {
	ItemIDs.POGO: POGO_TEX,
	ItemIDs.JOYSTICK: JOYSTICK_TEX,
	ItemIDs.BATTERY: BATTERY_TEX,
	ItemIDs.VACUUM: VACUUM_TEX,
	ItemIDs.EVERCLEAR: EVERCLEAR_TEX,
}

# Deterministic left-to-right display order.
const OVERWORLD_ITEM_ORDER := [
	ItemIDs.POGO,
	ItemIDs.JOYSTICK,
	ItemIDs.BATTERY,
	ItemIDs.VACUUM,
	ItemIDs.EVERCLEAR,
]

var _ammo_label: Label
var _life_label: Label
var _item_icons: Dictionary = {}  # item_id -> TextureRect


func _ready() -> void:
	_build_overworld_inventory()
	Inventory.item_collected.connect(_on_item_collected)


func _exit_tree() -> void:
	if Inventory != null and Inventory.item_collected.is_connected(_on_item_collected):
		Inventory.item_collected.disconnect(_on_item_collected)


func _on_item_collected(item_id: String) -> void:
	if OVERWORLD_ITEM_TEX.has(item_id):
		set_item_owned(item_id, true)


func set_mode(m: Mode) -> void:
	$LevelContainer.visible = (m == Mode.LEVEL)
	$OverworldContainer.visible = (m == Mode.OVERWORLD)


func set_health(hp: int, max_hp: int) -> void:
	_fill_row($LevelContainer/HeartsRow, max_hp, hp, HEART_FULL, HEART_EMPTY)


func set_ammo(ammo: int, max_ammo: int) -> void:
	_fill_row($LevelContainer/AmmoRow, max_ammo, ammo, AMMO_FULL, AMMO_EMPTY)


func set_score(score: int) -> void:
	$LevelContainer/ScoreLabel.text = "Score %d" % score


func set_cleared(cleared: int, total: int) -> void:
	$OverworldContainer/ClearedLabel.text = "Levels cleared: %d / %d" % [cleared, total]


func set_overworld_ammo(ammo: int) -> void:
	if _ammo_label:
		_ammo_label.text = "x%d" % ammo


func set_overworld_lives(lives: int) -> void:
	if _life_label:
		_life_label.text = "x%d" % lives


func set_item_owned(item_id: String, owned: bool) -> void:
	var icon: TextureRect = _item_icons.get(item_id)
	if icon:
		icon.modulate = Color.WHITE if owned else DIM_MODULATE


## Build the overworld inventory bar: ammo count | lives count | item icons.
## Icons start dimmed (not owned); call set_item_owned() to brighten.
func _build_overworld_inventory() -> void:
	var row: HBoxContainer = $OverworldContainer/InventoryRow
	# Ammo count: raygun icon + "x N"
	_ammo_label = _add_count_slot(row, RAYGUN_TEX)
	row.add_child(VSeparator.new())
	# Life count: keen head icon + "x N"
	_life_label = _add_count_slot(row, KEEN_HEAD_TEX)
	row.add_child(VSeparator.new())
	# Item icons (dimmed until owned)
	for item_id in OVERWORLD_ITEM_ORDER:
		var tex: Texture2D = OVERWORLD_ITEM_TEX[item_id]
		var icon := _make_icon(tex)
		icon.modulate = DIM_MODULATE
		row.add_child(icon)
		_item_icons[item_id] = icon


func _add_count_slot(row: HBoxContainer, tex: Texture2D) -> Label:
	var icon := _make_icon(tex)
	row.add_child(icon)
	var label := Label.new()
	label.text = "x0"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return label


func _make_icon(tex: Texture2D) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## Rebuild `row` with `slots` TextureRects; index < filled uses full_tex, else empty_tex.
func _fill_row(row: HBoxContainer, slots: int, filled: int, full_tex: Texture2D, empty_tex: Texture2D) -> void:
	for c in row.get_children():
		c.free()
	for i in slots:
		var tr := TextureRect.new()
		tr.texture = full_tex if i < filled else empty_tex
		tr.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(tr)
