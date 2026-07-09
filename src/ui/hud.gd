class_name Hud
extends Control
## Heads-up display. Two modes:
##   LEVEL     — hearts (health) + ammo shots + score
##   OVERWORLD — "Levels cleared: N / M"
## Instantiated by LevelRuntime._build_hud(). Setters are called both to seed
## initial values and from the player's score/ammo/health signals.

enum Mode { LEVEL, OVERWORLD }

const HEART_FULL  := preload("res://assets/sprites/hud/heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/hud/heart_empty.png")
const AMMO_FULL   := preload("res://assets/sprites/hud/ammo_full.png")
const AMMO_EMPTY  := preload("res://assets/sprites/hud/ammo_empty.png")
const ICON_SIZE   := 16


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
