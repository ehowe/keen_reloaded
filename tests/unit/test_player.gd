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
