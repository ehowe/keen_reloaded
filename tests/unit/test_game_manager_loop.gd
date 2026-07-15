extends GutTest

func before_each():
	GameManager.clear_progress()
	SaveSystem.saves_dir = SAVES_TMP
	SaveSystem.active_slot = 0
	PackLoader._remove_dir_recursive(SAVES_TMP)

func after_each():
	GameManager.clear_progress()
	PackLoader._remove_dir_recursive(PL_TMP)
	PackLoader.root_dir = "user://levelpacks/"
	_restore_save_dir()

func test_is_level_completed_false_by_default():
	assert_false(GameManager.is_level_completed("keen1_01"))

func test_mark_completed_then_query():
	GameManager.mark_completed("keen1_01")
	assert_true(GameManager.is_level_completed("keen1_01"))

func test_mark_completed_is_idempotent():
	GameManager.mark_completed("keen1_01")
	GameManager.mark_completed("keen1_01")
	assert_eq(GameManager.completed_levels.count("keen1_01"), 1)

func test_clear_progress():
	GameManager.mark_completed("keen1_01")
	var ld := LevelData.new()
	ld.level_id = "ow_x"
	GameManager.register_level(ld)
	GameManager.clear_progress()
	assert_false(GameManager.is_level_completed("keen1_01"))
	assert_null(GameManager.get_level_by_id("ow_x"), "registry cleared too")

func test_register_and_get_level():
	var ld := LevelData.new()
	ld.level_id = "ow_x"
	GameManager.register_level(ld)
	assert_eq(GameManager.get_level_by_id("ow_x"), ld)

func test_serialize_deserialize_round_trip():
	GameManager.mark_completed("a")
	GameManager.mark_completed("b")
	GameManager.current_episode_id = "keen1"
	var data := GameManager.serialize()
	GameManager.clear_progress()
	GameManager.current_episode_id = ""
	GameManager.deserialize(data)
	assert_true(GameManager.is_level_completed("a"))
	assert_true(GameManager.is_level_completed("b"))
	assert_eq(GameManager.current_episode_id, "keen1")

func test_default_state_is_menu():
	assert_eq(GameManager.state, GameManager.State.MENU)

func test_enter_level_sets_pending_and_state():
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(lvl)
	# Avoid real scene swap during the test:
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(3, 4))
	assert_eq(GameManager.state, GameManager.State.LEVEL)
	assert_eq(GameManager.pending_level, lvl)
	assert_eq(GameManager.last_entrance_pos, Vector2i(3, 4))
	assert_eq(GameManager.pending_player_spawn, Vector2i(-1, -1))

func test_complete_level_returns_to_overworld():
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(ow)
	GameManager.register_level(lvl)
	GameManager.current_overworld = ow
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(5, 6))
	GameManager.complete_level_no_scene_swap()
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_true(GameManager.is_level_completed("keen1_01"))

func test_episode_load_overworld_from_path():
	# Build a tiny overworld .tres, point an Episode at it, load.
	var ow := LevelData.new()
	ow.level_id = "ow_test"
	ow.level_name = "Test Overworld"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var path := "res://tests/tmp_overworld.tres"
	# Save into res:// so ResourceLoader.load(path) works headless.
	DirAccess.make_dir_recursive_absolute("res://tests/")
	assert_eq(ResourceSaver.save(ow, path), OK)
	var ep := Episode.new()
	ep.id = "t"
	ep.title = "T"
	ep.overworld_level_id = "ow_test"
	ep.overworld_path = path
	var loaded := ep.load_overworld()
	assert_not_null(loaded)
	assert_eq(loaded.level_id, "ow_test")
	assert_eq(loaded.map_kind, LevelData.MapKind.OVERWORLD)

func test_start_episode_sets_overworld_state():
	var ow := LevelData.new()
	ow.level_id = "ow_s"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	GameManager.register_level(ow)
	# start_episode_no_scene_swap takes the resolved overworld directly so the
	# test avoids directory scanning + scene swaps.
	GameManager.start_episode_no_scene_swap("fake", ow)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.current_overworld, ow)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.current_episode_id, "fake")

func test_fail_level_returns_to_overworld_without_completing():
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "keen1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	GameManager.register_level(ow)
	GameManager.register_level(lvl)
	GameManager.current_overworld = ow
	GameManager.enter_level_no_scene_swap("keen1_01", Vector2i(5, 6))
	GameManager.fail_level_no_scene_swap()
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.pending_player_spawn, Vector2i(5, 6))
	assert_false(GameManager.is_level_completed("keen1_01"), "death must NOT mark level complete")
	assert_null(GameManager.current_level, "current_level cleared")

