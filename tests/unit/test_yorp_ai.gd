extends GutTest


func _player_at(x: float) -> Node2D:
	var p := Node2D.new()
	p.add_to_group("player")
	p.global_position = Vector2(x, 0)
	add_child_autofree(p)
	return p


func _new_yorp() -> Yorp:
	var y := Yorp.new()
	add_child_autofree(y)
	return y


func test_choose_dir_seeks_player_when_roll_hits():
	var y := _new_yorp()
	y.seek_chance = 1.0
	y._dir = 1  # so base-reverse (-1) differs from seek-right (+1)
	y.global_position = Vector2(0, 0)
	var p := _player_at(500)
	assert_eq(y._choose_walk_dir(), 1, "heads right toward player")
	p.global_position.x = -500
	assert_eq(y._choose_walk_dir(), -1, "heads left toward player")


func test_choose_dir_falls_back_to_reverse_with_no_player():
	var y := _new_yorp()
	y._dir = -1
	assert_eq(y._choose_walk_dir(), 1, "no player -> reverse (-1 -> 1)")
	y._dir = 1
	assert_eq(y._choose_walk_dir(), -1, "no player -> reverse (1 -> -1)")


func test_detour_roll_returns_valid_dir():
	var y := _new_yorp()
	y.seek_chance = 0.0
	_player_at(500)
	for i in 20:
		var d: int = y._choose_walk_dir()
		assert_true(d == 1 or d == -1, "detour is a valid facing")


func test_phase_times_jitter_within_range():
	var y := _new_yorp()
	y.walk_time = 2.0
	y.idle_time = 1.0
	for i in 20:
		var w: float = y._walk_phase_time()
		assert_true(w >= 1.0 and w <= 3.0, "walk time in [1.0, 3.0]")
		var idl: float = y._idle_phase_time()
		assert_true(idl >= 0.5 and idl <= 1.5, "idle time in [0.5, 1.5]")
