extends GutTest

func _make_teleporter(tid := "a", dlevel := "lvl1", dtp := "b") -> Node2D:
	var t := Teleporter.new()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {
		"teleporter_id": tid,
		"destination_level_id": dlevel,
		"destination_teleporter_id": dtp,
	})
	return t

func test_setup_reads_properties():
	var t := _make_teleporter("alpha", "lvl2", "beta")
	assert_eq(t.teleporter_id, "alpha")
	assert_eq(t.destination_level_id, "lvl2")
	assert_eq(t.destination_teleporter_id, "beta")

func test_setup_defaults_empty():
	var t := Teleporter.new()
	add_child_autofree(t)
	t.setup("keen1.teleporter", {})
	assert_eq(t.teleporter_id, "")
	assert_eq(t.destination_level_id, "")
	assert_eq(t.destination_teleporter_id, "")

func test_attempt_teleport_requires_nearby():
	var t := _make_teleporter()
	assert_false(t.attempt_teleport(true))
	t._set_nearby_for_test(true)
	assert_true(t.attempt_teleport(true))

func test_attempt_teleport_requires_interact():
	var t := _make_teleporter()
	t._set_nearby_for_test(true)
	assert_false(t.attempt_teleport(false))

func test_attempt_teleport_requires_destination_fields():
	var t := _make_teleporter("a", "", "")
	t._set_nearby_for_test(true)
	assert_false(t.attempt_teleport(true))

func test_attempt_teleport_emits_configured_destination():
	var t := _make_teleporter("a", "lvl_x", "b")
	t._set_nearby_for_test(true)
	var captured := {"level": "", "teleporter": ""}
	t.teleport_requested.connect(func(lvl: String, tp: String) -> void:
		captured["level"] = lvl
		captured["teleporter"] = tp)
	assert_true(t.attempt_teleport(true))
	assert_eq(captured["level"], "lvl_x")
	assert_eq(captured["teleporter"], "b")
