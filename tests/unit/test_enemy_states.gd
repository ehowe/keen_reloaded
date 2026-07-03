extends GutTest


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	var score: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health -= amount
	func add_score(amount: int) -> void:
		score += amount


func _new_enemy() -> Enemy:
	var e := Enemy.new()
	add_child_autofree(e)
	return e


func _add_sprite(enemy: Node, pname: String) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.name = pname
	enemy.add_child(s)
	return s


func test_visual_active_node_matches_state():
	var e := _new_enemy()
	var walk := _add_sprite(e, "Walking")
	var idle := _add_sprite(e, "Idle")
	var stunned := _add_sprite(e, "Stunned")
	var shot := _add_sprite(e, "Shot")
	e._cache_sprites()

	e._dir = 1
	e._state = Enemy.State.WALK
	e._sync_visual()
	assert_true(walk.visible, "Walking visible in WALK")
	assert_false(idle.visible, "Idle hidden in WALK")
	assert_true(walk.flip_h, "Walking flips when _dir>0")

	e._state = Enemy.State.IDLE
	e._sync_visual()
	assert_true(idle.visible, "Idle visible in IDLE")
	assert_false(walk.visible, "Walking hidden in IDLE")

	e._state = Enemy.State.STUNNED
	e._sync_visual()
	assert_true(stunned.visible, "Stunned visible in STUNNED")

	e._state = Enemy.State.SHOT
	e._sync_visual()
	assert_true(shot.visible, "Shot visible in SHOT")


func test_cache_sprites_drops_placeholder_visual():
	var e := _new_enemy()
	# Entity._ready built a fallback ColorRect named "Visual".
	assert_true(e.has_node("Visual"), "placeholder Visual exists")
	_add_sprite(e, "Walking")
	_add_sprite(e, "Idle")
	_add_sprite(e, "Stunned")
	_add_sprite(e, "Shot")
	e._cache_sprites()
	await get_tree().process_frame  # let queue_free take effect
	assert_false(e.has_node("Visual"), "placeholder Visual removed once sprites exist")
