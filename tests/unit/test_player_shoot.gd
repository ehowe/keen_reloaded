extends GutTest

const BLASTER := "keen1.blaster"


func before_each() -> void:
	# Blaster is find-to-own (granted by the keen1.raygun pickup, not by
	# Player._ready). Start every test clean so each must grant it explicitly.
	Inventory.clear()
	GameManager.ammo = 0


func _new_player() -> Player:
	var p := Player.new()
	add_child_autofree(p)
	return p


func test_ammo_inits_to_zero():
	var p := _new_player()
	assert_eq(p.ammo, 0, "ammo starts at zero (must find pickups)")


func test_shoot_spawns_projectile_and_decrements():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)  # parent = host so the projectile lands as a sibling
	Inventory.add_item(BLASTER)
	p.projectile_speed = 999.0
	p.ammo = p.max_ammo
	var before := host.get_child_count()
	p.shoot()
	assert_eq(p.ammo, p.max_ammo - 1, "ammo decremented")
	assert_eq(host.get_child_count(), before + 1, "projectile spawned as sibling")
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_true(proj is Projectile, "spawned node is a Projectile")
	assert_eq(proj.speed, 999.0, "player projectile_speed wired to bolt")


func test_no_shoot_at_zero_ammo():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	p.ammo = 0
	var before := host.get_child_count()
	p.shoot()
	assert_eq(host.get_child_count(), before, "no projectile spawned at 0 ammo")


func test_shoot_uses_facing():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	Inventory.add_item(BLASTER)
	p._facing = -1
	p.ammo = p.max_ammo
	p.shoot()
	var proj := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(proj.velocity.x, 0, "left-facing shot moves left")


func test_shoot_spawn_flips_with_facing():
	var scene := load("res://src/runtime/player/player.tscn") as PackedScene
	var host := Node2D.new()
	add_child_autofree(host)
	var p := scene.instantiate() as Player
	host.add_child(p)
	Inventory.add_item(BLASTER)
	p.global_position = Vector2(1000, 500)
	p.ammo = p.max_ammo
	p._facing = 1
	p.shoot()
	var pr := host.get_child(host.get_child_count() - 1) as Projectile
	assert_gt(pr.global_position.x, p.global_position.x, "right-facing spawns right of player")
	p._facing = -1
	p.shoot()
	var pl := host.get_child(host.get_child_count() - 1) as Projectile
	assert_lt(pl.global_position.x, p.global_position.x, "left-facing spawns left of player")


func test_add_ammo_clamps_to_max():
	var p := _new_player()
	p.ammo = p.max_ammo
	p.add_ammo(10)
	assert_eq(p.ammo, p.max_ammo, "clamped to max_ammo")


# ---- Blaster (find-to-own: granted by keen1.raygun pickup, not Player._ready) ----

func test_ready_does_not_grant_blaster():
	# Player._ready must NOT auto-grant the blaster. Acquisition is via the
	# keen1.raygun pickup (see test_pickups.gd). Spawn-and-check is the contract.
	var p := _new_player()
	assert_false(Inventory.has_item(BLASTER), "spawn does not auto-grant blaster")


func test_shoot_requires_blaster():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	p.ammo = p.max_ammo
	Inventory.remove_item(BLASTER)  # disarm: no blaster, even with ammo
	var before := host.get_child_count()
	p.shoot()
	assert_eq(host.get_child_count(), before, "no projectile without the blaster")
	assert_eq(p.ammo, p.max_ammo, "ammo not spent without the blaster")


# ---- Ammo mirrors the persistent GameManager store ----

func test_add_ammo_mirrors_game_manager():
	var p := _new_player()
	p.add_ammo(3)
	assert_eq(p.ammo, 3, "local ammo updated")
	assert_eq(GameManager.ammo, 3, "pickup wrote through to persistent store")


func test_add_ammo_clamps_game_manager_to_max():
	var p := _new_player()
	p.add_ammo(100)
	assert_eq(GameManager.ammo, p.max_ammo, "persistent store clamped to max_ammo")


func test_shoot_mirrors_game_manager():
	var host := Node2D.new()
	add_child_autofree(host)
	var p := Player.new()
	host.add_child(p)
	Inventory.add_item(BLASTER)
	p.ammo = p.max_ammo
	GameManager.ammo = p.max_ammo
	p.shoot()
	assert_eq(GameManager.ammo, p.max_ammo - 1, "shot decremented persistent store")
