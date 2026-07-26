extends GutTest

## Tests for the IceCannon projectile: linear motion, solid-tile despawn
## (via the shared Projectile.is_solid_tile_at helper), one-way pass-through,
## and instakill on player contact. Mirrors test_projectile.gd's approach of
## testing is_solid_tile_at directly (the _physics_process overlap path
## needs a live physics tick which GUT does not drive per-step).


class FakePlayer extends CharacterBody2D:
	var health: int = 3
	func _ready() -> void:
		add_to_group("player")
	func take_damage(amount: int) -> void:
		health = max(0, health - amount)


func _new_proj() -> IceCannonProjectile:
	return add_child_autofree(load("res://src/runtime/entities/ice_cannon_projectile.tscn").instantiate())


## Minimal TileMapLayer fixture: cell (0,0) = one-way, cell (1,0) = solid.
## Mirrors test_projectile.gd._tilemap_with_one_way_and_solid.
func _tilemap_with_one_way_and_solid() -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))  # one-way
	src.create_tile(Vector2i(1, 0))  # solid
	ts.add_physics_layer()
	var rect := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	var td_ow: TileData = src.get_tile_data(Vector2i(0, 0), 0)
	td_ow.add_collision_polygon(0)
	td_ow.set_collision_polygon_points(0, 0, rect)
	td_ow.set_collision_polygon_one_way(0, 0, true)
	var td_solid: TileData = src.get_tile_data(Vector2i(1, 0), 0)
	td_solid.add_collision_polygon(0)
	td_solid.set_collision_polygon_points(0, 0, rect)
	var tml := TileMapLayer.new()
	tml.tile_set = ts
	tml.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))  # one-way at cell (0,0)
	tml.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))  # solid at cell (1,0)
	add_child_autofree(tml)
	return tml


func test_launch_sets_velocity():
	var p := _new_proj()
	p.launch(Vector2(100, 0))
	assert_eq(p.velocity, Vector2(100, 0), "launch stores velocity verbatim")


func test_moves_in_straight_line():
	var p := _new_proj()
	p.launch(Vector2(200, 0))
	var start := p.global_position
	p._physics_process(0.5)
	# velocity*dt = 100 px on x; y untouched (straight line).
	assert_almost_eq(p.global_position.x, start.x + 100.0, 0.001, "x advances by velocity*dt")
	assert_almost_eq(p.global_position.y, start.y, 0.001, "y unchanged")


func test_solid_tile_detected_as_blocking():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (1,0) center is at (24, 8) for 16px tiles.
	assert_true(Projectile.is_solid_tile_at(tml, Vector2(24, 8)), "solid tile blocks projectile")


func test_one_way_tile_not_blocking():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (0,0) center is at (8, 8).
	assert_false(Projectile.is_solid_tile_at(tml, Vector2(8, 8)), "one-way platform passed through")


func test_instakills_player_on_contact():
	var p := _new_proj()
	var player := FakePlayer.new()
	add_child_autofree(player)
	p._on_body_entered(player)
	assert_eq(player.health, 0, "contact drains all health")


func test_ignores_non_player_body():
	# A body without the player contract must not crash the instakill path.
	var p := _new_proj()
	var decoy := CharacterBody2D.new()
	add_child_autofree(decoy)
	p._on_body_entered(decoy)  # must not error
	assert_false(p.is_queued_for_deletion(), "non-player body does not free the projectile")