const PL_TMP := "user://tmp_gm_packtest/"

const SAVES_TMP := "user://tmp_gm_saves/"

func _restore_save_dir():
	PackLoader._remove_dir_recursive(SAVES_TMP)
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	SaveSystem.active_slot = 0

func _seed_pack_loader(pack_id: String, ow: LevelData, levels: Array) -> void:
	PackLoader.root_dir = PL_TMP
	PackLoader._remove_dir_recursive(PL_TMP)
	var d := PL_TMP + pack_id + "/"
	DirAccess.make_dir_recursive_absolute(d)
	ResourceSaver.save(ow, d + "overworld.tres")
	var parts := PackedStringArray()
	parts.append('{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}')
	var i := 1
	for lvl in levels:
		var fn := "lvl_%d.tres" % i
		ResourceSaver.save(lvl, d + fn)
		parts.append('{"level_id": "%s", "file": "%s", "name": "L%d", "order": %d}' % [lvl.level_id, fn, i, i])
		i += 1
	var manifest := """{
		"pack_id": "%s", "name": "GM", "author": "qa", "version": "1.0",
		"levels": [%s]
	}""" % [pack_id, ", ".join(parts)]
	var mf := FileAccess.open(d + "manifest.json", FileAccess.WRITE)
	mf.store_string(manifest)
	mf.close()
	PackLoader.scan()


func test_start_episode_registers_episode_levels_from_disk():
	GameManager.clear_progress()
	var ep := GameManager._find_episode("keen1")
	assert_not_null(ep)
	var ow := ep.load_overworld()
	assert_not_null(ow)
	GameManager.start_episode_no_scene_swap("keen1", ow)
	assert_not_null(GameManager.get_level_by_id("keen1_01"), "keen1_01 must be registered after start_episode")
	GameManager.clear_progress()


func test_start_pack_sets_overworld_state_and_registers_levels():
	GameManager.clear_progress()
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "k1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	_seed_pack_loader("mypack", ow, [lvl])
	GameManager.start_pack_no_scene_swap("mypack", ow)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	assert_eq(GameManager.current_overworld, ow)
	assert_eq(GameManager.pending_level, ow)
	assert_eq(GameManager.current_episode_id, "mypack")
	# _levels_by_id populated via register_level (existing seam). The loader
	# returns freshly disk-loaded Resource instances (not the in-memory ow/lvl
	# we saved), so verify registration by presence, not reference identity.
	assert_eq(GameManager.get_level_by_id("ow").level_id, "ow")
	assert_eq(GameManager.get_level_by_id("k1_01").level_id, "k1_01")
	# fresh session: progress cleared on start_pack
	assert_false(GameManager.is_level_completed("k1_01"))

func test_current_scope_kind_defaults_episode():
	assert_eq(GameManager.current_scope_kind, "episode")


func test_serialize_carries_scope_kind_and_round_trips():
	GameManager.current_scope_kind = "pack"
	GameManager.current_episode_id = "mypack"
	GameManager.mark_completed("lvl1")
	var data := GameManager.serialize()
	assert_eq(data.get("current_scope_kind", ""), "pack")
	GameManager.clear_progress()
	assert_eq(GameManager.current_scope_kind, "episode")
	GameManager.deserialize(data)
	assert_eq(GameManager.current_scope_kind, "pack")
	assert_eq(GameManager.current_episode_id, "mypack")
	assert_true(GameManager.is_level_completed("lvl1"))


func test_resume_overworld_episode_registers_levels_without_clearing():
	# Seed completion state as if loaded from a save.
	GameManager.current_scope_kind = "episode"
	GameManager.current_episode_id = "keen1"
	GameManager.mark_completed("keen1_01")
	var ep := GameManager._find_episode("keen1")
	assert_not_null(ep)
	var ow := ep.load_overworld()
	assert_not_null(ow)
	# resume_overworld_no_scene_swap must register the overworld + episode
	# levels without wiping the just-restored completion set.
	var ok := GameManager.resume_overworld_no_scene_swap()
	assert_true(ok)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	# load_overworld() uses ResourceLoader.CACHE_MODE_IGNORE, so the instance
	# held here and the one resume re-resolved differ by identity; compare by id.
	assert_eq(GameManager.current_overworld.level_id, ow.level_id)
	assert_not_null(GameManager.get_level_by_id("keen1_01"))
	assert_true(GameManager.is_level_completed("keen1_01"), "completion preserved")


