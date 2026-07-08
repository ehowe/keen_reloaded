extends GutTest

class StubEnemy extends Node:
	var hp: int = 1
	var damaged: bool = false
	func take_damage(_a: int) -> void:
		damaged = true


func _new_proj() -> Projectile:
	var p: Projectile = add_child_autofree(load("res://src/runtime/player/projectile.tscn").instantiate())
	return p


func test_lifetime_expiry_frees():
	var p := _new_proj()
	p.lifetime = 0.1
	p._physics_process(0.2)
	assert_true(p.is_queued_for_deletion(), "despawns when lifetime runs out")


func test_enemy_hit_deals_damage_and_frees():
	var p := _new_proj()
	var e := StubEnemy.new()
	add_child(e)
	p._on_body_entered(e)
	assert_true(e.damaged, "enemy took damage")
	assert_true(p.is_queued_for_deletion(), "projectile freed after hit")


func test_tile_hit_frees():
	var p := _new_proj()
	var wall := StaticBody2D.new()  # not in group "entity", no take_damage
	add_child(wall)
	p._on_body_entered(wall)
	assert_true(p.is_queued_for_deletion(), "despawns on wall")


func test_item_passes_through():
	var p := _new_proj()
	var item := Node2D.new()
	item.add_to_group("entity")  # entity without take_damage -> pass through
	add_child(item)
	p._on_body_entered(item)
	assert_false(p.is_queued_for_deletion(), "passes through items")


func test_launch_sets_velocity_from_dir():
	var p := _new_proj()
	p.launch(1)
	assert_gt(p.velocity.x, 0, "right launch")
	p.launch(-1)
	assert_lt(p.velocity.x, 0, "left launch")


## Minimal TileMapLayer fixture: cell (0,0) = one-way tile, cell (1,0) = solid
## tile. Both have full-cell collision polygons; only cell (0,0) is one-way.
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


func test_one_way_tile_not_solid_for_bolts():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (0,0) center is at (8, 8) for 16px tiles.
	assert_false(Projectile.is_solid_tile_at(tml, Vector2(8, 8)), "one-way tile is not solid for bolts")


func test_solid_tile_blocks_bolts():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (1,0) center is at (24, 8).
	assert_true(Projectile.is_solid_tile_at(tml, Vector2(24, 8)), "solid tile blocks bolts")


func test_empty_cell_not_solid():
	var tml := _tilemap_with_one_way_and_solid()
	# Cell (2,0) is empty.
	assert_false(Projectile.is_solid_tile_at(tml, Vector2(40, 8)), "empty cell is not solid")
