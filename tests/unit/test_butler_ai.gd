extends GutTest


## Butler subclass with a controllable boundary flag so we can drive _tick_wander
## through wall/ledge transitions without a real tile world.
class FakeButler extends Butler:
	var hit_boundary := false
	func _hit_boundary() -> bool:
		return hit_boundary


func _new_butler() -> FakeButler:
	var b := FakeButler.new()
	add_child_autofree(b)
	return b


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	var bounced_vx: float = 0.0
	var bounced_calls: int = 0
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health -= amount
	func apply_bounce(vx: float) -> void:
		bounced_vx = vx
		bounced_calls += 1


func _fake_player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	return p


func test_walk_keeps_moving_when_unblocked():
	var b := _new_butler()
	b._state = Enemy.State.WALK
	b._dir = 1
	b.patrol_speed = 220.0
	b._tick_wander(0.016)
	assert_eq(b.velocity.x, 220.0, "marches right at patrol_speed")
	assert_eq(b._state, Enemy.State.WALK, "still walking")


func test_walk_left_moves_left_when_unblocked():
	var b := _new_butler()
	b._state = Enemy.State.WALK
	b._dir = -1
	b._tick_wander(0.016)
	assert_eq(b.velocity.x, -220.0, "marches left")


func test_walk_does_not_time_out_into_idle():
	# Butler marches until blocked — long walk time must NOT enter IDLE on its own.
	var b := _new_butler()
	b._state = Enemy.State.WALK
	b._dir = 1
	b._phase_timer = 0.01
	b._tick_wander(1.0)  # way past any phase timer
	assert_eq(b._state, Enemy.State.WALK, "no time-based phase exit")
	assert_eq(b.velocity.x, 220.0, "still marching")


func test_wall_hit_enters_idle_with_pause_timer():
	var b := _new_butler()
	b._state = Enemy.State.WALK
	b._dir = 1
	b.pause_time = 1.5
	b.hit_boundary = true
	b._tick_wander(0.016)
	assert_eq(b._state, Enemy.State.IDLE, "blocked -> pause on idle")
	assert_eq(b.velocity.x, 0.0, "stopped while pausing")
	assert_almost_eq(b._phase_timer, 1.5, 0.001, "pause timer armed")


func test_wall_hit_reverses_dir_after_pause_only():
	# Butler hits wall while walking right; pause keeps facing right (toward the
	# wall it hit). _dir only reverses once the pause timer elapses.
	var b := _new_butler()
	b._state = Enemy.State.WALK
	b._dir = 1
	b.hit_boundary = true
	b._tick_wander(0.016)
	assert_eq(b._dir, 1, "during pause: still facing the wall (right)")
	b.hit_boundary = false
	b._phase_timer = 0.01
	b._tick_wander(0.1)  # pause elapses
	assert_eq(b._dir, -1, "after pause: reversed to march the other way")


func test_idle_resumes_walk_after_pause():
	var b := _new_butler()
	b._state = Enemy.State.IDLE
	b._dir = 1  # facing the wall we just hit
	b._phase_timer = 0.05
	b._tick_wander(0.1)  # pause elapses
	assert_eq(b._state, Enemy.State.WALK, "back to marching after pause")
	assert_eq(b._dir, -1, "reversed on resume")


func test_idle_stops_horizontal_velocity():
	var b := _new_butler()
	b._state = Enemy.State.IDLE
	b._dir = 1
	b.velocity.x = 999.0
	b._phase_timer = 1.0
	b._tick_wander(0.016)
	assert_eq(b.velocity.x, 0.0, "no horizontal motion while pausing")


