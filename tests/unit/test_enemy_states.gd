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


func test_wander_cycles_walk_then_idle():
	var e := _new_enemy()
	e.walk_time = 0.2
	e.idle_time = 0.1
	e._phase_timer = e.walk_time
	e._state = Enemy.State.WALK
	assert_eq(e._dir, -1, "starts facing left")

	e._tick_wander(0.3)  # walk_time elapsed -> IDLE
	assert_eq(e._state, Enemy.State.IDLE, "enters IDLE after walk_time")
	assert_eq(e.velocity.x, 0.0, "stopped while idle")

	e._tick_wander(0.1)  # idle_time elapsed -> WALK, about-face
	assert_eq(e._state, Enemy.State.WALK, "back to WALK after idle_time")
	assert_eq(e._dir, 1, "reversed facing after idle")


func test_walk_phase_moves_at_patrol_speed():
	var e := _new_enemy()
	e.patrol_speed = 200.0
	e._state = Enemy.State.WALK
	e._phase_timer = 1.0
	e._dir = 1
	e._tick_wander(0.05)
	assert_eq(e.velocity.x, 200.0, "walks right at patrol_speed")


func _fake_player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	return p


func test_stun_freezes_and_marks_state():
	var e := _new_enemy()
	e.velocity.x = 123.0
	e.stun(4.0)
	assert_true(e._stunned, "stunned flag set")
	assert_eq(e._state, Enemy.State.STUNNED, "state STUNNED")
	assert_eq(e._stun_timer, 4.0, "timer set")
	assert_eq(e.velocity.x, 0.0, "frozen")


func test_stun_recovers_after_duration():
	var e := _new_enemy()
	e.stun(0.2)
	assert_true(e._stunned)
	e._physics_process(0.3)  # stun timer elapses
	assert_false(e._stunned, "no longer stunned")
	assert_eq(e._state, Enemy.State.WALK, "resumed walking")


func test_stomp_from_above_stuns_without_damage():
	var e := _new_enemy()
	e.global_position = Vector2(0, 0)
	var p := _fake_player()
	p.global_position = Vector2(0, -40)  # above
	p.velocity = Vector2(0, 500)         # falling
	e._handle_player(p)
	assert_true(e._stunned, "stomped -> stunned")
	assert_eq(e.health, 1, "stomp does not damage enemy")
	assert_eq(p.health, 3, "stomp does not damage player")
	assert_lt(p.velocity.y, 0.0, "player bounced up")


func test_restomp_refreshes_timer():
	var e := _new_enemy()
	e.stun(4.0)
	e._physics_process(1.0)            # timer 4.0 -> 3.0
	var p := _fake_player()
	p.global_position = Vector2(0, -40)
	p.velocity = Vector2(0, 500)
	e._handle_player(p)                # restomp
	assert_almost_eq(e._stun_timer, 4.0, 0.001, "timer refreshed to full")


func test_side_contact_knockback_and_damage():
	var e := _new_enemy()
	e.global_position = Vector2(100, 0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)  # to the right
	p.velocity = Vector2(0, 0)           # not falling
	e._handle_player(p)
	assert_gt(p.velocity.x, 0.0, "knocked right (away from enemy)")
	assert_eq(p.health, 2, "took 1 contact damage")


func test_side_contact_ignored_while_stunned():
	var e := _new_enemy()
	e.global_position = Vector2(100, 0)
	e.stun(4.0)
	var p := _fake_player()
	p.global_position = Vector2(200, 0)
	p.velocity = Vector2(0, 0)
	e._handle_player(p)
	assert_eq(p.health, 3, "harmless while stunned")
	assert_eq(p.velocity.x, 0.0, "no knockback while stunned")
