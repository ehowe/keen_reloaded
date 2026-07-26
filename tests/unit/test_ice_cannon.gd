extends GutTest

## Tests for the IceCannon hazard: facing selection, direction-vector math
## for all eight sprites, solid-body/no-contact-area construction, timer
## wiring, and fire-spawns-projectile-at-muzzle.


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)


func _new_cannon(facing: String = "UpRight") -> IceCannon:
	var c: IceCannon = load("res://src/runtime/entities/ice_cannon.tscn").instantiate()
	c.setup("keen1.ice_cannon", {"facing": facing})
	add_child_autofree(c)
	return c


## Table of expected normalized direction vectors per sprite, derived from
## the projectile_vector metadata (degrees, 0=up, CCW visually):
##   dir = Vector2(-sin(rad), -cos(rad))
const _DIRECTIONS := {
	"Up": [0.0, -1.0],
	"Left": [-1.0, 0.0],
	"Down": [0.0, 1.0],
	"Right": [1.0, 0.0],
	"UpRight": [0.7071067811865476, -0.7071067811865476],
	"UpLeft": [-0.7071067811865476, -0.7071067811865476],
	"DownRight": [0.7071067811865476, 0.7071067811865476],
	"DownLeft": [-0.7071067811865476, 0.7071067811865476],
}


func test_facing_selects_exactly_one_matching_sprite():
	for facing in _DIRECTIONS.keys():
		var c := _new_cannon(facing)
		var visible_names: Array[String] = []
		for child in c.get_children():
			if child is Sprite2D and child.visible:
				visible_names.append(String(child.name))
		assert_eq(visible_names.size(), 1, "%s: exactly one sprite visible" % facing)
		assert_eq(visible_names[0].to_lower(), facing.to_lower(),
			"%s: visible sprite name matches facing" % facing)


func test_direction_vector_for_each_facing_sprite():
	# Read each sprite's metadata and verify _read_direction produces the
	# expected normalized vector. Covers all eight directions.
	var c := _new_cannon()
	for child in c.get_children():
		if not (child is Sprite2D):
			continue
		var name := String(child.name)
		if not _DIRECTIONS.has(name):
			continue
		var expected: Array = _DIRECTIONS[name]
		var got := c._read_direction(child)
		assert_almost_eq(got.x, expected[0], 0.0001, "%s direction.x" % name)
		assert_almost_eq(got.y, expected[1], 0.0001, "%s direction.y" % name)


func test_read_start_offset_reads_metadata():
	var c := _new_cannon()
	# UpRight sprite carries PackedInt32Array(32, 32).
	var up_right := c.get_node("UpRight") as Sprite2D
	var off := c._read_start_offset(up_right)
	assert_eq(off, Vector2(32, 32), "UpRight muzzle offset read from metadata")


func test_body_is_solid_and_has_no_contact_area():
	var c := _new_cannon()
	assert_eq(c.collision_layer, 4, "body on tiles bit so Keen collides with it")
	assert_eq(c.collision_mask, 0, "body mask zero (static)")
	var body_col: CollisionShape2D = null
	var has_contact_area := false
	for child in c.get_children():
		if body_col == null and child is CollisionShape2D:
			body_col = child
		if child is Area2D:
			has_contact_area = true
	assert_not_null(body_col, "body has a direct CollisionShape2D child")
	assert_true(body_col.shape is RectangleShape2D, "body shape is RectangleShape2D")
	assert_eq((body_col.shape as RectangleShape2D).size, Vector2(128, 128),
		"body shape covers the 128px cannon footprint")
	assert_false(has_contact_area,
		"no contact Area2D — cannon body does not kill Keen (only the projectile does)")


func test_timer_configured_for_period():
	var c := _new_cannon()
	var timer: Timer = null
	for child in c.get_children():
		if child is Timer:
			timer = child
			break
	assert_not_null(timer, "Timer child built by _ready")
	assert_almost_eq(timer.wait_time, 1.0, 0.001, "default period is 1.0s")
	assert_false(timer.one_shot, "timer loops (periodic firing)")
	# NOTE: Godot CONSUMES the `autostart` flag once the node enters the tree,
	# so timer.autostart reads false here. Verify the timer actually started
	# automatically instead (time_left is set by start()).
	assert_true(timer.time_left > 0.0, "timer autostarted on ready (is running)")


func test_period_export_overrides_wait_time():
	# Drive period through setup() properties (the real contract) instead of
	# re-calling _ready(). Entity.setup() applies matching keys via set(), so
	# @export period flows through before _ready() builds the Timer.
	var c: IceCannon = load("res://src/runtime/entities/ice_cannon.tscn").instantiate()
	c.setup("keen1.ice_cannon", {"facing": "UpRight", "period": 2.5})
	add_child_autofree(c)
	var timer: Timer = null
	for child in c.get_children():
		if child is Timer:
			timer = child
			break
	assert_not_null(timer, "Timer built")
	assert_almost_eq(timer.wait_time, 2.5, 0.001, "period property drives Timer.wait_time")


func test_fire_spawns_projectile_at_muzzle_with_velocity():
	var c := _new_cannon("UpRight")
	c.global_position = Vector2(100, 100)
	var parent := c.get_parent()
	var before := parent.get_child_count()
	c._fire()
	assert_eq(parent.get_child_count(), before + 1, "_fire spawns one sibling")
	var proj := parent.get_child(parent.get_child_count() - 1)
	assert_true(proj is IceCannonProjectile, "sibling is IceCannonProjectile")
	# UpRight muzzle offset (32,32) + cannon pos (100,100) = (132,132).
	assert_eq(proj.global_position, Vector2(132, 132), "projectile spawned at muzzle offset")
	# UpRight direction (315 deg) * speed (300) = (212.13, -212.13).
	var expected_speed := c.projectile_speed
	assert_almost_eq(proj.velocity.x, 0.7071067811865476 * expected_speed, 0.01, "velocity.x")
	assert_almost_eq(proj.velocity.y, -0.7071067811865476 * expected_speed, 0.01, "velocity.y")


func test_handle_player_is_noop():
	# The cannon builds no contact Area2D, so _handle_player is never
	# invoked at runtime; verify the guard neither crashes nor damages.
	var c := _new_cannon()
	var player := FakePlayer.new()
	add_child_autofree(player)
	c._handle_player(player)
	assert_eq(player.health, 3, "cannon contact does not damage player")