func test_setup_idle_frames_creates_left_animation():
	var bu: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	var idle := bu.get_node("Idle") as AnimatedSprite2D
	assert_true(idle.sprite_frames.has_animation("default"), "default anim present")
	assert_true(idle.sprite_frames.has_animation("left"), "left (reversed) anim built in _ready")
	# "left" should have same frame count, reversed texture order.
	var default_count := idle.sprite_frames.get_frame_count("default")
	var left_count := idle.sprite_frames.get_frame_count("left")
	assert_eq(left_count, default_count, "left anim has same frame count")
	if default_count >= 2:
		var first_default := idle.sprite_frames.get_frame_texture("default", 0)
		var last_left := idle.sprite_frames.get_frame_texture("left", left_count - 1)
		assert_eq(first_default, last_left, "left anim reverses default order")


func test_sync_visual_picks_left_anim_when_dir_negative():
	var bu: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	var idle := bu.get_node("Idle") as AnimatedSprite2D
	bu._dir = -1
	bu._state = Enemy.State.IDLE
	bu._sync_visual()
	assert_eq(idle.animation, "left", "facing left -> reversed idle anim")
	assert_false(idle.flip_h, "idle never flips (frames encode facing)")


func test_sync_visual_picks_default_anim_when_dir_positive():
	var bu: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	var idle := bu.get_node("Idle") as AnimatedSprite2D
	bu._dir = 1
	bu._state = Enemy.State.IDLE
	bu._sync_visual()
	assert_eq(idle.animation, "default", "facing right -> default idle order (0,1)")
	assert_false(idle.flip_h, "idle never flips")


func test_sync_visual_idle_visible_during_idle_state():
	var bu: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	bu._state = Enemy.State.IDLE
	bu._dir = 1
	bu._sync_visual()
	var idle := bu.get_node("Idle") as AnimatedSprite2D
	assert_true(idle.visible, "Idle sprite shown during IDLE state")
	var walk := bu.get_node("Walking") as AnimatedSprite2D
	assert_false(walk.visible, "Walking hidden during IDLE state")


func test_sync_visual_walking_visible_during_walk_state():
	var bu: Butler = add_child_autofree(load("res://src/runtime/entities/butler.tscn").instantiate())
	bu._state = Enemy.State.WALK
	bu._dir = 1
	bu._sync_visual()
	var walk := bu.get_node("Walking") as AnimatedSprite2D
	assert_true(walk.visible, "Walking sprite shown during WALK state")
	var idle := bu.get_node("Idle") as AnimatedSprite2D
	assert_false(idle.visible, "Idle hidden during WALK state")


func test_push_away_distance_unblocked():
	var b := _new_butler()
	assert_eq(b._push_away_distance(10.0, 1, false), 10.0, "pushes right by overlap")


func test_push_away_distance_zero_when_blocked():
	var b := _new_butler()
	assert_eq(b._push_away_distance(10.0, 1, true), 0.0, "walled -> butler passes through")


func test_push_away_distance_negative_when_dir_left():
	var b := _new_butler()
	assert_eq(b._push_away_distance(10.0, -1, false), -10.0, "pushes left")


func test_should_bounce_fires_on_contact_entry():
	var b := _new_butler()
	assert_true(b._should_bounce(true, false), "first frame of contact -> bounce")


func test_should_bounce_false_while_held():
	var b := _new_butler()
	assert_false(b._should_bounce(true, true), "still touching -> no re-bounce")


func test_side_contact_does_not_damage_or_knockback():
	var b := _new_butler()
	var p := CharacterBody2D.new()
	add_child_autofree(p)
	p.velocity = Vector2(123, 45)
	b._on_side_contact(p)
	assert_eq(p.velocity, Vector2(123, 45), "side contact: no one-shot knockback (shove is per-frame)")


func test_butler_cannot_be_stunned():
	var b := _new_butler()
	b.velocity.x = 200.0
	b.stun(4.0)
	assert_false(b._stunned, "stun is a no-op on butler")
	assert_eq(b._state, Enemy.State.WALK, "state unchanged by stun")
	assert_eq(b.velocity.x, 200.0, "not frozen")


func test_butler_take_damage_no_op():
	var b := _new_butler()
	var health_before := b.health
	b.take_damage(99)
	assert_eq(b.health, health_before, "armored: health unchanged")
	assert_false(b.is_queued_for_deletion(), "not freed")
