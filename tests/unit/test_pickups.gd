extends GutTest

class FakePlayer extends Node:
	var score: int = 0
	var ammo: int = 0
	var max_ammo: int = 5
	func _ready() -> void:
		add_to_group("player")
	func add_score(a: int) -> void:
		score += a
	func add_ammo(a: int) -> void:
		ammo = clampi(ammo + a, 0, max_ammo)


func test_candy_awards_score():
	var c: Candy = add_child_autofree(load("res://src/runtime/entities/candy.tscn").instantiate())
	assert_eq(c.score_value, 100)
	var p := FakePlayer.new()
	add_child_autofree(p)
	c._on_body_entered(p)
	assert_eq(p.score, 100)
	assert_true(c.is_queued_for_deletion())


func test_raygun_grants_ammo():
	var r: AmmoPickup = add_child_autofree(load("res://src/runtime/entities/ammo_pickup.tscn").instantiate())
	assert_eq(r.ammo_value, 5)
	var p := FakePlayer.new()
	p.ammo = 1
	add_child_autofree(p)
	r._on_body_entered(p)
	assert_eq(p.ammo, 5, "ammo granted and clamped to max")
	assert_true(r.is_queued_for_deletion(), "pickup frees after use")


func after_each():
	GameManager.register_episodes()
