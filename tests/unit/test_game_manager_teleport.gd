extends GutTest

func before_each():
	GameManager.clear_progress()

func after_each():
	GameManager.clear_progress()

func _add_teleporter(ld: LevelData, id: String, x: int, y: int, dlevel := "", dtp := "") -> void:
	ld.entities.append(EntityDef.new("keen1.teleporter", x, y, {
		"teleporter_id": id,
		"destination_level_id": dlevel,
		"destination_teleporter_id": dtp,
	}))

func _level(level_id: String, map_kind: int) -> LevelData:
	var ld := LevelData.new()
	ld.level_id = level_id
	ld.width = 4
	ld.height = 4
	ld.fill_blank()
	ld.map_kind = map_kind
	return ld

func test_same_map_teleport_sets_spawn_and_state():
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "src", 1, 1, "lvl1", "dst")
	_add_teleporter(lvl, "dst", 5, 6, "lvl1", "src")
	GameManager.register_level(lvl)
	GameManager.teleport_no_scene_swap("lvl1", "dst")
	assert_eq(GameManager.pending_level, lvl)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.current_level, lvl)
	assert_eq(GameManager.pending_teleport_arrival_id, "dst", "arrival id set on same-map teleport")

func test_cross_map_teleport_into_level():
	var ow := _level("ow", LevelData.MapKind.OVERWORLD)
	_add_teleporter(ow, "ow_north", 2, 3, "lvl_secret", "secret")
	var secret := _level("lvl_secret", LevelData.MapKind.LEVEL)
	_add_teleporter(secret, "secret", 7, 8, "ow", "ow_north")
	GameManager.register_level(ow)
	GameManager.register_level(secret)
	GameManager.teleport_no_scene_swap("lvl_secret", "secret")
	assert_eq(GameManager.pending_level, secret)
	assert_eq(GameManager.pending_player_spawn, Vector2i(7, 8))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.current_level, secret)
	assert_eq(GameManager.pending_teleport_arrival_id, "secret", "arrival id set on cross-map teleport")

func test_teleport_to_overworld_sets_overworld_state():
	var ow := _level("ow", LevelData.MapKind.OVERWORLD)
	_add_teleporter(ow, "ow_tp", 3, 3)
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "lvl_tp", 0, 0, "ow", "ow_tp")
	GameManager.register_level(ow)
	GameManager.register_level(lvl)
	GameManager.teleport_no_scene_swap("ow", "ow_tp")
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_null(GameManager.current_level)
	assert_eq(GameManager.pending_player_spawn, Vector2i(3, 3))
	assert_eq(GameManager.pending_teleport_arrival_id, "ow_tp", "arrival id set on teleport to overworld")

func test_dangling_level_id_is_noop():
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "a", 1, 1)
	GameManager.register_level(lvl)
	var state_before := GameManager.state
	GameManager.teleport_no_scene_swap("nope", "a")
	assert_eq(GameManager.state, state_before, "state unchanged on dangling level")
	assert_null(GameManager.pending_level, "pending_level untouched on dangling level")
	assert_eq(GameManager.pending_teleport_arrival_id, "", "arrival id not set on dangling level")

func test_dangling_teleporter_id_is_noop():
	var lvl := _level("lvl1", LevelData.MapKind.LEVEL)
	_add_teleporter(lvl, "a", 1, 1)
	GameManager.register_level(lvl)
	GameManager.teleport_no_scene_swap("lvl1", "missing")
	assert_eq(GameManager.pending_player_spawn, Vector2i(-1, -1), "spawn untouched when teleporter missing")
	assert_eq(GameManager.pending_teleport_arrival_id, "", "arrival id not set on dangling teleporter")

func test_empty_destination_is_noop():
	GameManager.teleport_no_scene_swap("", "")
	assert_eq(GameManager.state, GameManager.State.MENU, "state unchanged on empty destination")
	assert_eq(GameManager.pending_teleport_arrival_id, "", "arrival id not set on empty destination")

func test_clear_progress_resets_arrival_id():
	GameManager.pending_teleport_arrival_id = "stale"
	GameManager.clear_progress()
	assert_eq(GameManager.pending_teleport_arrival_id, "", "clear_progress resets arrival id")
