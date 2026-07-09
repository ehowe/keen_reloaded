extends GutTest

const HUD_SCENE := preload("res://src/ui/hud.tscn")


func _hud() -> Hud:
	var h := HUD_SCENE.instantiate() as Hud
	add_child_autofree(h)
	return h


func _uses(node: Node, tex: Texture2D) -> bool:
	var tr := node as TextureRect
	return tr != null and tr.texture == tex


func test_set_health_shows_hearts():
	var h := _hud()
	h.set_mode(Hud.Mode.LEVEL)
	h.set_health(2, 3)
	var row := h.get_node("LevelContainer/HeartsRow") as HBoxContainer
	assert_eq(row.get_child_count(), 3, "3 heart slots")
	assert_true(_uses(row.get_child(0), Hud.HEART_FULL), "child 0 full")
	assert_true(_uses(row.get_child(1), Hud.HEART_FULL), "child 1 full")
	assert_true(_uses(row.get_child(2), Hud.HEART_EMPTY), "child 2 empty")


func test_set_ammo_shots():
	var h := _hud()
	h.set_mode(Hud.Mode.LEVEL)
	h.set_ammo(1, 5)
	var row := h.get_node("LevelContainer/AmmoRow") as HBoxContainer
	assert_eq(row.get_child_count(), 5, "5 ammo slots")
	assert_true(_uses(row.get_child(0), Hud.AMMO_FULL), "child 0 full")
	assert_true(_uses(row.get_child(1), Hud.AMMO_EMPTY), "child 1 empty")


func test_set_score_text():
	var h := _hud()
	h.set_mode(Hud.Mode.LEVEL)
	h.set_score(42)
	assert_eq((h.get_node("LevelContainer/ScoreLabel") as Label).text, "Score 42")


func test_set_cleared_text():
	var h := _hud()
	h.set_mode(Hud.Mode.OVERWORLD)
	h.set_cleared(2, 5)
	assert_eq((h.get_node("OverworldContainer/ClearedLabel") as Label).text, "Levels cleared: 2 / 5")


func test_mode_toggles_containers():
	var h := _hud()
	h.set_mode(Hud.Mode.LEVEL)
	assert_true((h.get_node("LevelContainer") as CanvasItem).visible, "LEVEL shows level container")
	assert_false((h.get_node("OverworldContainer") as CanvasItem).visible, "LEVEL hides overworld container")
	h.set_mode(Hud.Mode.OVERWORLD)
	assert_false((h.get_node("LevelContainer") as CanvasItem).visible, "OVERWORLD hides level container")
	assert_true((h.get_node("OverworldContainer") as CanvasItem).visible, "OVERWORLD shows overworld container")
