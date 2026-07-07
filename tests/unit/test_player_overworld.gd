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


func test_overworld_applies_no_gravity():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p.velocity = Vector2(0, 0)
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.y, 0.0, 0.01, "no gravity applied in overworld")


func test_overworld_velocity_tracks_input_vector():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_right")
	Input.action_press("move_down")
	p._physics_process(0.016)
	var expected := Vector2(1, 1).normalized() * p.overworld_speed
	assert_almost_eq(p.velocity.x, expected.x, 0.5, "velocity.x = input * overworld_speed")
	assert_almost_eq(p.velocity.y, expected.y, 0.5, "velocity.y = input * overworld_speed")
	Input.action_release("move_right")
	Input.action_release("move_down")


func test_overworld_no_input_zeros_velocity():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p.velocity = Vector2(123, 456)
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, 0.0, 0.01, "no input -> zero velocity")
	assert_almost_eq(p.velocity.y, 0.0, 0.01, "no input -> zero velocity")


func test_overworld_dir_updates_on_dominant_axis_horizontal():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_left")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.LEFT, "pure-left input -> LEFT")
	Input.action_release("move_left")


func test_overworld_dir_updates_on_dominant_axis_vertical():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_up")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.UP, "pure-up input -> UP")
	Input.action_release("move_up")


func test_overworld_dir_prefers_horizontal_on_tie():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_right")  # magnitude tie with up -> horizontal wins
	Input.action_press("move_up")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.RIGHT, "tied magnitude -> horizontal dominant")
	Input.action_release("move_right")
	Input.action_release("move_up")


func test_overworld_dir_persists_when_stopped():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	Input.action_press("move_up")
	p._physics_process(0.016)
	Input.action_release("move_up")
	p._physics_process(0.016)
	assert_eq(p._overworld_dir, Player.Direction.UP, "direction persists after release")


func test_overworld_lock_input_forces_x_axis():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p.lock_input(1.0, 1.0)  # forced rightward
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, p.overworld_speed, 0.5, "locked -> forced x velocity")
	assert_almost_eq(p.velocity.y, 0.0, 0.01, "locked -> no y velocity")
