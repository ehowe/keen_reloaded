extends GutTest

const ST := preload("res://src/core/surface_type.gd")

## Minimal TileMapLayer fixture: cell (0,0) tile is ICE1, cell (1,0) is ICE2,
## cell (2,0) is NONE. 16px tiles. Reuses the projectile-test tileset pattern.
func _tilemap_with_surfaces() -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "surface_type")
	var img := Image.create(48, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	for x in 3:
		src.create_tile(Vector2i(x, 0))
	src.get_tile_data(Vector2i(0, 0), 0).set_custom_data("surface_type", ST.Kind.ICE1)
	src.get_tile_data(Vector2i(1, 0), 0).set_custom_data("surface_type", ST.Kind.ICE2)
	src.get_tile_data(Vector2i(2, 0), 0).set_custom_data("surface_type", ST.Kind.NONE)
	var tml := TileMapLayer.new()
	tml.tile_set = ts
	tml.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	tml.set_cell(Vector2i(1, 0), 0, Vector2i(1, 0))
	tml.set_cell(Vector2i(2, 0), 0, Vector2i(2, 0))
	add_child_autofree(tml)
	return tml


func _new_player() -> Player:
	return add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate())


func test_read_surface_returns_kind_under_feet():
	var tml := _tilemap_with_surfaces()
	var p := _new_player()
	p.set_ground_tilemap(tml)
	# Player Level collision shape is RectangleShape2D(48, 96): foot at +48.
	# 16px tiles: cell (0,0) spans x in [0,16), center (8,8). Foot samples at
	# global_position.y + 48 + 1 (1px nudge into the tile below). Position so
	# the foot lands at y=8 (inside cell row 0): global_position.y = 8 - 48.
	p.global_position = Vector2(8, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.ICE1, "over ICE1 cell")
	p.global_position = Vector2(24, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.ICE2, "over ICE2 cell")
	p.global_position = Vector2(40, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.NONE, "over NONE cell")


func test_read_surface_none_when_no_tilemap():
	var p := _new_player()
	# no ground tilemap injected -> safe default NONE (never crashes)
	assert_eq(p._read_surface_under_feet(), ST.Kind.NONE, "no tilemap -> NONE")


func test_read_surface_none_when_no_custom_data_layer():
	# A tileset without the surface_type layer must read NONE (migration safety).
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))
	var tml := TileMapLayer.new()
	tml.tile_set = ts
	tml.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
	add_child_autofree(tml)
	var p := _new_player()
	p.set_ground_tilemap(tml)
	p.global_position = Vector2(8, 8 - 48)
	assert_eq(p._read_surface_under_feet(), ST.Kind.NONE, "missing layer -> NONE")


func test_step_grounded_normal_accelerates_then_decelerates():
	var p := _new_player()
	# from rest, hold right -> accelerates toward run_speed (does not snap)
	p.velocity.x = 0.0
	p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_lt(p.velocity.x, p.run_speed, "accelerates, does not snap to run_speed")
	assert_gt(p.velocity.x, 0.0, "moving right")
	# build up real speed before testing deceleration — the "no instant stop"
	# property must hold from a representative speed, not a 1-frame creep
	# (a single accel frame yields less speed than one decel frame removes, by
	# design: decel is snappier than accel for responsive feel).
	for i in 10:
		p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	var mid := p.velocity.x
	# release -> decelerates toward 0 (does not snap-stop)
	p._step_grounded(ST.Kind.NONE, 0.0, 0.016)
	assert_lt(absf(p.velocity.x), mid, "decelerating after release")
	assert_gt(absf(p.velocity.x), 0.0, "not yet stopped (no instant stop)")
	# eventually reaches run_speed when held
	p.velocity.x = 0.0
	for i in 100:
		p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, p.run_speed, 1.0, "reaches run_speed when held")


func test_step_grounded_speed_scale_applies_when_input_locked():
	var p := _new_player()
	p.lock_input(1.0, 0.5)   # exit walk: half speed
	p.velocity.x = 0.0
	for i in 100:
		p._step_grounded(ST.Kind.NONE, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, p.run_speed * 0.5, 1.0, "caps at scaled target while locked")


func test_step_grounded_ice1_zero_friction_no_input():
	var p := _new_player()
	p.velocity.x = 480.0
	for i in 60:
		p._step_grounded(ST.Kind.ICE1, 0.0, 0.016)
	assert_almost_eq(p.velocity.x, 480.0, 0.001, "ice1: velocity preserved with no input")


func test_step_grounded_ice1_accelerates_with_input():
	var p := _new_player()
	p.velocity.x = 0.0
	p._step_grounded(ST.Kind.ICE1, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, p.ice_accel * 0.016, 0.01, "ice1: accelerates by ice_accel*delta")


func test_step_grounded_ice1_entry_caps_overspeed():
	var p := _new_player()
	p.ice_max_speed_cap = 480.0
	p.velocity.x = 700.0          # landed faster than cap (e.g. from a leap)
	p._step_grounded(ST.Kind.ICE1, 1.0, 0.016)
	assert_almost_eq(p.velocity.x, 480.0, 0.5, "ice1: entry caps overspeed to cap")


func test_step_grounded_ice1_shows_walking_while_gliding():
	# Drive a real ICE1 glide step, then derive `moving` the same way production
	# does (absf(velocity.x) > 1.0) — no ice2 guard in production's moving calc.
	var p := _new_player()
	p.velocity.x = 0.0
	p._step_grounded(ST.Kind.ICE1, 1.0, 0.016)
	var moving := absf(p.velocity.x) > 1.0
	assert_true(moving, "ice1 glide counts as moving -> Walking")
	assert_eq(p._current_anim(true, moving, false, false, false), "Walking")
