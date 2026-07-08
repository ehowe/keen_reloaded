extends GutTest

func test_score_accumulates():
	var p := Player.new()
	add_child(p)
	p.add_score(100)
	p.add_score(25)
	assert_eq(p.score, 125)

func test_take_damage_reduces_health():
	var p := Player.new()
	add_child(p)
	p.take_damage(1)
	assert_eq(p.health, 2)

func test_player_in_player_group():
	var p := Player.new()
	add_child(p)
	assert_true(p.is_in_group("player"))


func test_apply_bounce_sets_impulse():
	var p := _new_player()
	p.apply_bounce(-440.0)
	assert_eq(p._bounce_vx, -440.0, "bounce impulse stored")


func _new_player() -> Player:
	var p: Player = add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())
	return p


func _visible_sprite(p: Player) -> AnimatedSprite2D:
	for n in p.get_children():
		if n is AnimatedSprite2D and (n as AnimatedSprite2D).visible:
			return n
	return null


func test_sprite_flip_matches_facing():
	var p := _new_player()
	p._facing = -1
	p._sync_visual()
	var vis := _visible_sprite(p)
	assert_not_null(vis, "one sprite visible")
	assert_true(vis.flip_h, "facing left -> flipped")
	p._facing = 1
	p._sync_visual()
	assert_false(vis.flip_h, "facing right -> unflipped")


func test_current_anim_priority():
	var p := _new_player()
	assert_eq(p._current_anim(true, false, false, false, false), "Idle")
	assert_eq(p._current_anim(true, true, false, false, false), "Walking")
	assert_eq(p._current_anim(false, true, false, false, false), "Jumping")
	assert_eq(p._current_anim(true, false, false, false, true), "Jumping", "wind-up shows Jumping while grounded")
	assert_eq(p._current_anim(true, true, true, false, false), "Pogo")
	assert_eq(p._current_anim(true, true, true, true, false), "Shooting")
	assert_eq(p._current_anim(false, false, false, true, false), "Shooting")


func test_jump_anim_duration_matches_frames_over_speed():
	var p := _new_player()
	# 6 frames @ speed 30 -> 0.2s wind-up
	assert_almost_eq(p._jump_anim_duration(), 0.2, 0.001, "wind-up length == anim length")


func test_jump_windup_delays_then_launches():
	var p := _new_player()
	Input.action_press("jump")  # hold so the variable-jump cut doesn't reduce launch velocity
	p._coyote = 0.1
	p._buffer = 0.1
	p._physics_process(0.016)
	assert_gt(p._windup, 0.0, "wind-up started, not launched yet")
	assert_gt(p.velocity.y, -p.jump_velocity, "still grounded during wind-up")
	var frames := 0
	while p._windup > 0.0 and frames < 100:
		p._physics_process(0.016)
		frames += 1
	Input.action_release("jump")
	assert_almost_eq(p.velocity.y, -p.jump_velocity, 1.0, "launches after wind-up elapses")


func test_windup_halts_horizontal_movement():
	var p := _new_player()
	p._windup = 0.1
	p.velocity.x = 250.0
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, 0.0, 0.01, "halted during wind-up")


func test_launch_leaps_in_pre_jump_direction():
	var p := _new_player()
	Input.action_press("move_right")
	Input.action_press("jump")  # hold so variable-jump cut doesn't reduce launch
	p._coyote = 0.1
	p._buffer = 0.1
	p._physics_process(0.016)  # initiates wind-up, captures rightward dir
	assert_eq(p._jump_dir, 1.0, "captured rightward direction at jump press")
	var frames := 0
	while p._windup > 0.0 and frames < 100:
		p._physics_process(0.016)
		frames += 1
	Input.action_release("jump")
	Input.action_release("move_right")
	assert_almost_eq(p.velocity.x, p.leap_speed, 0.01, "launch carries pre-jump direction at leap_speed")


func test_stationary_jump_launches_straight_up():
	var p := _new_player()
	Input.action_press("jump")  # no move input -> dir 0
	p._coyote = 0.1
	p._buffer = 0.1
	p._physics_process(0.016)
	assert_eq(p._jump_dir, 0.0, "no direction captured when stationary")
	var frames := 0
	while p._windup > 0.0 and frames < 100:
		p._physics_process(0.016)
		frames += 1
	Input.action_release("jump")
	assert_almost_eq(p.velocity.x, 0.0, 0.01, "stationary jump launches straight up")


func test_no_horizontal_air_control():
	var p := _new_player()
	p.velocity.x = 250.0
	# no floor in the test scene -> airborne; Input.get_axis returns 0 (dir=0)
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, 250.0, 0.01, "air momentum preserved (no air control)")


func test_moving_jump_allows_slow_air_steer():
	var p := _new_player()
	Input.action_press("move_left")  # steer opposite to launch direction
	p._jumping = true
	p._jump_dir = 1.0
	p.velocity.x = p.leap_speed
	p._physics_process(0.016)
	# steers toward -leap_speed at air_accel: advances by air_accel * delta
	var expected := p.leap_speed - p.air_accel * 0.016
	assert_almost_eq(p.velocity.x, expected, 1.0, "moving jump steers slowly toward input")
	Input.action_release("move_left")


func test_stationary_jump_blocks_air_steer():
	var p := _new_player()
	Input.action_press("move_right")
	p._jumping = true
	p._jump_dir = 0.0
	p.velocity.x = 0.0
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, 0.0, 0.01, "stationary jump: no air control")
	Input.action_release("move_right")


