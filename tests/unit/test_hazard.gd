extends GutTest

## Characterization tests for the instakill hazard family (Spike/Fire/Clapper
## /GreenDanglyStuff) and the base Hazard contact-damage contract. These lock
## the existing "drain all health on contact" behavior so the instakill-helper
## refactor (#1) cannot silently change it.


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)


func _player() -> FakePlayer:
	var p := FakePlayer.new()
	add_child_autofree(p)
	return p


func test_base_hazard_deals_configured_damage():
	var h := Hazard.new()
	h.damage = 1
	add_child_autofree(h)
	var p := _player()
	h._handle_player(p)
	assert_eq(p.health, 2, "base Hazard subtracts its damage value")


func test_spike_instakills_on_contact():
	var s := Spike.new()
	add_child_autofree(s)
	var p := _player()
	s._handle_player(p)
	assert_eq(p.health, 0, "Spike drains all health")


func test_fire_instakills_on_contact():
	var f := Fire.new()
	add_child_autofree(f)
	var p := _player()
	f._handle_player(p)
	assert_eq(p.health, 0, "Fire drains all health")


func test_clapper_instakills_on_contact():
	var c := Clapper.new()
	add_child_autofree(c)
	var p := _player()
	c._handle_player(p)
	assert_eq(p.health, 0, "Clapper drains all health")


func test_instakill_ignores_non_player_body():
	# _handle_player is only reached via the player-filtered Area2D, but the
	# method itself must not crash on a body lacking the player contract.
	var s := Spike.new()
	add_child_autofree(s)
	var decoy := CharacterBody2D.new()  # no take_damage, no health
	add_child_autofree(decoy)
	s._handle_player(decoy)  # must not error
	assert_true(true, "non-player body does not crash instakill path")


func test_green_dangly_stuff_instakills_on_contact():
	var g := GreenDanglyStuff.new()
	add_child_autofree(g)
	var p := _player()
	g._handle_player(p)
	assert_eq(p.health, 0, "GreenDanglyStuff drains all health on bottom contact")


func test_green_dangly_stuff_contact_area_is_bottom_kill_zone():
	var g := GreenDanglyStuff.new()
	add_child_autofree(g)  # _ready() builds the contact Area2D + body shape
	var area := g.get_node_or_null("Area2D") as Area2D
	assert_not_null(area, "contact Area2D exists")
	var col := area.get_child(0) as CollisionShape2D
	assert_not_null(col, "Area2D has a CollisionShape2D")
	assert_true(col.shape is RectangleShape2D, "Area2D shape is RectangleShape2D")
	var rect := col.shape as RectangleShape2D
	assert_eq(rect.size, Vector2(64, 48), "kill zone is 64 wide × 48 tall (bottom 48 px strip)")
	# Shape position centers the rect in the LOWER half of the tile.
	# Tile center is (0,0); the bottom 48 strip's center is 8 px below origin.
	assert_eq(col.position, Vector2(0, 8), "kill zone offset 8 px down so it spans the bottom 48 px")


func test_green_dangly_stuff_body_is_one_way_platform():
	var g := GreenDanglyStuff.new()
	add_child_autofree(g)
	assert_eq(g.collision_layer, 4, "body on tiles bit so player lands on it")
	assert_eq(g.collision_mask, 0, "body mask is zero (static)")
	# Find the body's direct-child CollisionShape2D (not the Area2D's shape).
	var body_col: CollisionShape2D = null
	for c in g.get_children():
		if c is CollisionShape2D:
			body_col = c
			break
	assert_not_null(body_col, "body has a direct CollisionShape2D child")
	assert_true(body_col.one_way_collision, "body shape is one-way (land from top, pass through from below)")
	assert_true(body_col.shape is RectangleShape2D, "body shape is RectangleShape2D")
	var rect := body_col.shape as RectangleShape2D
	assert_eq(rect.size, Vector2(64, 64), "body shape covers the full tile")


func test_green_dangly_stuff_scene_instantiates_with_three_variants():
	var packed := load("res://src/runtime/entities/green_dangly_stuff.tscn") as PackedScene
	assert_not_null(packed, "scene loads")
	var g := add_child_autofree(packed.instantiate()) as GreenDanglyStuff
	assert_not_null(g, "scene root is GreenDanglyStuff")
	var vis := g.get_node_or_null("Visual")
	assert_not_null(vis, "Visual wrapper exists")
	# All three variant AnimatedSprite2D children are present by exact name.
	assert_not_null(vis.get_node_or_null("Left Edge"), "Left Edge variant present")
	assert_not_null(vis.get_node_or_null("Normal"), "Normal variant present")
	assert_not_null(vis.get_node_or_null("Right Edge"), "Right Edge variant present")
