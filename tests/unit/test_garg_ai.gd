extends GutTest


func _player_at(x: float, y: float = 0.0) -> Node2D:
	var p := Node2D.new()
	p.add_to_group("player")
	p.global_position = Vector2(x, y)
	add_child_autofree(p)
	return p


func _new_garg() -> Garg:
	var g := Garg.new()
	add_child_autofree(g)
	return g


func test_choose_dir_seeks_player_when_seek_roll_hits():
	var g := _new_garg()
	g.seek_chance = 1.0
	g.global_position = Vector2.ZERO
	var p := _player_at(500)
	assert_eq(g._choose_walk_dir(), 1, "heads right toward player")
	p.global_position.x = -500
	assert_eq(g._choose_walk_dir(), -1, "heads left toward player")


func test_choose_dir_returns_valid_dir_when_wandering():
	var g := _new_garg()
	g.seek_chance = 0.0
	_player_at(500)
	for i in 20:
		var d: int = g._choose_walk_dir()
		assert_true(d == 1 or d == -1, "wander is a valid facing")


func test_should_charge_true_when_in_front_same_level():
	var g := _new_garg()
	g.global_position = Vector2.ZERO
	assert_true(g._should_charge(Vector2(300, 0), 29.0, 1), "sees keen ahead on level -> charge")


func test_should_charge_true_when_directly_behind_within_reach():
	# Within one tile the garg lunges even if keen is just behind it.
	var g := _new_garg()
	g.global_position = Vector2.ZERO
	assert_true(g._should_charge(Vector2(-30, 0), 29.0, 1), "close behind -> charge")


func test_should_charge_false_when_out_of_range():
	var g := _new_garg()
	g.global_position = Vector2.ZERO
	assert_false(g._should_charge(Vector2(600, 0), 29.0, 1), "too far -> no charge")


func test_should_charge_false_when_behind_facing():
	var g := _new_garg()
	g.global_position = Vector2.ZERO
	assert_false(g._should_charge(Vector2(-300, 0), 29.0, 1), "behind back -> no charge")


func test_should_charge_false_when_different_level():
	var g := _new_garg()
	g.global_position = Vector2.ZERO
	assert_false(g._should_charge(Vector2(300, 200), 29.0, 1), "different level -> no charge")


func test_should_charge_uses_body_overlap_for_same_level():
	# "Any part of the player" on the level counts: a tall player whose body
	# reaches down into the garg's band is noticed even though its center sits
	# well above the garg; a short player entirely above it is not.
	var g := _new_garg()
	g.global_position = Vector2.ZERO
	assert_true(g._should_charge(Vector2(200, -30), 40.0, 1), "body overlaps level -> charge")
	assert_false(g._should_charge(Vector2(200, -80), 5.0, 1), "no overlap -> no charge")


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	var score: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)
	func add_score(amount: int) -> void:
		score += amount


func test_contact_instakills_player():
	var g := _new_garg()
	var p := FakePlayer.new()
	add_child_autofree(p)
	assert_eq(p.health, 3, "starts at 3 hp")
	g._handle_player(p)
	assert_eq(p.health, 0, "garg contact kills keen")


func test_one_shot_kills_and_awards_score():
	var g := _new_garg()
	var p := FakePlayer.new()
	add_child_autofree(p)
	g.take_damage(1)
	assert_true(g.is_queued_for_deletion(), "1 blaster shot defeats garg")
	assert_eq(p.score, 300, "score awarded on death")
