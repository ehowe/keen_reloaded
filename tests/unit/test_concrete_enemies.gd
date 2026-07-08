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


func test_yorp_shove_no_damage():
	# Yorp no longer one-shot knocks back; it shoves Keen continuously in
	# _physics_process. Side contact on its own must not damage Keen (harmless)
	# and must not throw him (velocity unchanged by the contact handler itself).
	var y: Yorp = add_child_autofree(load("res://src/runtime/entities/yorp.tscn").instantiate())
	y.global_position = Vector2(100, 0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)
	p.velocity = Vector2(11, 22)
	y._handle_player(p)
	assert_eq(p.velocity, Vector2(11, 22), "side contact does not knockback (shove is per-frame)")
	assert_eq(p.health, 3, "yorp bump does not damage keen")


func test_clapper_instakills_on_contact():
	var c: Clapper = add_child_autofree(load("res://src/runtime/entities/clapper.tscn").instantiate())
	var p := _fake_player()
	assert_eq(p.health, 3, "fake player starts at 3 hp")
	c._handle_player(p)
	assert_eq(p.health, 0, "clapper drains all health on contact (instakill)")


func test_clapper_invincible_to_shots():
	# projectile.gd only damages bodies with a take_damage method. The Clapper
	# must NOT implement it, so blaster bolts pass straight through.
	var c: Clapper = add_child_autofree(load("res://src/runtime/entities/clapper.tscn").instantiate())
	assert_false(c.has_method("take_damage"), "clapper has no take_damage -> projectiles pass through")


func after_each():
	GameManager.register_episodes()