func test_moving_jump_holding_direction_maintains_leap():
	var p := _new_player()
	Input.action_press("move_right")
	p._jumping = true
	p._jump_dir = 1.0
	p.velocity.x = p.leap_speed
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, p.leap_speed, 0.01, "holding leap direction maintains speed")
	Input.action_release("move_right")


func test_max_jump_height_is_three_tiles():
	var p := _new_player()
	var h := p.jump_velocity * p.jump_velocity / (2.0 * p.gravity)
	assert_almost_eq(h, 3.0 * 64.0, 1.0, "full jump apex = 3 tiles")


func test_full_running_jump_distance_is_seven_tiles():
	var p := _new_player()
	# air time for full jump (up + down to launch height) = 2 * jump_velocity / gravity
	var air_time := 2.0 * p.jump_velocity / p.gravity
	var distance := p.leap_speed * air_time
	assert_almost_eq(distance, 7.0 * 64.0, 1.0, "full running jump distance = 7 tiles")


func test_releasing_jump_cuts_ascent():
	var p := _new_player()
	# no input -> jump button released
	p._jumping = true
	p._buffer = 0.0
	p._coyote = -1.0
	p._windup = 0.0
	p.velocity.y = -p.jump_velocity
	p._physics_process(0.016)
	# Extra gravity applied -> velocity bleeds faster than gravity alone
	var gravity_only := -p.jump_velocity + p.gravity * 0.016
	assert_gt(p.velocity.y, gravity_only, "extra gravity cuts ascent faster than gravity alone")


func test_holding_jump_keeps_full_ascent():
	var p := _new_player()
	Input.action_press("jump")
	p._jumping = true
	p._buffer = 0.0
	p._coyote = -1.0
	p._windup = 0.0
	p.velocity.y = -p.jump_velocity
	p._physics_process(0.016)
	Input.action_release("jump")
	# Holding = gravity only, no extra cut gravity
	var gravity_only := -p.jump_velocity + p.gravity * 0.016
	assert_almost_eq(p.velocity.y, gravity_only, 1.0, "no extra gravity when held")


func test_sprite_feet_aligned_to_collision():
	var p := _new_player()
	var walk := p.get_node("Walking") as AnimatedSprite2D
	# sprite 96 tall vs collision 96 tall -> offset.y = -(48 - 48) = 0
	assert_almost_eq(walk.offset.y, 0.0, 0.01, "feet rest on collision bottom")


# Regression: after overworld sprites were added to the player scene, the LEVEL
# display showed an overworld sprite alongside the active level sprite because
# _sync_visual_level() only managed LEVEL_SPRITES (overworld sprites were left
# at whatever visibility the scene/previous mode left them in).
func test_level_mode_hides_all_overworld_sprites():
	var p := _new_player()
	p._sync_visual()
	for name in Player.OVERWORLD_SPRITES:
		var n := p.get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		assert_false(n.visible, "%s must be hidden in LEVEL mode" % name)


func test_level_mode_shows_exactly_one_sprite():
	var p := _new_player()
	p._sync_visual()
	var vis_count := 0
	for name in Player.LEVEL_SPRITES:
		var n := p.get_node_or_null(name) as AnimatedSprite2D
		if n != null and n.visible:
			vis_count += 1
	assert_eq(vis_count, 1, "exactly one LEVEL sprite visible in LEVEL mode")


func test_overworld_to_level_switch_hides_overworld_sprites():
	var p := _new_player()
	p.set_mode(Player.Mode.OVERWORLD)
	p._sync_visual()  # activates an overworld sprite
	p.set_mode(Player.Mode.LEVEL)
	p._sync_visual()
	for name in Player.OVERWORLD_SPRITES:
		var n := p.get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		assert_false(n.visible, "%s must be hidden after switching back to LEVEL" % name)


func test_take_damage_lethal_sets_dead():
	var p := Player.new()
	add_child(p)
	var fired := []
	p.died.connect(func() -> void: fired.append(true))
	p.take_damage(p.health)
	assert_true(p._dead, "health to 0 sets _dead")
	assert_eq(fired.size(), 1, "died emitted exactly once")


func test_take_damage_after_dead_is_noop():
	var p := Player.new()
	add_child(p)
	p._dead = true
	p.health = 5
	var fired := []
	p.died.connect(func() -> void: fired.append(true))
	p.take_damage(3)
	assert_eq(p.health, 5, "health unchanged once dead")
	assert_eq(fired.size(), 0, "no further died emit once dead")


func test_die_sets_upleft_launch_vector():
	var p := _new_player()
	var speed := p.death_launch_speed
	p.take_damage(p.health)
	var rad := deg_to_rad(60.0)
	var expected := Vector2(-cos(rad), -sin(rad)) * speed
	assert_almost_eq(p.velocity.x, expected.x, 0.1, "vx = -speed*cos60")
	assert_almost_eq(p.velocity.y, expected.y, 0.1, "vy = -speed*sin60")


func test_die_disables_collision_shape():
	var p := _new_player()
	var col := p.get_node("CollisionShape2D") as CollisionShape2D
	assert_false(col.disabled, "collision enabled before death")
	p.take_damage(p.health)
	assert_true(col.disabled, "collision disabled on death so Keen flies through walls")


func test_death_launch_speed_default_is_800():
	var p := Player.new()
	assert_eq(p.death_launch_speed, 800.0, "tunable default")
