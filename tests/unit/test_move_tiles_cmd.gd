extends GutTest

const G := "geometry"
const F := "foreground"
const B := "background"


func _level(w: int, h: int) -> LevelData:
	var l := LevelData.new()
	l.width = w
	l.height = h
	l.fill_blank()
	return l


func test_move_filled_tiles_single_layer():
	var l := _level(8, 8)
	l.set_tile(G, 1, 1, 5)
	l.set_tile(G, 2, 1, 6)
	var cmd := MoveTilesCmd.new()
	cmd.add_layer(G, {Vector2i(1, 1): 5, Vector2i(2, 1): 6})
	cmd.set_delta(Vector2i(3, 0))
	cmd.apply(l)
	assert_eq(l.get_tile(G, 1, 1), 0, "src cell cleared")
	assert_eq(l.get_tile(G, 2, 1), 0, "src cell cleared")
	assert_eq(l.get_tile(G, 4, 1), 5, "dest cell written")
	assert_eq(l.get_tile(G, 5, 1), 6, "dest cell written")


func test_empty_source_cells_do_not_erase_dest():
	# Only filled cells are handed to the command (contract with LevelEditor).
	# A pre-existing destination tile under a gap must survive the move.
	var l := _level(8, 8)
	l.set_tile(G, 1, 1, 5)
	l.set_tile(G, 5, 1, 9)  # sits under where an empty src cell would land
	var cmd := MoveTilesCmd.new()
	cmd.add_layer(G, {Vector2i(1, 1): 5})
	cmd.set_delta(Vector2i(3, 0))
	cmd.apply(l)
	assert_eq(l.get_tile(G, 5, 1), 9, "gap did not erase dest")
	assert_eq(l.get_tile(G, 4, 1), 5, "filled src moved")
	assert_eq(l.get_tile(G, 1, 1), 0, "src cleared")


func test_multi_layer_move():
	var l := _level(8, 8)
	l.set_tile(G, 1, 1, 5)
	l.set_tile(F, 1, 1, 7)
	l.set_tile(B, 1, 1, 9)
	var cmd := MoveTilesCmd.new()
	cmd.add_layer(G, {Vector2i(1, 1): 5})
	cmd.add_layer(F, {Vector2i(1, 1): 7})
	cmd.add_layer(B, {Vector2i(1, 1): 9})
	cmd.set_delta(Vector2i(2, 0))
	cmd.apply(l)
	assert_eq(l.get_tile(G, 3, 1), 5, "geometry moved")
	assert_eq(l.get_tile(F, 3, 1), 7, "foreground moved")
	assert_eq(l.get_tile(B, 3, 1), 9, "background moved")
	assert_eq(l.get_tile(G, 1, 1), 0, "src cleared")


func test_overlap_undo_restores_exactly():
	# Move right by 1: dest of (1,1) is (2,1) which is itself a src cell.
	var l := _level(8, 8)
	l.set_tile(G, 1, 1, 5)
	l.set_tile(G, 2, 1, 6)
	var cmd := MoveTilesCmd.new()
	cmd.add_layer(G, {Vector2i(1, 1): 5, Vector2i(2, 1): 6})
	cmd.set_delta(Vector2i(1, 0))
	cmd.apply(l)
	assert_eq(l.get_tile(G, 1, 1), 0, "src cleared")
	assert_eq(l.get_tile(G, 2, 1), 5, "overlapped dest written")
	assert_eq(l.get_tile(G, 3, 1), 6, "dest written")
	cmd.undo(l)
	assert_eq(l.get_tile(G, 1, 1), 5, "undo restores src")
	assert_eq(l.get_tile(G, 2, 1), 6, "undo restores overlapped cell")
	assert_eq(l.get_tile(G, 3, 1), 0, "undo clears dest")


func test_undo_restores_dest_that_was_occupied():
	# Destination had its own tile before the move; undo must bring it back.
	var l := _level(8, 8)
	l.set_tile(G, 1, 1, 5)
	l.set_tile(G, 4, 1, 8)  # pre-existing dest tile
	var cmd := MoveTilesCmd.new()
	cmd.add_layer(G, {Vector2i(1, 1): 5})
	cmd.set_delta(Vector2i(3, 0))
	cmd.apply(l)
	assert_eq(l.get_tile(G, 4, 1), 5, "dest overwritten by move")
	cmd.undo(l)
	assert_eq(l.get_tile(G, 1, 1), 5, "src restored")
	assert_eq(l.get_tile(G, 4, 1), 8, "pre-existing dest tile restored")


func test_describe_contains_delta_and_layer_count():
	var cmd := MoveTilesCmd.new()
	cmd.add_layer(G, {Vector2i(0, 0): 1})
	cmd.add_layer(F, {Vector2i(0, 0): 2})
	cmd.set_delta(Vector2i(2, 3))
	var d := cmd.describe()
	assert_true(d.length() > 0, "describe is non-empty")
	assert_true(d.find("(2, 3)") >= 0, "describe includes delta")
	assert_true(d.find("2") >= 0, "describe includes layer count")
