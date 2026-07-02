extends GutTest

func test_build_creates_hud():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 6
	ld.height = 4
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var hud := rt.find_child("HUD", true, false)
	assert_not_null(hud, "HUD canvas layer created")
	var label := hud.find_child("HUDLabel", true, false) if hud != null else null
	assert_not_null(label, "HUD label present")
	assert_eq(label.text, "Score: 0   Ammo: 5   HP: 3", "HUD reflects initial player state")


func after_each():
	GameManager.register_episodes()
