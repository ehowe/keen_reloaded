extends GutTest

class FakePlayer extends Node:
	var score: int = 0
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func add_score(amount: int) -> void:
		score += amount
	func take_damage(amount: int) -> void:
		health -= amount


func _fake_player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child(p)
	return p


func test_collectible_awards_score_and_frees():
	var c := Collectible.new()
	c.score_value = 250
	add_child(c)
	var p := _fake_player()
	c._on_body_entered(p)
	assert_eq(p.score, 250, "score awarded")
	assert_true(c.is_queued_for_deletion(), "collectible frees on pickup")


func test_hazard_damages_player():
	var h := Hazard.new()
	h.damage = 2
	add_child(h)
	var p := _fake_player()
	h._on_body_entered(p)
	assert_eq(p.health, 1, "took 2 damage from 3")


func test_enemy_contact_damages_player():
	var e := Enemy.new()
	e.contact_damage = 1
	add_child(e)
	var p := _fake_player()
	e._on_body_entered(p)
	assert_eq(p.health, 2)


func test_enemy_take_damage_reduces_health_and_frees_at_zero():
	var e := Enemy.new()
	e.health = 2
	add_child(e)
	e.take_damage(1)
	assert_eq(e.health, 1)
	assert_false(e.is_queued_for_deletion())
	e.take_damage(1)
	assert_eq(e.health, 0)
	assert_true(e.is_queued_for_deletion(), "enemy frees at 0 health")


func test_entity_ignores_non_player_body():
	var c := Collectible.new()
	add_child(c)
	var decoy := Node.new()
	add_child(decoy)
	c._on_body_entered(decoy)  # must not error and must not free
	assert_false(c.is_queued_for_deletion())
