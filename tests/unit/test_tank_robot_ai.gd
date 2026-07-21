extends GutTest


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	var score: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)
	func add_score(amount: int) -> void:
		score += amount


func _fake_player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	return p


func _new_tank() -> TankRobot:
	var t := TankRobot.new()
	add_child_autofree(t)
	return t


func _new_tank_from_scene() -> TankRobot:
	return add_child_autofree(load("res://src/runtime/entities/tank_robot.tscn").instantiate())


func test_scene_loads_with_required_sprites():
	var t := _new_tank_from_scene()
	assert_true(t is TankRobot, "scene root runs TankRobot script")
	assert_true(t.has_node("Moving"), "scene has Moving sprite (wander anim)")
	assert_true(t.has_node("Idle"), "scene has Idle sprite (turn anim)")


func test_should_fire_threshold():
	var t := _new_tank()
	t.fire_chance = 0.5
	assert_true(t._should_fire(0.49), "roll below chance -> fire")
	assert_false(t._should_fire(0.5), "roll at chance -> no fire (strict less-than)")
	assert_false(t._should_fire(0.7), "roll above chance -> no fire")


func test_should_reverse_threshold():
	var t := _new_tank()
	t.turn_reverse_chance = 0.5
	assert_true(t._should_reverse(0.4), "roll below chance -> reverse")
	assert_false(t._should_reverse(0.6), "roll above chance -> keep facing")


func test_next_walk_time_in_range():
	var t := _new_tank()
	t.walk_time_min = 2.0
	t.walk_time_max = 4.0
	for i in 30:
		var w: float = t._next_walk_time()
		assert_true(w >= 2.0 and w <= 4.0, "walk time within [min, max], got %f" % w)


func test_walk_phase_moves_in_patrol_dir():
	var t := _new_tank()
	t._dir = 1
	t.patrol_speed = 80.0
	t._enter_walk()
	t._tick_wander(0.016)
	assert_eq(t.velocity.x, 80.0, "walk phase applies patrol velocity")
	assert_eq(t._phase, TankRobot.Phase.WALK, "still walking")


func test_walk_phase_enters_stop_when_timer_expires():
	var t := _new_tank()
	t._dir = 1
	t.stop_time = 1.0
	t._enter_walk()
	t._phase_timer = 0.01
	t._tick_wander(0.1)
	assert_eq(t._phase, TankRobot.Phase.STOP, "expired walk -> stop")
	assert_eq(t._state, Enemy.State.IDLE, "stop maps to base IDLE")
	assert_eq(t.velocity.x, 0.0, "halted during stop")


func test_stop_phase_fires_when_roll_hits():
	# Inject a fire roll that forces a shot, then tick once: a Projectile child
	# must be spawned under the tank's parent.
	var t := _new_tank()
	t._dir = 1
	t._enter_stop()
	t._fire_roll = 0.0  # below any fire_chance > 0 -> guaranteed shot
	t.fire_chance = 0.7
	t._tick_wander(0.016)
	assert_true(t._fired_this_stop, "stop with passing roll marks fired")
	var found := false
	for c in t.get_parent().get_children():
		if c is Projectile:
			found = true
			break
	assert_true(found, "projectile spawned when roll passes")


func test_stop_phase_skips_fire_when_roll_misses():
	var t := _new_tank()
	t._dir = 1
	t._enter_stop()
	t._fire_roll = 0.99  # above fire_chance
	t.fire_chance = 0.5
	t._fired_this_stop = false
	t._tick_wander(0.016)
	assert_false(t._fired_this_stop, "roll above chance -> no fire this stop")


func test_stop_phase_enters_turn_when_timer_expires():
	var t := _new_tank()
	t._dir = 1
	t.turn_time = 0.4
	t._enter_stop()
	t._phase_timer = 0.01
	t._tick_wander(0.1)
	assert_eq(t._phase, TankRobot.Phase.TURN, "expired stop -> turn")


func test_turn_phase_reverses_dir_when_roll_hits():
	var t := _new_tank()
	t._dir = 1
	t.turn_reverse_chance = 1.0  # always reverse
	t._enter_turn()
	assert_eq(t._dir, -1, "reversed on turn entry when roll forces it")


func test_turn_phase_keeps_dir_when_roll_misses():
	var t := _new_tank()
	t._dir = 1
	# _enter_turn rolls randf() internally; force the decision via direct call.
	t.turn_reverse_chance = 0.0
	t._enter_turn()
	assert_eq(t._dir, 1, "no reverse when chance is 0")


func test_turn_phase_enters_walk_when_timer_expires():
	var t := _new_tank()
	t._enter_turn()
	t._phase_timer = 0.01
	t._tick_wander(0.1)
	assert_eq(t._phase, TankRobot.Phase.WALK, "expired turn -> walk")
	assert_eq(t._state, Enemy.State.WALK, "walk maps to base WALK")


func test_sync_visual_walk_shows_moving_hides_idle():
	var t := _new_tank_from_scene()
	t._phase = TankRobot.Phase.WALK
	t._dir = 1
	t._sync_visual()
	var moving := t.get_node("Moving") as AnimatedSprite2D
	var idle := t.get_node("Idle") as AnimatedSprite2D
	assert_true(moving.visible, "Moving shown during WALK")
	assert_false(idle.visible, "Idle hidden during WALK")


