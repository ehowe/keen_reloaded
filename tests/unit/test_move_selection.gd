extends GutTest

const G := "geometry"
const F := "foreground"
const B := "background"


func _editor() -> LevelEditor:
	var scene: PackedScene = load("res://src/editor/level_editor.tscn")
	var inst: LevelEditor = scene.instantiate()
	add_child_autofree(inst)
	return inst


func test_move_with_no_selection_is_noop():
	var e := _editor()
	e.level.set_tile(G, 2, 2, 5)
	# tile_selection defaults to zero-area (no selection)
	var ok := e.move_selection(Vector2i(1, 0))
	assert_false(ok, "returns false with no active selection")
	assert_eq(e.level.get_tile(G, 2, 2), 5, "level unchanged")


func test_move_with_zero_delta_is_noop():
	var e := _editor()
	e.level.set_tile(G, 2, 2, 5)
	e.tile_selection = Rect2i(2, 2, 2, 2)
	var ok := e.move_selection(Vector2i.ZERO)
	assert_false(ok, "returns false on zero delta")
	assert_eq(e.level.get_tile(G, 2, 2), 5, "level unchanged")


func test_move_all_empty_selection_is_noop():
	var e := _editor()
	e.tile_selection = Rect2i(2, 2, 3, 3)  # no tiles placed inside
	var ok := e.move_selection(Vector2i(1, 0))
	assert_false(ok, "returns false when nothing to move")
	assert_eq(e.tile_selection.position, Vector2i(2, 2), "selection did not move")


func test_move_blocked_when_dest_out_of_bounds():
	var e := _editor()
	# default level 32x24; place tile on right edge column
	e.level.set_tile(G, 31, 5, 7)
	e.tile_selection = Rect2i(30, 4, 3, 3)  # covers (31,5)
	var ok := e.move_selection(Vector2i(5, 0))  # dest x = 36 -> OOB
	assert_false(ok, "blocked when dest out of bounds")
	assert_eq(e.level.get_tile(G, 31, 5), 7, "level unchanged on block")
	assert_eq(e.tile_selection.position, Vector2i(30, 4), "selection unchanged on block")


func test_move_blocked_negative_out_of_bounds():
	var e := _editor()
	e.level.set_tile(G, 0, 0, 7)
	e.tile_selection = Rect2i(0, 0, 2, 2)
	var ok := e.move_selection(Vector2i(-1, 0))  # dest x = -1 -> OOB
	assert_false(ok, "blocked on negative OOB")
	assert_eq(e.level.get_tile(G, 0, 0), 7, "level unchanged")


func test_move_in_bounds_applies_and_advances_selection():
	var e := _editor()
	e.level.set_tile(G, 2, 2, 5)
	e.level.set_tile(F, 2, 2, 6)
	e.tile_selection = Rect2i(2, 2, 2, 2)
	var ok := e.move_selection(Vector2i(3, 0))
	assert_true(ok, "move applied")
	assert_eq(e.level.get_tile(G, 5, 2), 5, "geometry moved")
	assert_eq(e.level.get_tile(F, 5, 2), 6, "foreground moved")
	assert_eq(e.level.get_tile(G, 2, 2), 0, "src cleared")
	assert_eq(e.tile_selection.position, Vector2i(5, 2), "selection follows moved tiles")


func test_move_undo_reverts_all_layers():
	var e := _editor()
	e.level.set_tile(G, 2, 2, 5)
	e.level.set_tile(B, 2, 2, 9)
	e.tile_selection = Rect2i(2, 2, 2, 2)
	e.move_selection(Vector2i(3, 0))
	e.undo()
	assert_eq(e.level.get_tile(G, 2, 2), 5, "undo restores geometry")
	assert_eq(e.level.get_tile(B, 2, 2), 9, "undo restores background")


func test_clear_tile_selection_resets():
	var e := _editor()
	e.tile_selection = Rect2i(3, 3, 4, 4)
	e.clear_tile_selection()
	assert_eq(e.tile_selection.size, Vector2i.ZERO, "selection cleared to zero-area")
