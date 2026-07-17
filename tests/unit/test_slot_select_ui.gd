extends GutTest

const SLOT_SELECT := preload("res://src/ui/slot_select.tscn")

func before_each():
	SaveSystem.saves_dir = "user://tmp_slot_ui/"
	PackLoader._remove_dir_recursive("user://tmp_slot_ui/")

func after_each():
	PackLoader._remove_dir_recursive("user://tmp_slot_ui/")
	SaveSystem.saves_dir = SaveSystem.DEFAULT_SAVES_DIR
	GameManager.clear_progress()

func test_card_text_empty():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert_true(ss._card_text({"slot": 1, "status": "empty"}).find("Empty") >= 0, "empty slot card should say 'Empty'")
	ss.queue_free()

func test_card_text_occupied():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	var t: String = ss._card_text({"slot": 2, "status": "occupied", "scope_title": "Keen 1", "completed_count": 3, "saved_at": 1700000000, "kind": "episode", "scope_id": "keen1"})
	assert_true(t.find("Keen 1") >= 0, "occupied card should include scope title")
	assert_true(t.find("3") >= 0, "occupied card should include completed count")
	ss.queue_free()

func test_card_text_corrupt():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert_true(ss._card_text({"slot": 3, "status": "corrupt"}).find("Corrupt") >= 0, "corrupt slot card should say 'Corrupt'")
	ss.queue_free()

func test_card_text_missing_pack():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert_true(ss._card_text({"slot": 1, "status": "missing_pack"}).find("missing") >= 0, "missing_pack card should say 'missing'")
	ss.queue_free()

func test_card_text_unsupported_version():
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert_true(ss._card_text({"slot": 1, "status": "unsupported_version", "version": 999}).find("Unsupported") >= 0, "unsupported_version card should say 'Unsupported'")
	ss.queue_free()

func test_repopulate_shows_all_six_slots():
	# add_child triggers _ready → _repopulate against the empty temp saves_dir,
	# producing one button per slot (all "empty").
	var ss := SLOT_SELECT.instantiate()
	add_child(ss)
	assert_eq(ss.grid.get_child_count(), 6)
	ss.queue_free()
