extends GutTest

func after_each() -> void:
	AudioManager.stop_music()
	GameManager.ammo = 0

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 2, 1)
	ld.set_geometry_tile(1, 2, 1)
	ld.set_foreground_tile(2, 0, 3)
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("keen1.lollipop", 3, 1))
	ld.entities.append(EntityDef.new("keen1.butler", 1, 0))
	return ld


func test_build_assembles_four_tile_layers():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_eq(rt.layers.size(), 4)
	assert_true(rt.layers.has(LevelData.LAYER_GEOMETRY))
	assert_true(rt.layers.has(LevelData.LAYER_FOREGROUND))
	assert_true(rt.layers.has(LevelData.LAYER_BACKGROUND))
	assert_true(rt.layers.has(LevelData.LAYER_FRONT))


## FRONT renders ABOVE player + entities. Two requirements: (1) z_index higher
## than the player's z_index=1 (Godot sorts CanvasItems by z_index BEFORE tree
## order), and (2) FRONT is a later scene-tree sibling than player + entities
## so same-z_index ties still resolve correctly.
func test_front_layer_renders_above_player_and_entities():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	var front: TileMapLayer = rt.layers[LevelData.LAYER_FRONT]
	assert_gt(front.z_index, rt.player.z_index, "front.z_index must exceed player.z_index (1) to render on top")
	assert_eq(rt.player.z_index, 1, "sanity: player still z_index=1 (if this changed, bump FRONT)")
	var front_idx := front.get_index()
	for e in rt.entities_spawned:
		assert_gt(front_idx, e.get_index(), "front must be a later sibling than every entity (defensive)")


func test_build_sets_geometry_cells():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 2)), Vector2i(0, 0), "tile id 1 -> atlas (0,0)")
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), -1, "empty cell has no source")


func test_build_spawns_player_and_entities():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	assert_not_null(rt.player, "player spawned")
	assert_true(rt.player.is_in_group("player"))
	var ts := lvl.tile_size
	assert_eq(rt.player.position, Vector2(lvl.player_spawn.x * ts + ts / 2.0, lvl.player_spawn.y * ts + ts / 2.0), "player at spawn cell center")
	assert_eq(rt.entities_spawned.size(), lvl.entities.size(), "all entities spawned")
	assert_true(rt.entities_spawned[0].is_in_group("entity"), "entity in group")


func test_ready_auto_builds_from_pending_level():
	var lvl := _level()
	GameManager.pending_level = lvl
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	# _ready fired on add_child and should have built from pending_level.
	assert_eq(rt.layers.size(), 4)
	assert_not_null(rt.player)
	GameManager.pending_level = null


## A minimal real TileSet: 2 cols x 1 row, cell 16, one physics layer.
func _tileset_fixture() -> TileSet:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.3, 1))
	var tex := ImageTexture.create_from_image(img)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	ts.add_source(src)
	src.create_tile(Vector2i(0, 0))
	src.create_tile(Vector2i(1, 0))
	ts.add_physics_layer()
	return ts


func test_build_uses_tileset_ref_when_assigned():
	GameManager.pending_level = null
	var ts := _tileset_fixture()
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 2)  # tile id 2 -> atlas (1,0)
	ld.tileset_ref = ts
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_eq(rt.layers[LevelData.LAYER_GEOMETRY].tile_set, ts, "geometry uses the real TileSet")
	assert_eq(rt.layers[LevelData.LAYER_FOREGROUND].tile_set, ts, "foreground uses the real TileSet")
	assert_eq(rt.layers[LevelData.LAYER_BACKGROUND].tile_set, ts, "background uses the real TileSet")
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(1, 0), "id 2 -> atlas (1,0) via TileAtlas")
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), TileAtlas.source_id(ts), "source id resolved by index")
	assert_true(ts.get_physics_layers_count() >= 1, "TileSet carries a physics (collision) layer")


func test_build_creates_perimeter_bounds():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	# 3 solid walls (left/right/top), 1 kill zone (bottom) — found by name prefix
	# so unrelated entity nodes don't pollute the count.
	var walls := rt.find_children("BoundsWall*", "StaticBody2D", true, false)
	var kill_zones := rt.find_children("BoundsKillZone*", "Area2D", true, false)
	assert_eq(walls.size(), 3, "three perimeter walls")
	assert_eq(kill_zones.size(), 1, "one bottom kill zone")
	# Walls must sit on the tiles collision layer (4) so the player (mask 4) hits them.
	for w in walls:
		assert_eq(w.collision_layer, 4, "wall on tiles layer")
	# Kill zone must monitor the player layer (1).
	assert_eq(kill_zones[0].collision_mask, 1, "kill zone detects player")


