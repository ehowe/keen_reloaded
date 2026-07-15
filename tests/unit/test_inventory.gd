extends GutTest

func before_each():
	Inventory.clear()

func after_each():
	Inventory.clear()

func test_has_item_false_by_default():
	assert_false(Inventory.has_item("keen1.pogo"))

func test_add_then_has():
	Inventory.add_item("keen1.pogo")
	assert_true(Inventory.has_item("keen1.pogo"))

func test_add_is_idempotent():
	Inventory.add_item("keen1.pogo")
	Inventory.add_item("keen1.pogo")
	assert_true(Inventory.has_item("keen1.pogo"))

func test_remove_item():
	Inventory.add_item("keen1.pogo")
	Inventory.remove_item("keen1.pogo")
	assert_false(Inventory.has_item("keen1.pogo"))

func test_remove_nonexistent_is_noop():
	Inventory.remove_item("keen1.pogo")
	assert_false(Inventory.has_item("keen1.pogo"))

func test_clear_empties_all():
	Inventory.add_item("keen1.pogo")
	Inventory.add_item("keen1.key")
	Inventory.clear()
	assert_false(Inventory.has_item("keen1.pogo"))
	assert_false(Inventory.has_item("keen1.key"))

func test_serialize_round_trip():
	Inventory.add_item("keen1.pogo")
	Inventory.add_item("keen1.key")
	var data := Inventory.serialize()
	Inventory.clear()
	assert_false(Inventory.has_item("keen1.pogo"))
	Inventory.deserialize(data)
	assert_true(Inventory.has_item("keen1.pogo"))
	assert_true(Inventory.has_item("keen1.key"))

func test_deserialize_replaces_not_merges():
	Inventory.add_item("stale_item")
	Inventory.deserialize({"keen1.pogo": true})
	assert_false(Inventory.has_item("stale_item"))
	assert_true(Inventory.has_item("keen1.pogo"))

func test_deserialize_empty_dict_is_noop():
	Inventory.add_item("keen1.pogo")
	Inventory.deserialize({})
	assert_false(Inventory.has_item("keen1.pogo"))

func test_item_collected_emits_on_first_add():
	watch_signals(Inventory)
	Inventory.add_item("keen1.pogo")
	assert_signal_emitted_with_parameters(Inventory, "item_collected", ["keen1.pogo"])

func test_item_collected_does_not_emit_on_duplicate():
	Inventory.add_item("keen1.pogo")
	watch_signals(Inventory)
	Inventory.add_item("keen1.pogo")
	assert_signal_not_emitted(Inventory, "item_collected")
