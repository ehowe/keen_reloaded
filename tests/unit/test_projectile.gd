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
