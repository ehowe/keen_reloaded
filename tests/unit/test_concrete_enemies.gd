extends GutTest

class FakeKinematicPlayer extends CharacterBody2D:
	var health: int = 3
	var score: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health -= amount
	func add_score(amount: int) -> void:
		score += amount


func _fake_player() -> FakeKinematicPlayer:
	var p := FakeKinematicPlayer.new()
	add_child_autofree(p)
	return p


func test_vorticon_has_three_hp_and_awards_score():
	var v: Vorticon = add_child_autofree(load("res://src/runtime/entities/vorticon.tscn").instantiate())
	assert_eq(v.health, 3, "vorticon starts at 3 hp")
	v.score_value = 300
	var p := _fake_player()
	v.take_damage(1)
	assert_eq(v.health, 2)
	assert_false(v.is_queued_for_deletion(), "alive after 1 hit")
	v.take_damage(1)
	v.take_damage(1)
	assert_eq(p.score, 300, "score awarded on third hit")
	assert_true(v.is_queued_for_deletion(), "freed at 0 hp")


func test_butler_is_armored():
	var b: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	b.take_damage(5)
	assert_false(b.is_queued_for_deletion(), "armored butler ignores damage")
	assert_eq(b.health, 1, "health unchanged")


func test_yorp_knockback_no_damage():
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	y.global_position = Vector2(100, 0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)  # player to the right -> knockback +x
	y._handle_player(p)
	assert_gt(p.velocity.x, 0, "knocked right")
	assert_eq(p.health, 3, "yorp bump does not damage keen (knockback only)")


func after_each():
	GameManager.register_episodes()
