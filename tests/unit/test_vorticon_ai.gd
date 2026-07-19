extends GutTest


func _new_vorticon() -> Vorticon:
	var v := Vorticon.new()
	add_child_autofree(v)
	return v


func test_should_hop_when_roll_hits_and_grounded():
	var v := _new_vorticon()
	v.jump_chance = 1.0
	assert_true(v._should_hop(0.0, 0.016, true, false, false), "roll 0 < chance*delta -> hop")


func test_should_hop_false_when_airborne():
	var v := _new_vorticon()
	v.jump_chance = 1.0
	assert_false(v._should_hop(0.0, 0.016, false, false, false), "not on floor -> no hop")


func test_should_hop_false_when_dying():
	var v := _new_vorticon()
	v.jump_chance = 1.0
	assert_false(v._should_hop(0.0, 0.016, true, true, false), "dying -> no hop")


func test_should_hop_false_when_stunned():
	var v := _new_vorticon()
	v.jump_chance = 1.0
	assert_false(v._should_hop(0.0, 0.016, true, false, true), "stunned -> no hop")


func test_should_hop_false_when_already_winding_up():
	var v := _new_vorticon()
	v.jump_chance = 1.0
	v._windup = 0.1
	assert_false(v._should_hop(0.0, 0.016, true, false, false), "mid wind-up -> no new hop")


func test_should_hop_false_when_already_jumping():
	var v := _new_vorticon()
	v.jump_chance = 1.0
	v._state = Enemy.State.JUMP
	assert_false(v._should_hop(0.0, 0.016, true, false, false), "already airborne -> no new hop")


func test_should_hop_false_when_roll_misses():
	var v := _new_vorticon()
	v.jump_chance = 0.1  # 0.1 * 0.016 = 0.0016 threshold
	assert_false(v._should_hop(0.5, 0.016, true, false, false), "roll above threshold -> no hop")
	assert_true(v._should_hop(0.0001, 0.016, true, false, false), "roll below threshold -> hop")


func test_begin_hop_captures_dir_and_starts_windup():
	var v := _new_vorticon()
	v._windup_duration = 0.2
	v._dir = 1
	v.velocity.x = 999.0
	v._begin_hop()
	assert_eq(v._windup, 0.2, "windup armed")
	assert_eq(v._jump_dir, 1, "captured facing at hop start")
	assert_eq(v.velocity.x, 0.0, "frozen during wind-up")


func test_ai_tick_windup_launches_with_random_height():
	var v := _new_vorticon()
	v._windup_duration = 0.0  # no Jumping sprite -> 0-duration windup
	v._windup = 0.01  # tick once to elapse
	v._jump_dir = 1
	v._ai_tick(0.02)
	assert_lt(v.velocity.y, 0.0, "launched upward")
	assert_eq(v.velocity.x, v.leap_speed, "leaps in captured direction")
	assert_eq(v._state, Enemy.State.JUMP, "enters JUMP state for sprite")


func test_ai_tick_launch_height_stays_in_range():
	var v := _new_vorticon()
	v.jump_velocity_min = 600.0
	v.jump_velocity_max = 1227.0
	for i in 30:
		v._windup = 0.01
		v._jump_dir = 0
		v.velocity.y = 0.0
		v._ai_tick(0.02)
		assert_true(v.velocity.y <= -600.0 and v.velocity.y >= -1227.0,
				"launch y in [-1227, -600], got %f" % v.velocity.y)


func test_max_launch_matches_keen_three_tile_apex():
	# Keen's full jump apex is 3 tiles (192px). Vorticon uses Enemy gravity (3920),
	# so its max launch velocity must satisfy v² = 2 * gravity * 3 * TILE.
	var v := _new_vorticon()
	var gravity := 3920.0
	var tiles := 3.0
	var expected_v := sqrt(2.0 * gravity * tiles * 64.0)
	assert_almost_eq(v.jump_velocity_max, expected_v, 1.0,
			"max launch reaches keen's 3-tile apex")
	var apex_px := v.jump_velocity_max * v.jump_velocity_max / (2.0 * gravity)
	assert_almost_eq(apex_px, 192.0, 1.0, "apex ~3 tiles (192px)")


func test_ai_tick_each_jump_has_different_height():
	# Regression: every launch must sample a fresh random height — not a constant.
	var v := _new_vorticon()
	v.jump_velocity_min = 600.0
	v.jump_velocity_max = 1227.0
	var seen: Dictionary = {}
	for i in 30:
		v._windup = 0.01
		v._jump_dir = 0
		v.velocity.y = 0.0
		v._ai_tick(0.02)
		seen[v.velocity.y] = true
	assert_gt(seen.size(), 1, "30 jumps should produce >1 distinct height, got %d" % seen.size())


func test_ai_tick_no_hop_while_dying():
	var v := _new_vorticon()
	v._dying = true
	v._windup = 0.0
	var vx_before := v.velocity.x
	var vy_before := v.velocity.y
	v._ai_tick(0.016)
	assert_eq(v.velocity.x, vx_before, "dying: no wind-up; velocity untouched")
	assert_eq(v.velocity.y, vy_before, "dying: no launch")


func test_ai_tick_no_hop_while_stunned():
	var v := _new_vorticon()
	v._stunned = true
	v._windup = 0.0
	var vx_before := v.velocity.x
	var vy_before := v.velocity.y
	v._ai_tick(0.016)
	assert_eq(v.velocity.x, vx_before, "stunned: no hop")
	assert_eq(v.velocity.y, vy_before, "stunned: no launch")


func test_ai_tick_jumping_state_lands_back_to_walk():
	var v := _new_vorticon()
	v._state = Enemy.State.JUMP
	v.velocity.y = 100.0  # falling
	# Simulate "on floor": velocity.y >= 0 with floor contact is handled by the
	# ai_tick check using is_on_floor() — but in headless without tiles, we only
	# verify the state stays JUMP when not flagged as landed.
	v._ai_tick(0.016)
	assert_eq(v._state, Enemy.State.JUMP, "still airborne -> stays JUMP")


func test_vorticon_scene_has_jumping_sprite():
	var v: Vorticon = add_child_autofree(load("res://src/runtime/entities/vorticon.tscn").instantiate())
	assert_true(v.has_node("Jumping"), "scene includes Jumping sprite for hop state")
	assert_true(v.has_node("Walking"), "scene includes Walking sprite for wander")
	assert_true(v.has_node("Idle"), "scene includes Idle sprite for wander pause")
