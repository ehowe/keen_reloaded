extends GutTest

const TMP := "user://tmp_savetest/"

func before_each():
	SaveSystem.saves_dir = TMP
	SaveSystem.active_slot = 0
	_clean(TMP)
	DirAccess.make_dir_recursive_absolute(TMP)
	GameManager.clear_progress()

func after_each():
	_clean(TMP)
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	SaveSystem.active_slot = 0
	GameManager.clear_progress()
	PackLoader.root_dir = "user://levelpacks/"

func _clean(path: String) -> void:
	for slot in range(1, SaveSystem.SLOT_COUNT + 1):
		var base := path + "slot_%d.json" % slot
		DirAccess.remove_absolute(base)
		DirAccess.remove_absolute(base + ".bak")
		DirAccess.remove_absolute(base + ".tmp")
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

func test_list_slots_all_empty_by_default():
	var slots := SaveSystem.list_slots()
	assert_eq(slots.size(), SaveSystem.SLOT_COUNT)
	for s in slots:
		assert_eq(s["status"], "empty")

func test_list_slots_marks_occupied_after_save():
	_seed_game("episode", "keen1")
	assert_true(SaveSystem.save_slot(2))
	var slots := SaveSystem.list_slots()
	assert_eq(slots[1]["status"], "occupied")
	assert_eq(slots[1]["slot"], 2)
	assert_eq(slots[1]["kind"], "episode")
	assert_eq(slots[1]["scope_id"], "keen1")
	assert_eq(slots[1]["scope_title"], "Marooned on Mars")
	assert_eq(slots[1]["completed_count"], 2)
	assert_true(int(slots[1]["saved_at"]) > 0)
	# Other slots still empty.
	assert_eq(slots[0]["status"], "empty")
	assert_eq(slots[3]["status"], "empty")

func test_list_slots_corrupt_json():
	var f := FileAccess.open(TMP + "slot_3.json", FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	var slots := SaveSystem.list_slots()
	assert_eq(slots[2]["status"], "corrupt")

func test_list_slots_unsupported_version():
	var f := FileAccess.open(TMP + "slot_4.json", FileAccess.WRITE)
	f.store_string('{"version": 999, "data": {}}')
	f.close()
	var slots := SaveSystem.list_slots()
	assert_eq(slots[3]["status"], "unsupported_version")

func test_list_slots_missing_pack():
	# Save a pack slot for a pack that is not installed.
	_seed_game("pack", "ghost_pack")
	# Force the file to exist even though PackLoader has no such pack: save
	# writes scope_title fallback = scope_id.
	assert_true(SaveSystem.save_slot(5))
	# PackLoader.get_overworld("ghost_pack") is null → missing_pack.
	var slots := SaveSystem.list_slots()
	assert_eq(slots[4]["status"], "missing_pack")
	assert_eq(slots[4]["kind"], "pack")

func test_list_slots_pack_present_marks_occupied():
	# Install a real pack and seed a save against it.
	const PK := "user://tmp_savetest_pack/"
	PackLoader.root_dir = PK
	DirAccess.make_dir_recursive_absolute(PK + "realpack/")
	ResourceSaver.save(_real_overworld(), PK + "realpack/overworld.tres")
	var mf := FileAccess.open(PK + "realpack/manifest.json", FileAccess.WRITE)
	mf.store_string('{"pack_id": "realpack", "name": "Real", "author": "qa", "version": "1.0", "levels": [{"level_id": "ow", "file": "overworld.tres", "name": "OW", "order": 0}]}')
	mf.close()
	PackLoader.scan()
	_seed_game("pack", "realpack")
	assert_true(SaveSystem.save_slot(6))
	var slots := SaveSystem.list_slots()
	assert_eq(slots[5]["status"], "occupied")
	assert_eq(slots[5]["scope_title"], "Real")
	# cleanup
	PackLoader._remove_dir_recursive(PK)
	PackLoader.root_dir = "user://levelpacks/"

func _real_overworld() -> LevelData:
	var ld := LevelData.new()
	ld.level_id = "ow"
	ld.width = 2
	ld.height = 2
	ld.fill_blank()
	ld.map_kind = LevelData.MapKind.OVERWORLD
	return ld

func test_delete_slot_removes_file_and_bak():
	_seed_game()
	assert_true(SaveSystem.save_slot(1))
	GameManager.mark_completed("lvl_c")
	assert_true(SaveSystem.save_slot(1))   # creates .bak
	assert_true(FileAccess.file_exists(TMP + "slot_1.json"))
	assert_true(FileAccess.file_exists(TMP + "slot_1.json.bak"))
	SaveSystem.delete_slot(1)
	assert_false(FileAccess.file_exists(TMP + "slot_1.json"))
	assert_false(FileAccess.file_exists(TMP + "slot_1.json.bak"))

func test_delete_slot_clears_active_if_match():
	SaveSystem.active_slot = 3
	SaveSystem.delete_slot(3)
	assert_eq(SaveSystem.active_slot, 0)

func test_delete_slot_out_of_range_noop():
	SaveSystem.delete_slot(0)  # no crash
	SaveSystem.delete_slot(9)

func test_list_slots_corrupt_data_not_dict():
	# data present but not a Dictionary → corrupt (not occupied), matching
	# _read_and_validate's contract so list_slots status == load_slot outcome.
	var f := FileAccess.open(TMP + "slot_4.json", FileAccess.WRITE)
	f.store_string('{"version": 1, "data": "not a dict", "kind": "episode", "scope_id": "keen1"}')
	f.close()
	var slots := SaveSystem.list_slots()
	assert_eq(slots[3]["status"], "corrupt")