func test_resume_overworld_missing_episode_returns_false():
	GameManager.current_scope_kind = "episode"
	GameManager.current_episode_id = "no_such_episode"
	assert_false(GameManager.resume_overworld_no_scene_swap())


func test_start_pack_no_scene_swap_does_not_clear_progress():
	# Per Plan 6c: start_pack_no_scene_swap no longer hard-clears; the public
	# start_pack wrapper clears for the new-game path, and the load path uses
	# resume_overworld_no_scene_swap instead.
	GameManager.mark_completed("pre_existing")
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	_seed_pack_loader("clrpack", ow, [])
	GameManager.start_pack_no_scene_swap("clrpack", ow)
	assert_true(GameManager.is_level_completed("pre_existing"), "progress must survive _no_scene_swap")
	assert_eq(GameManager.current_scope_kind, "pack")


func test_save_active_noop_without_active_slot():
	# save_active must be a no-op (no file/dir created) when active_slot == 0.
	SaveSystem.active_slot = 0
	assert_true(SaveSystem.save_active())
	assert_false(DirAccess.dir_exists_absolute(SAVES_TMP))


func test_serialize_carries_scope_kind_post_resume():
	# After resume sets scope_kind, serialize must round-trip it.
	GameManager.current_scope_kind = "pack"
	var data := GameManager.serialize()
	assert_eq(data["current_scope_kind"], "pack")
	GameManager.clear_progress()
	GameManager.deserialize(data)
	assert_eq(GameManager.current_scope_kind, "pack")


func test_resume_overworld_pack_registers_levels_without_clearing():
	# Install a real pack, seed completion as if loaded from a save.
	var ow := LevelData.new()
	ow.level_id = "ow"
	ow.width = 2
	ow.height = 2
	ow.fill_blank()
	ow.map_kind = LevelData.MapKind.OVERWORLD
	var lvl := LevelData.new()
	lvl.level_id = "p1_01"
	lvl.width = 2
	lvl.height = 2
	lvl.fill_blank()
	_seed_pack_loader("resumepack", ow, [lvl])
	GameManager.current_scope_kind = "pack"
	GameManager.current_episode_id = "resumepack"
	GameManager.mark_completed("p1_01")
	var ok := GameManager.resume_overworld_no_scene_swap()
	assert_true(ok)
	assert_eq(GameManager.state, GameManager.State.OVERWORLD)
	# Disk-loaded resources (CACHE_MODE_IGNORE) — verify by level_id, not identity.
	assert_eq(GameManager.current_overworld.level_id, "ow")
	assert_not_null(GameManager.get_level_by_id("p1_01"), "pack level registered")
	assert_not_null(GameManager.get_level_by_id("ow"), "pack overworld registered")
	assert_true(GameManager.is_level_completed("p1_01"), "completion preserved")


func test_resume_overworld_missing_pack_returns_false():
	# current_episode_id points at a pack that PackLoader does not have.
	GameManager.current_scope_kind = "pack"
	GameManager.current_episode_id = "ghost_pack"
	assert_false(GameManager.resume_overworld_no_scene_swap())


func test_serialize_carries_inventory():
	Inventory.add_item("keen1.pogo")
	var data := GameManager.serialize()
	assert_true(data.has("inventory"))
	assert_true(data["inventory"].has("keen1.pogo"))


func test_deserialize_restores_inventory():
	var data := {"completed_levels": [], "current_episode_id": "", "current_scope_kind": "episode", "inventory": {"keen1.pogo": true}}
	GameManager.deserialize(data)
	assert_true(Inventory.has_item("keen1.pogo"))


func test_clear_progress_clears_inventory():
	Inventory.add_item("keen1.pogo")
	GameManager.clear_progress()
	assert_false(Inventory.has_item("keen1.pogo"))


func test_deserialize_old_save_without_inventory_key():
	# Pre-this-plan saves lack the inventory key — must not error.
	var data := {"completed_levels": ["x"], "current_episode_id": "keen1", "current_scope_kind": "episode"}
	GameManager.deserialize(data)
	assert_false(Inventory.has_item("keen1.pogo"))
	assert_true(GameManager.is_level_completed("x"))
