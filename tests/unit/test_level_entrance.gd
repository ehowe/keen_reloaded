extends GutTest

const TILE := 64
const SCENE := preload("res://src/runtime/entities/level_entrance.tscn")

func before_each():
	GameManager.clear_progress()
	EntityRegistry.clear()
	Keen1Episode.new().register_entities(EntityRegistry)

func after_each():
	GameManager.register_episodes()

func _make_entrance(target := "keen1_01", gate := false) -> Node2D:
	var e := LevelEntrance.new()
	add_child_autofree(e)
	e.setup("keen1.level_entrance", {"target_level_id": target, "blocks_until_completed": gate})
	e.set_tile(Vector2i(3, 4))
	return e

# Instantiates the real scene (mirrors production: setup before add_child).
func _make_scene_entrance(target := "keen1_01", variant := "City") -> LevelEntrance:
	var e: LevelEntrance = SCENE.instantiate()
	e.setup("keen1.level_entrance", {"target_level_id": target, "variant": variant})
	add_child_autofree(e)
	return e

func test_setup_reads_properties():
	var e := _make_entrance("lvl2", true)
	assert_eq(e.target_level_id, "lvl2")
	assert_true(e.blocks_until_completed)

func test_set_tile_records_position():
	var e := _make_entrance()
	assert_eq(e.tile, Vector2i(3, 4))

func test_non_gate_never_blocks():
	var e := _make_entrance("a", false)
	assert_false(e.is_blocking())

func test_gate_blocks_when_uncompleted():
	var e := _make_entrance("a", true)
	assert_true(e.is_blocking())

func test_gate_unblocks_when_completed():
	GameManager.mark_completed("a")
	var e := _make_entrance("a", true)
	assert_false(e.is_blocking())

func test_gate_with_empty_target_never_blocks():
	# A gate pointing at no level must not wall off the overworld forever.
	var e := _make_entrance("", true)
	assert_false(e.is_blocking())

func test_attempt_enter_requires_nearby():
	var e := _make_entrance("a", false)
	assert_false(e.attempt_enter(true))
	e._set_nearby_for_test(true)
	assert_true(e.attempt_enter(true))

func test_non_player_body_does_not_set_nearby():
	# TileMapLayer collision bodies share layer 1 and enter proximity zones at
	# build time. They must NOT mark the entrance as nearby — only the player.
	var e := _make_entrance("a", false)
	var decoy := StaticBody2D.new()
	add_child_autofree(decoy)
	e._on_body_entered(decoy)
	assert_false(e.attempt_enter(true), "non-player body must not activate proximity")

func test_player_body_sets_nearby():
	var e := _make_entrance("a", false)
	var p := CharacterBody2D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	e._on_body_entered(p)
	assert_true(e.attempt_enter(true), "player body activates proximity")

func test_attempt_enter_requires_interact():
	var e := _make_entrance("a", false)
	e._set_nearby_for_test(true)
	assert_false(e.attempt_enter(false))

func test_attempt_enter_emits_signal():
	var e := _make_entrance("lvl_x", false)
	e._set_nearby_for_test(true)
	var captured := {"target": "", "tile": Vector2i(-1, -1)}
	e.enter_requested.connect(func(t: String, tile: Vector2i) -> void:
		captured["target"] = t
		captured["tile"] = tile)
	e.attempt_enter(true)
	assert_eq(captured["target"], "lvl_x")
	assert_eq(captured["tile"], Vector2i(3, 4))

func test_refresh_blocking_clears_after_completion():
	var e := _make_entrance("a", true)
	assert_true(e.is_blocking())
	GameManager.mark_completed("a")
	e.refresh_blocking()
	assert_false(e.is_blocking())

# --- Done overlay sprite ---

func test_done_sprites_hidden_when_not_completed():
	var e := _make_scene_entrance("lvl_a", "City")
	var small: Sprite2D = e.get_node("Small Done")
	var large: Sprite2D = e.get_node("Large Done")
	assert_false(small.visible, "Small Done hidden while level uncompleted")
	assert_false(large.visible, "Large Done hidden while level uncompleted")
	var city: Sprite2D = e.get_node("City")
	assert_true(city.visible, "variant sprite stays visible while uncompleted")

func test_large_done_shown_when_completed():
	# City has useLargeDoneTile=true, doneVariant=blue.
	GameManager.mark_completed("lvl_a")
	var e := _make_scene_entrance("lvl_a", "City")
	var small: Sprite2D = e.get_node("Small Done")
	var large: Sprite2D = e.get_node("Large Done")
	var city: Sprite2D = e.get_node("City")
	assert_true(large.visible, "Large Done shown when level completed")
	assert_false(small.visible, "Small Done hidden when large variant used")
	assert_false(city.visible, "variant hidden when completed")
	var tex := large.texture as AtlasTexture
	assert_eq(tex.region.position.x, 0, "blue large column offset = 0")

func test_small_done_shown_when_completed():
	# Blue Shrine has useLargeDoneTile=false.
	GameManager.mark_completed("lvl_a")
	var e := _make_scene_entrance("lvl_a", "Blue Shrine")
	var small: Sprite2D = e.get_node("Small Done")
	var large: Sprite2D = e.get_node("Large Done")
	assert_true(small.visible, "Small Done shown when level completed")
	assert_false(large.visible, "Large Done hidden when small variant used")

func test_large_done_red_column_offset():
	GameManager.mark_completed("lvl_a")
	var e := _make_scene_entrance("lvl_a", "City")
	(e.get_node("City") as Sprite2D).set_meta("doneVariant", "red")
	e.refresh_blocking()
	var tex := (e.get_node("Large Done") as Sprite2D).texture as AtlasTexture
	assert_eq(tex.region.position.x, 128, "red large column offset = 128")

func test_large_done_yellow_column_offset():
	GameManager.mark_completed("lvl_a")
	var e := _make_scene_entrance("lvl_a", "City")
	(e.get_node("City") as Sprite2D).set_meta("doneVariant", "yellow")
	e.refresh_blocking()
	var tex := (e.get_node("Large Done") as Sprite2D).texture as AtlasTexture
	assert_eq(tex.region.position.x, 256, "yellow large column offset = 256")

func test_small_done_red_column_offset():
	GameManager.mark_completed("lvl_a")
	var e := _make_scene_entrance("lvl_a", "Blue Shrine")
	(e.get_node("Blue Shrine") as Sprite2D).set_meta("doneVariant", "red")
	e.refresh_blocking()
	var tex := (e.get_node("Small Done") as Sprite2D).texture as AtlasTexture
	assert_eq(tex.region.position.x, 64, "red small column offset = 64")

func test_done_sprite_overlays_variant_position():
	# City is positioned at (0, -32); done overlay must share it.
	GameManager.mark_completed("lvl_a")
	var e := _make_scene_entrance("lvl_a", "City")
	var city: Sprite2D = e.get_node("City")
	var large: Sprite2D = e.get_node("Large Done")
	assert_eq(large.position, city.position, "Large Done overlays variant position")

func test_done_region_does_not_leak_across_instances():
	# Mutating one instance's done region must not corrupt the shared subresource
	# seen by a second instance.
	GameManager.mark_completed("lvl_a")
	var e1 := _make_scene_entrance("lvl_a", "City")
	(e1.get_node("City") as Sprite2D).set_meta("doneVariant", "yellow")
	e1.refresh_blocking()
	var e2 := _make_scene_entrance("lvl_a", "City")
	var tex2 := (e2.get_node("Large Done") as Sprite2D).texture as AtlasTexture
	assert_eq(tex2.region.position.x, 0, "second instance blue offset unaffected by first")