func test_build_clamps_camera_to_map_bounds():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	var cam := rt.player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(cam, "player has a camera")
	var ts := lvl.tile_size
	assert_eq(cam.limit_left, 0, "left clamped to map origin")
	assert_eq(cam.limit_top, 0, "top clamped to map origin")
	assert_eq(cam.limit_right, lvl.width * ts, "right clamped to map width")
	assert_eq(cam.limit_bottom, lvl.height * ts, "bottom clamped to map height")


## Two-source TileSet: source 0 = 2x1, source 1 = 2x1 (16px cells).
func _two_source_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var img0 := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img0.fill(Color(0.2, 0.7, 0.3, 1))
	var s0 := TileSetAtlasSource.new()
	s0.texture = ImageTexture.create_from_image(img0)
	s0.texture_region_size = Vector2i(16, 16)
	ts.add_source(s0)
	s0.create_tile(Vector2i(0, 0))
	s0.create_tile(Vector2i(1, 0))
	var img1 := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img1.fill(Color(0.7, 0.2, 0.3, 1))
	var s1 := TileSetAtlasSource.new()
	s1.texture = ImageTexture.create_from_image(img1)
	s1.texture_region_size = Vector2i(16, 16)
	ts.add_source(s1)
	s1.create_tile(Vector2i(0, 0))
	s1.create_tile(Vector2i(1, 0))
	return ts


func test_build_renders_second_source_cell():
	GameManager.pending_level = null
	var ts := _two_source_tileset()
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	# source 1, cell idx 1 -> atlas (1, 0)
	ld.set_geometry_tile(0, 0, TileAtlas.SOURCE_STRIDE + 2)
	ld.tileset_ref = ts
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_eq(geo.get_cell_source_id(Vector2i(0, 0)), ts.get_source_id(1), "cell resolves to source 1")
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(1, 0), "source-1 cell coords")


func test_build_falls_back_to_procedural_when_tileset_ref_null():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.set_geometry_tile(0, 0, 1)
	assert_null(ld.tileset_ref)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	# Procedural fallback: geometry TileSet is NOT the (null) tileset_ref; it's built.
	var geo: TileMapLayer = rt.layers[LevelData.LAYER_GEOMETRY]
	assert_not_null(geo.tile_set)
	assert_eq(geo.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(0, 0), "procedural id 1 -> (0,0)")


func test_build_sets_player_mode_for_overworld():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	assert_not_null(rt.player, "player spawned")
	assert_eq(rt.player._mode, Player.Mode.OVERWORLD, "player spawned in OVERWORLD mode on overworld map")


func test_build_keeps_player_mode_for_level():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_eq(rt.player._mode, Player.Mode.LEVEL, "player stays in LEVEL mode on level map")


func test_build_seeds_player_ammo_from_game_manager():
	# Ammo persists in GameManager across levels; a freshly spawned player must
	# inherit it so the stash carries over (and the HUD shows the right count).
	GameManager.pending_level = null
	GameManager.ammo = 4
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_eq(rt.player.ammo, 4, "player ammo seeded from GameManager on spawn")


func test_kill_zone_lethal_fall_does_not_respawn():
	# Classic Keen 1: any damage is lethal. A fall into the kill zone triggers
	# take_damage -> _die() which owns the launch velocity. No respawn.
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	var lvl := _level()
	rt.build(lvl)
	var p := rt.player
	var pos_before := p.position
	rt._on_kill_zone_body_entered(p)
	assert_eq(p.position, pos_before, "lethal fall: position untouched by respawn")
	assert_true((p.velocity - Vector2(-cos(deg_to_rad(60.0)), -sin(deg_to_rad(60.0))) * p.death_launch_speed).length() < 0.2, "launch velocity preserved")
	assert_true(p._dead, "player is dead")


func test_player_died_signal_sets_dying_flag():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_false(rt._dying, "_dying false before death")
	rt.player.died.emit()
	assert_true(rt._dying, "_dying set when player.died emits")


