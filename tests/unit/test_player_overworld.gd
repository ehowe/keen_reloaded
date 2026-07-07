extends GutTest


func _new_player() -> Player:
	var p: Player = add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())
	return p


func test_default_mode_is_level():
	var p := _new_player()
	assert_eq(p._mode, Player.Mode.LEVEL, "player starts in LEVEL mode")


func test_set_mode_flips_to_overworld():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	assert_eq(p._mode, Player.Mode.OVERWORLD, "set_mode(OVERWORLD) flips mode")


func test_overworld_dir_defaults_down():
	var p := _new_player()
	assert_eq(p._overworld_dir, Player.Direction.DOWN, "default overworld facing is DOWN")
