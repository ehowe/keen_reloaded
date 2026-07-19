extends GutTest

## Characterization tests for Ship overworld entity: proximity detection and
## the interact gating of attempt_show_progress. Locks current behavior so the
## ProximityInteractable extraction (#5) cannot regress Ship.


func _ship() -> Ship:
	var s := Ship.new()
	add_child_autofree(s)
	return s


func _player_body() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	return p


func test_attempt_show_progress_requires_nearby():
	var s := _ship()
	assert_false(s.attempt_show_progress(true), "no nearby -> no progress")


func test_attempt_show_progress_requires_interact():
	var s := _ship()
	s._set_nearby_for_test(true)
	assert_false(s.attempt_show_progress(false), "nearby but no interact -> no progress")
	assert_true(s.attempt_show_progress(true), "nearby + interact -> progress shown")


func test_non_player_body_does_not_set_nearby():
	var s := _ship()
	var decoy := StaticBody2D.new()
	add_child_autofree(decoy)
	s._on_body_entered(decoy)
	assert_false(s.attempt_show_progress(true), "non-player body must not activate proximity")


func test_player_body_sets_nearby():
	var s := _ship()
	s._on_body_entered(_player_body())
	assert_true(s.attempt_show_progress(true), "player body activates proximity")


func test_player_exit_clears_nearby():
	var s := _ship()
	var p := _player_body()
	s._on_body_entered(p)
	s._on_body_exited(p)
	assert_false(s.attempt_show_progress(true), "exit clears nearby")


func test_attempt_show_progress_emits_signal():
	var s := _ship()
	s._set_nearby_for_test(true)
	var captured := {"collected": -1, "total": -1}
	s.progress_requested.connect(func(c: int, t: int, _parts: Array) -> void:
		captured["collected"] = c
		captured["total"] = t)
	assert_true(s.attempt_show_progress(true))
	assert_eq(captured["collected"], 0, "starts with zero collected")
	assert_eq(captured["total"], s.REQUIRED_PARTS.size(), "total = required parts count")


func before_each():
	Inventory.clear()


func after_each():
	Inventory.clear()


func test_collected_count_starts_at_zero():
	var s := _ship()
	assert_eq(s.collected_count(), 0, "no inventory items -> zero parts collected")


func test_collected_count_increments_when_battery_granted():
	var s := _ship()
	Inventory.add_item(ItemIDs.BATTERY)
	assert_eq(s.collected_count(), 1, "battery in inventory -> one part collected")


func test_is_part_collected_reflects_inventory():
	var s := _ship()
	assert_false(s.is_part_collected("Battery"), "not collected before grant")
	Inventory.add_item(ItemIDs.BATTERY)
	assert_true(s.is_part_collected("Battery"), "collected after grant")


func test_is_part_collected_unknown_name_returns_false():
	var s := _ship()
	Inventory.add_item(ItemIDs.BATTERY)
	assert_false(s.is_part_collected("Nonexistent Part"), "unknown name -> false")
