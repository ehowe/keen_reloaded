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


func test_vorticon_has_four_hp_and_awards_score():
	var v: Vorticon = add_child_autofree(load("res://src/runtime/entities/vorticon.tscn").instantiate())
	assert_eq(v.health, 4, "vorticon starts at 4 hp")
	v.score_value = 300
	var p := _fake_player()
	v.take_damage(1)
	assert_eq(v.health, 3)
	assert_false(v.is_queued_for_deletion(), "alive after 1 hit")
	v.take_damage(1)
	v.take_damage(1)
	assert_false(v.is_queued_for_deletion(), "alive after 3 hits")
	# 4th hit triggers the Shot animation death path (deferred 0.6s by _die timer).
	v.take_damage(1)
	assert_true(v._dying, "dying flag set on fourth hit")
	assert_eq(v._state, Enemy.State.SHOT, "enters SHOT state for death animation")
	v._die()  # simulate the deferred timer firing
	assert_eq(p.score, 300, "score awarded on death")
	assert_true(v.is_queued_for_deletion() or not v.is_physics_processing(),
			"removed or frozen as corpse")


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


func test_spike_instakills_on_contact():
	# Spike is a stationary instakill hazard (drains all health), like the Clapper.
	var s = add_child_autofree(load("res://src/runtime/entities/spike.tscn").instantiate())
	var p := _fake_player()
	assert_eq(p.health, 3, "fake player starts at 3 hp")
	s._handle_player(p)
	assert_eq(p.health, 0, "spike drains all health on contact (instakill)")


func test_spike_facing_left_shows_left_variant():
	# The facing enum variant selects which AnimatedSprite2D child is visible.
	GameManager.register_episodes()
	var s = add_child_autofree(load("res://src/runtime/entities/spike.tscn").instantiate())
	s.setup("keen1.spike", {"facing": "left"})
	assert_true(_find_node_named(s, "SpikeLeft").visible, "left variant visible")
	assert_false(_find_node_named(s, "Spike Right").visible, "right variant hidden")


func test_spike_facing_right_shows_right_variant():
	GameManager.register_episodes()
	var s = add_child_autofree(load("res://src/runtime/entities/spike.tscn").instantiate())
	s.setup("keen1.spike", {"facing": "right"})
	assert_true(_find_node_named(s, "Spike Right").visible, "right variant visible")
	assert_false(_find_node_named(s, "SpikeLeft").visible, "left variant hidden")


func test_spike_invincible_to_shots():
	var s = add_child_autofree(load("res://src/runtime/entities/spike.tscn").instantiate())
	assert_false(s.has_method("take_damage"), "spike has no take_damage -> projectiles pass through")


func _find_node_named(root: Node, want: String) -> Node:
	for c in root.get_children():
		if String(c.name) == want:
			return c
		var deeper := _find_node_named(c, want)
		if deeper != null:
			return deeper
	return null


func after_each():
	GameManager.register_episodes()