func test_died_is_connected_after_build():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	assert_true(rt.player.died.is_connected(rt._on_player_died), "died -> _on_player_died wired")


# REPRODUCTION: real TileMapLayer ceiling. Player dies, launches up-left.
# If CollisionShape2D.disable does NOT stop TileMapLayer collisions, Keen
# stops at the ceiling row. If it does, he flies past it.
func test_dead_player_flies_through_tilemap_ceiling():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 5
	ld.height = 6
	ld.tile_size = 16
	ld.fill_blank()
	# Solid ceiling row across the top (row 0) — covers the up-left launch path.
	for x in range(ld.width):
		ld.set_geometry_tile(x, 0, 1)
	ld.player_spawn = Vector2i(2, 4)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var p := rt.player
	p.take_damage(p.health)  # die -> up-left launch, shape disabled
	await get_tree().physics_frame  # let the deferred disable flush
	var start := p.global_position
	for i in 40:
		p._physics_process(0.016)
	var traveled := p.global_position - start
	# Ceiling sits ~40px above spawn; if colliding, traveled.y ~= -40. If passing
	# through (correct), traveled.y is far more negative (40 frames * ~11px).
	assert_lt(traveled.y, -100.0, "Keen flew past the tilemap ceiling during death flight")


# REGRESSION: the real Clapper path. The Clapper (and every Entity) detects the
# player via an Area2D body_entered signal, which fires DURING the physics query
# flush. Setting CollisionShape2D.disabled = true there is rejected by Godot
# ("Can't change this state while flushing queries"), leaving the shape enabled
# so Keen collides with walls during death-flight. The fix defers the disable.
# This test drives the player into a contact Area2D on real physics frames so
# death triggers from the body_entered callback (the query-flush path), then
# verifies the death-flight passes through a ceiling.
func test_death_via_area_body_entered_flies_through_ceiling():
	var p := add_child_autofree(load("res://src/runtime/player/player.tscn").instantiate()) as Player
	p.global_position = Vector2(200, 400)
	# Wide ceiling on the tiles layer (4) covering the up-left launch path.
	var ceil_body := StaticBody2D.new()
	ceil_body.collision_layer = 4
	var cshape := RectangleShape2D.new()
	cshape.size = Vector2(2000, 16)
	var ccol := CollisionShape2D.new()
	ccol.shape = cshape
	ceil_body.add_child(ccol)
	ceil_body.global_position = Vector2(-400, 200)
	add_child(ceil_body)
	# Clapper-like contact Area2D just above the player's start.
	var area := Area2D.new()
	area.collision_mask = 1  # player bit
	var ashape := RectangleShape2D.new()
	ashape.size = Vector2(64, 64)
	var acol := CollisionShape2D.new()
	acol.shape = ashape
	area.add_child(acol)
	area.global_position = Vector2(200, 300)
	area.body_entered.connect(func(body) -> void:
		if body == p and p.has_method("take_damage"):
			p.take_damage(p.health))
	add_child(area)
	# Drive the player up into the area on real physics frames so body_entered
	# fires during the query flush (the real Clapper path).
	for i in 40:
		if p._dead:
			break
		p.velocity = Vector2(0, -300)
		await get_tree().physics_frame
	assert_true(p._dead, "player died via area body_entered")
	var col := p.get_node("Level") as CollisionShape2D
	var start := Vector2(p.global_position)
	for i in 40:
		await get_tree().physics_frame
	var end := p.global_position
	assert_true(col.disabled, "death during query flush still disables the shape (deferred)")
	assert_lt(end.y, 0.0, "Keen flew up through the ceiling (no collision)")


func test_build_plays_level_music():
	GameManager.pending_level = null
	var lvl := _level()
	lvl.music = load("res://assets/audio/sfx/jump.wav")
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(lvl)
	assert_true(AudioManager._music_player.playing)
	assert_eq(AudioManager._music_player.stream, lvl.music)


func test_build_stops_music_when_none():
	GameManager.pending_level = null
	var lvl := _level()
	lvl.music = null
	AudioManager.play_music(load("res://assets/audio/sfx/jump.wav"))
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(lvl)
	assert_false(AudioManager._music_player.playing)


