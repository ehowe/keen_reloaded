extends GutTest

const TMP := "user://tmp_savetest/"

func before_each():
	SaveSystem.saves_dir = TMP
	SaveSystem.active_slot = 0
	_clean(TMP)
	GameManager.clear_progress()

func after_each():
	_clean(TMP)
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	SaveSystem.active_slot = 0
	GameManager.clear_progress()

func _clean(path: String) -> void:
	DirAccess.remove_absolute(path + "slot_1.json")
	DirAccess.remove_absolute(path + "slot_1.json.bak")
	DirAccess.remove_absolute(path + "slot_1.json.tmp")
	DirAccess.remove_absolute(path + "slot_2.json")
	DirAccess.remove_absolute(path + "slot_2.json.bak")
	DirAccess.remove_absolute(path + "slot_3.json")
	DirAccess.remove_absolute(path + "slot_6.json")
	DirAccess.remove_absolute(TMP)

func _seed_game(kind: String = "episode", scope_id: String = "keen1") -> void:
	GameManager.current_scope_kind = kind
	GameManager.current_episode_id = scope_id
	GameManager.mark_completed("lvl_a")
	GameManager.mark_completed("lvl_b")

func test_save_slot_writes_valid_json_file():
	_seed_game()
	var ok := SaveSystem.save_slot(1)
	assert_true(ok)
	assert_true(FileAccess.file_exists(TMP + "slot_1.json"))

func test_save_slot_round_trips_payload_fields():
	_seed_game("episode", "keen1")
	assert_true(SaveSystem.save_slot(1))
	var text := FileAccess.get_file_as_string(TMP + "slot_1.json")
	var parser := JSON.new()
	assert_eq(parser.parse(text), OK)
	var d: Dictionary = parser.data
	assert_eq(d["version"], SaveSystem.CURRENT_VERSION)
	assert_eq(d["kind"], "episode")
	assert_eq(d["scope_id"], "keen1")
	assert_eq(d["completed_count"], 2)
	assert_eq(d["data"]["current_episode_id"], "keen1")
	assert_eq(d["data"]["current_scope_kind"], "episode")
	assert_eq((d["data"]["completed_levels"] as Array).size(), 2)

func test_save_slot_sets_active_slot():
	_seed_game()
	assert_eq(SaveSystem.active_slot, 0)
	assert_true(SaveSystem.save_slot(3))
	assert_eq(SaveSystem.active_slot, 3)

func test_save_slot_rejects_out_of_range():
	_seed_game()
	assert_false(SaveSystem.save_slot(0))
	assert_false(SaveSystem.save_slot(7))

func test_save_slot_rotates_bak_from_previous():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	var first := FileAccess.get_file_as_string(TMP + "slot_1.json")
	# Change state and save again — previous content should land in .bak.
	GameManager.mark_completed("lvl_c")
	assert_true(SaveSystem.save_slot(1))
	assert_true(FileAccess.file_exists(TMP + "slot_1.json.bak"))
	assert_eq(FileAccess.get_file_as_string(TMP + "slot_1.json.bak"), first)

func test_save_active_noop_when_no_active_slot():
	_seed_game()
	SaveSystem.active_slot = 0
	assert_true(SaveSystem.save_active())  # no-op, returns true
	assert_false(FileAccess.file_exists(TMP + "slot_1.json"))

func test_save_active_writes_to_active_slot():
	_seed_game()
	SaveSystem.active_slot = 2
	assert_true(SaveSystem.save_active())
	assert_true(FileAccess.file_exists(TMP + "slot_2.json"))

func test_clear_active_resets_to_zero():
	SaveSystem.active_slot = 5
	SaveSystem.clear_active()
	assert_eq(SaveSystem.active_slot, 0)

func test_load_slot_round_trips_into_game_manager():
	_seed_game("episode", "keen1")
	assert_true(SaveSystem.save_slot(1))
	GameManager.clear_progress()
	assert_false(GameManager.is_level_completed("lvl_a"))
	assert_true(SaveSystem.load_slot(1))
	assert_true(GameManager.is_level_completed("lvl_a"))
	assert_true(GameManager.is_level_completed("lvl_b"))
	assert_eq(GameManager.current_episode_id, "keen1")
	assert_eq(GameManager.current_scope_kind, "episode")
	assert_eq(SaveSystem.active_slot, 1)

func test_load_slot_missing_file_returns_false():
	GameManager.clear_progress()
	assert_false(SaveSystem.load_slot(2))
	assert_eq(SaveSystem.active_slot, 0)

func test_load_slot_corrupt_json_returns_false():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	# Corrupt the primary file. No .bak yet (only one save) → load fails.
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string("{ not valid json")
	f.close()
	assert_false(SaveSystem.load_slot(1))

func test_load_slot_falls_back_to_bak_when_primary_corrupt():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))   # creates base
	_seed_game()
	GameManager.mark_completed("lvl_c")
	assert_true(SaveSystem.save_slot(1))   # rotates base → .bak
	# Now corrupt the primary; .bak holds the previous good save.
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	GameManager.clear_progress()
	assert_true(SaveSystem.load_slot(1))   # recovers from .bak
	# .bak was the first save (2 completions: lvl_a, lvl_b).
	assert_true(GameManager.is_level_completed("lvl_a"))
	assert_false(GameManager.is_level_completed("lvl_c"))

func test_load_slot_rejects_future_version():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	var text := FileAccess.get_file_as_string(TMP + "slot_1.json")
	text = text.replace('"version": 1', '"version": 999')
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	assert_false(SaveSystem.load_slot(1))

func test_load_slot_rejects_missing_data_key():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	# Hand-write a file that lacks the "data" key.
	var f := FileAccess.open(TMP + "slot_1.json", FileAccess.WRITE)
	f.store_string('{"version": 1, "kind": "episode", "scope_id": "keen1"}')
	f.close()
	assert_false(SaveSystem.load_slot(1))

func test_load_slot_rejects_out_of_range():
	assert_false(SaveSystem.load_slot(0))
	assert_false(SaveSystem.load_slot(7))
