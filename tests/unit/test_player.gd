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


func test_no_horizontal_air_control():
	var p := _new_player()
	p.velocity.x = 250.0
	# no floor in the test scene -> airborne; Input.get_axis returns 0 (dir=0)
	p._physics_process(0.016)
	assert_almost_eq(p.velocity.x, 250.0, 0.01, "air momentum preserved (no air control)")


func test_max_jump_height_is_three_tiles():
	var p := _new_player()
	var h := p.jump_velocity * p.jump_velocity / (2.0 * p.gravity)
	assert_almost_eq(h, 3.0 * 64.0, 1.0, "full jump apex = 3 tiles")


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
	# sprite 96 tall vs collision 64 tall -> offset.y = -(48 - 32) = -16
	assert_almost_eq(walk.offset.y, -16.0, 0.01, "feet rest on collision bottom")
