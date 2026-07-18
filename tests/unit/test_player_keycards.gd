extends GutTest


func _new_player() -> Player:
	return add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())


func test_keycards_empty_by_default():
	var p := _new_player()
	assert_eq(p.keycards, {}, "fresh Player starts with no keycards")


func test_has_keycard_false_before_add():
	var p := _new_player()
	assert_false(p.has_keycard("red"), "no red keycard before add")


func test_add_keycard_grants_color():
	var p := _new_player()
	p.add_keycard("red")
	assert_true(p.has_keycard("red"), "red keycard granted")


func test_add_keycard_accumulates_count():
	var p := _new_player()
	p.add_keycard("blue")
	p.add_keycard("blue")
	p.add_keycard("blue")
	# has_keycard only tells us count > 0; consume to verify count.
	assert_true(p.consume_keycard("blue"), "first consume ok")
	assert_true(p.consume_keycard("blue"), "second consume ok")
	assert_true(p.consume_keycard("blue"), "third consume ok")
	assert_false(p.consume_keycard("blue"), "fourth consume fails (empty)")


func test_consume_returns_false_when_empty():
	var p := _new_player()
	assert_false(p.consume_keycard("yellow"), "consume on empty returns false")


func test_consume_decrements_count():
	var p := _new_player()
	p.add_keycard("green")
	p.add_keycard("green")
	assert_true(p.consume_keycard("green"), "consume when count=2")
	assert_true(p.has_keycard("green"), "still has one green after first consume")
	assert_true(p.consume_keycard("green"), "consume when count=1")
	assert_false(p.has_keycard("green"), "no green left after second consume")
	assert_false(p.consume_keycard("green"), "third consume fails")


func test_colors_are_independent():
	var p := _new_player()
	p.add_keycard("red")
	p.add_keycard("blue")
	assert_true(p.has_keycard("red"), "red present")
	assert_true(p.has_keycard("blue"), "blue present")
	assert_false(p.has_keycard("yellow"), "yellow absent")
	p.consume_keycard("red")
	assert_false(p.has_keycard("red"), "red drained")
	assert_true(p.has_keycard("blue"), "blue unaffected by red consume")


func test_each_player_instance_starts_empty():
	# Per-level isolation: two fresh Player instances must NOT share keycard state.
	var p1 := _new_player()
	p1.add_keycard("red")
	var p2 := _new_player()
	assert_false(p2.has_keycard("red"), "second Player instance is isolated")
