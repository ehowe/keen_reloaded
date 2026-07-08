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


func _visible_sprite(p: Player) -> AnimatedSprite2D:
	for n in p.get_children():
		if n is AnimatedSprite2D and (n as AnimatedSprite2D).visible:
			return n
	return null


func test_overworld_shows_down_sprite_by_default():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_not_null(vis, "one sprite visible")
	assert_eq(vis.name, "OverworldDown", "default facing -> OverworldDown visible")


func test_overworld_shows_direction_sprite():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	for dir_name in ["Up", "Down", "Left", "Right"]:
		var dir: int = {
			"Up": Player.Direction.UP,
			"Down": Player.Direction.DOWN,
			"Left": Player.Direction.LEFT,
			"Right": Player.Direction.RIGHT,
		}[dir_name]
		p._overworld_dir = dir
		p._sync_visual()
		var vis := _visible_sprite(p)
		assert_eq(vis.name, "Overworld" + dir_name, "direction %s -> matching sprite visible" % dir_name)


func test_overworld_moving_plays_anim():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._overworld_dir = Player.Direction.RIGHT
	p.velocity = Vector2(p.overworld_speed, 0)  # moving
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_true(vis.is_playing(), "moving -> anim playing")


func test_overworld_stopped_stops_on_frame_zero():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._overworld_dir = Player.Direction.UP
	p.velocity = Vector2(p.overworld_speed, 0)
	p._sync_visual()  # starts playing
	p.velocity = Vector2.ZERO  # now stopped
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_false(vis.is_playing(), "stopped -> anim stopped")
	assert_eq(vis.frame, 0, "stopped -> frame 0")


func test_overworld_no_flip_h():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._overworld_dir = Player.Direction.LEFT
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_false(vis.flip_h, "overworld sprites never flip (each direction has its own)")


func test_overworld_sprite_feet_aligned():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	var down := p.get_node("OverworldDown") as AnimatedSprite2D
	# collision 96 tall (foot_y=48), overworld sprite 64 tall (half=32) -> offset.y = -(32-48) = 16
	assert_almost_eq(down.offset.y, 16.0, 0.5, "overworld sprite feet align to collision bottom")


# Regression: _sync_visual_overworld() previously only touched OVERWORLD_SPRITES,
# so any LEVEL sprite left visible by a prior LEVEL sync would still render in
# OVERWORLD mode. After LEVEL->OVERWORLD transitions, all level sprites must hide.
func test_overworld_mode_hides_all_level_sprites():
	var p := _new_player()
	p._sync_visual()  # LEVEL mode first -> activates a level sprite
	p.set_mode(Player.Mode.OVERWORLD)
	p._sync_visual()
	for name in Player.LEVEL_SPRITES:
		var n := p.get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		assert_false(n.visible, "%s must be hidden in OVERWORLD mode" % name)


func test_overworld_mode_shows_exactly_one_sprite():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._sync_visual()
	var vis_count := 0
	for name in Player.OVERWORLD_SPRITES:
		var n := p.get_node_or_null(name) as AnimatedSprite2D
		if n != null and n.visible:
			vis_count += 1
	assert_eq(vis_count, 1, "exactly one OVERWORLD sprite visible in OVERWORLD mode")
