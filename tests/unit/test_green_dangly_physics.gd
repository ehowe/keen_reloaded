extends GutTest

## Physics integration test for GreenDanglyStuff one-way behavior.
## Verifies that CollisionShape2D.one_way_collision=true on the CharacterBody2D
## root is honored by Godot 4.7 physics when a player-like body interacts.
##
## Two cases:
##   1. Player rising from below -> passes through (no collision)
##   2. Player falling from above -> lands on top (collision blocks)
##
## Player's actual config (verified in player.tscn / player.gd):
##   collision_layer = 1 (player), collision_mask = 4 (tiles).
## Hazard body (green_dangly_stuff.gd _ready): layer=4, mask=0,
## RectangleShape2D 64x64 at body origin -> spans y in [-32, +32].


class FakePlayer extends CharacterBody2D:
	## Minimal player body matching Player's collision bits. NOT in the "player"
	## group so the hazard's kill Area2D body_entered path stays dormant (we
	## only want to test body-vs-body physics here). One-tile box (32x32) for
	## predictable math (half-extent = 16).
	func _ready() -> void:
		collision_layer = 1  # player bit
		collision_mask = 4   # tiles bit
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(32, 32)
		shape.shape = rect
		add_child(shape)


func _make_hazard() -> GreenDanglyStuff:
	var packed := load("res://src/runtime/entities/green_dangly_stuff.tscn") as PackedScene
	var g := add_child_autofree(packed.instantiate()) as GreenDanglyStuff
	g.position = Vector2(0, 0)
	return g


func _make_player(at: Vector2) -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	p.position = at
	return p


func test_player_falling_lands_on_top_of_hazard() -> void:
	# Hazard body covers y in [-32, +32] (full tile centered at 0).
	# Player (32x32) starts above, falls down.
	var _g := _make_hazard()
	var p := _make_player(Vector2(0, -100))
	p.velocity = Vector2(0, 500)  # strong downward
	# Step physics several times so collision can resolve.
	for i in 60:
		p.move_and_slide()
		await get_tree().physics_frame
	# Player should be RESTING on top of the hazard (not have fallen through).
	# Top of hazard is at y = -32; player center rests at y = -32 - 16 = -48.
	assert_lt(p.position.y, -32.0, "player did not fall through (still above hazard top): y=%.2f" % p.position.y)
	assert_gt(p.position.y, -100.0, "player actually fell somewhat (didn't stay at start): y=%.2f" % p.position.y)


func test_player_rising_from_below_passes_through_hazard() -> void:
	# Player starts well below hazard, rises up.
	var _g := _make_hazard()
	var p := _make_player(Vector2(0, 200))
	p.velocity = Vector2(0, -500)  # strong upward
	for i in 80:
		p.move_and_slide()
		await get_tree().physics_frame
	# Player should have passed THROUGH the hazard and ended above it.
	# If one-way is NOT honored, player bonks at y = +32 + 16 = +48.
	assert_lt(p.position.y, -32.0, "player passed through the hazard (one-way honored): y=%.2f" % p.position.y)