func test_sync_visual_stop_shows_moving_hides_idle():
	var t := _new_tank_from_scene()
	t._phase = TankRobot.Phase.STOP
	t._dir = 1
	t._sync_visual()
	var moving := t.get_node("Moving") as AnimatedSprite2D
	var idle := t.get_node("Idle") as AnimatedSprite2D
	assert_true(moving.visible, "Moving still shown during STOP (frozen)")
	assert_false(idle.visible, "Idle hidden during STOP")


func test_sync_visual_turn_shows_idle_hides_moving():
	var t := _new_tank_from_scene()
	t._phase = TankRobot.Phase.TURN
	t._dir = -1
	t._sync_visual()
	var moving := t.get_node("Moving") as AnimatedSprite2D
	var idle := t.get_node("Idle") as AnimatedSprite2D
	assert_false(moving.visible, "Moving hidden during TURN")
	assert_true(idle.visible, "Idle shown during TURN")
	assert_true(idle.flip_h, "Idle flips when facing left")


func test_sync_visual_flips_moving_with_facing():
	var t := _new_tank_from_scene()
	t._phase = TankRobot.Phase.WALK
	t._dir = -1
	t._sync_visual()
	var moving := t.get_node("Moving") as AnimatedSprite2D
	assert_true(moving.flip_h, "Moving flips when facing left")
	t._dir = 1
	t._sync_visual()
	assert_false(moving.flip_h, "Moving faces right when _dir positive")


func test_tank_robot_is_invincible_to_damage():
	var t := _new_tank_from_scene()
	var hp_before := t.health
	t.take_damage(99)
	assert_eq(t.health, hp_before, "armored: take_damage is a no-op")
	assert_false(t.is_queued_for_deletion(), "not freed by damage")


func test_tank_robot_cannot_be_stunned():
	var t := _new_tank_from_scene()
	t.velocity.x = 200.0
	var state_before: int = t._state
	t.stun(4.0)
	assert_false(t._stunned, "stun is a no-op")
	assert_eq(t._state, state_before, "state unchanged by stun")
	assert_eq(t.velocity.x, 200.0, "not frozen by stun")


func test_contact_instakills_player():
	var t := _new_tank_from_scene()
	var p := _fake_player()
	assert_eq(p.health, 3, "starts at 3 hp")
	t._handle_player(p)
	assert_eq(p.health, 0, "tank robot contact drains all health")


func test_contact_killed_no_score_award():
	# Tank Robot cannot be defeated, so its score_value stays 0; we verify the
	# property default so designers don't accidentally make it reward score for
	# a kill that can never happen.
	var t := _new_tank_from_scene()
	assert_eq(t.score_value, 0, "no score awarded (undefeatable)")


func test_projectile_tank_robot_variant_sets_mask_and_sprite():
	# Spawn a Projectile with the TANK_ROBOT variant and verify _ready masks the
	# player bit + tiles and shows only the "Tank Robot" sprite.
	var proj: Projectile = load("res://src/runtime/player/projectile.tscn").instantiate()
	proj.variant = Projectile.Variant.TANK_ROBOT
	add_child_autofree(proj)
	# Enemy bolt mask: player (1) + tiles (4) = 5.
	assert_eq(proj.collision_mask, 5, "Tank Robot bolt targets player + tiles")
	var tank_sprite := proj.get_node_or_null("Tank Robot") as Sprite2D
	var player_sprite := proj.get_node_or_null("Player") as Sprite2D
	assert_not_null(tank_sprite, "Tank Robot sprite present")
	assert_true(tank_sprite.visible, "Tank Robot sprite shown for enemy bolt")
	assert_false(player_sprite.visible, "Player sprite hidden for enemy bolt")


func test_projectile_player_variant_masks_enemies():
	var proj: Projectile = load("res://src/runtime/player/projectile.tscn").instantiate()
	proj.variant = Projectile.Variant.PLAYER
	add_child_autofree(proj)
	# Player bolt mask: enemies (2) + tiles (4) = 6.
	assert_eq(proj.collision_mask, 6, "Player bolt targets enemies + tiles")


func test_projectile_launch_flips_sprite_for_left_travel():
	var proj: Projectile = load("res://src/runtime/player/projectile.tscn").instantiate()
	proj.variant = Projectile.Variant.TANK_ROBOT
	add_child_autofree(proj)
	proj.launch(-1)
	var tank_sprite := proj.get_node_or_null("Tank Robot") as Sprite2D
	assert_true(tank_sprite.flip_h, "left launch flips Tank Robot sprite")
	assert_lt(proj.velocity.x, 0.0, "travels left")


func test_tank_robot_registered_in_keen1_episode():
	GameManager.register_episodes()
	var entry: Dictionary = EntityRegistry.get_entry("keen1.tank_robot")
	assert_eq(entry.get("type_id"), "keen1.tank_robot", "tank robot registered")
	assert_eq(entry.get("category"), EntityRegistry.CATEGORY_HAZARD, "filed as hazard")
	assert_not_null(entry.get("scene"), "scene bound")


func after_each():
	GameManager.register_episodes()