func test_build_creates_level_hud():
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(_level())
	var hud := rt.find_child("Hud", true, false) as Hud
	assert_not_null(hud, "HUD node present on level build")
	assert_true((hud.get_node("LevelContainer") as CanvasItem).visible, "level HUD visible in LEVEL mode")
	assert_eq((hud.get_node("LevelContainer/ScoreLabel") as Label).text, "Score 0", "score seeded from player")


func test_overworld_hud_shows_cleared():
	GameManager.completed_levels.clear()
	var ld := LevelData.new()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("keen1.level_entrance", 0, 0, {"target_level_id": "level1"}))
	ld.entities.append(EntityDef.new("keen1.level_entrance", 1, 0, {"target_level_id": "level2"}))
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var hud := rt.find_child("Hud", true, false) as Hud
	assert_not_null(hud, "HUD node present on overworld build")
	assert_true((hud.get_node("OverworldContainer") as CanvasItem).visible, "overworld HUD visible")
	assert_eq((hud.get_node("OverworldContainer/ClearedLabel") as Label).text, "Levels cleared: 0 / 2", "M counts entrances, N is completed set size")
	GameManager.completed_levels.clear()


func test_build_wires_teleporter_signal():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("keen1.teleporter", 2, 1, {
		"teleporter_id": "a",
		"destination_level_id": "ow",
		"destination_teleporter_id": "b",
	}))
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var tp: Teleporter = null
	for n in rt.entities_spawned:
		if n is Teleporter:
			tp = n
			break
	assert_not_null(tp, "teleporter spawned")
	assert_true(tp.teleport_requested.get_connections().size() >= 1, "teleport_requested wired to runtime")


func test_build_plays_arrival_for_pending_teleport():
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("keen1.teleporter", 2, 1, {
		"teleporter_id": "dest",
		"destination_level_id": "ow",
		"destination_teleporter_id": "src",
	}))
	# Drive the _ready arrival path: pending_level + arrival id + spawn tile.
	GameManager.pending_level = ld
	GameManager.pending_teleport_arrival_id = "dest"
	GameManager.pending_player_spawn = Vector2i(2, 1)
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	# _ready consumed the flag and triggered the destination's arrival anim.
	assert_eq(GameManager.pending_teleport_arrival_id, "", "arrival id consumed after build")
	assert_false(rt.player.visible, "player hidden during arrival anim")
	assert_eq(rt.player.process_mode, Node.PROCESS_MODE_DISABLED, "player frozen during arrival anim")
	var tp: Teleporter = null
	for n in rt.entities_spawned:
		if n is Teleporter:
			tp = n
			break
	assert_not_null(tp, "destination teleporter spawned")
	assert_true((tp.get_node("AnimatedSprite2D") as AnimatedSprite2D).is_playing(), "arrival anim playing")
	# Finish arrival to restore player state (avoids leaking a frozen player).
	tp._on_animation_finished()
	assert_true(rt.player.visible, "player shown after arrival finishes")


func test_failed_teleport_restores_player_and_visual():
	# A teleporter pointing at a dangling level must not soft-lock: the player
	# is un-hidden and unfrozen after the failed teleport.
	var ld := LevelData.new()
	ld.width = 4
	ld.height = 3
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(0, 1)
	ld.entities.append(EntityDef.new("keen1.teleporter", 2, 1, {
		"teleporter_id": "src",
		"destination_level_id": "ghost",  # not registered -> dangling
		"destination_teleporter_id": "dst",
	}))
	GameManager.pending_level = null
	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)
	var tp: Teleporter = null
	for n in rt.entities_spawned:
		if n is Teleporter:
			tp = n
			break
	tp._set_player_for_test(rt.player)
	tp._set_nearby_for_test(true)
	assert_true(tp.attempt_teleport(true), "departure started")
	assert_false(rt.player.visible, "player hidden during departure anim")
	# Finishing the departure anim emits teleport_requested -> dangling teleport
	# -> GameManager.teleport returns false -> source restored.
	tp._on_animation_finished()
	assert_true(rt.player.visible, "player restored after failed teleport")
	assert_eq(rt.player.process_mode, Node.PROCESS_MODE_INHERIT, "player unfrozen after failed teleport")
	assert_true((tp.get_node("Visual") as CanvasItem).visible, "teleporter visual restored")
