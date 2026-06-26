extends GutTest

const G := "geometry"

func _level() -> LevelData:
	var ld := LevelData.new()
	ld.width = 3
	ld.height = 3
	ld.fill_blank()
	return ld

func test_paint_cells_single():
	var ld := _level()
	var cmd := PaintCellsCmd.new(G, 1)
	cmd.paint(ld, 0, 0)
	assert_eq(ld.get_tile(G, 0, 0), 1)
	cmd.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 0, "undo restores previous id")

func test_paint_cells_records_each_cell_once():
	var ld := _level()
	ld.set_tile(G, 1, 1, 4)  # pre-existing id
	var cmd := PaintCellsCmd.new(G, 2)
	cmd.paint(ld, 1, 1)
	cmd.paint(ld, 1, 1)  # same cell twice in a stroke
	cmd.paint(ld, 2, 0)
	assert_eq(ld.get_tile(G, 1, 1), 2)
	assert_eq(ld.get_tile(G, 2, 0), 2)
	cmd.undo(ld)
	assert_eq(ld.get_tile(G, 1, 1), 4, "restores original 4, not 0")
	assert_eq(ld.get_tile(G, 2, 0), 0)

func test_undo_stack_execute_and_undo():
	var ld := _level()
	var s := UndoStack.new()
	assert_false(s.can_undo())
	s.execute(ld, PaintCellsCmd.new(G, 5))
	assert_true(s.can_undo())
	assert_false(s.can_redo())
	s.undo(ld)
	assert_false(s.can_undo())
	assert_true(s.can_redo())

func test_undo_stack_push_applied_does_not_double_apply():
	var ld := _level()
	var s := UndoStack.new()
	var cmd := PaintCellsCmd.new(G, 3)
	cmd.paint(ld, 0, 0)  # applied live
	assert_eq(ld.get_tile(G, 0, 0), 3)
	s.push_applied(ld, cmd)  # record without re-applying
	assert_eq(ld.get_tile(G, 0, 0), 3, "no double apply")
	s.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 0)
	s.redo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 3)

func test_new_command_clears_redo():
	var ld := _level()
	var s := UndoStack.new()
	s.execute(ld, PaintCellsCmd.new(G, 1))
	s.undo(ld)
	assert_true(s.can_redo())
	s.execute(ld, PaintCellsCmd.new(G, 2))
	assert_false(s.can_redo(), "redo cleared after new command")

func test_flood_fill_fills_connected_region():
	var ld := _level()
	# carve an L-shaped region of 1s
	ld.set_tile(G, 0, 0, 1)
	ld.set_tile(G, 1, 0, 1)
	ld.set_tile(G, 0, 1, 1)
	var cmd := FloodFillCmd.new(G, Vector2i(0, 0), 2)
	UndoStack.new().execute(ld, cmd)
	assert_eq(ld.get_tile(G, 0, 0), 2)
	assert_eq(ld.get_tile(G, 1, 0), 2)
	assert_eq(ld.get_tile(G, 0, 1), 2)
	assert_eq(ld.get_tile(G, 1, 1), 0, "diagonal not connected, stays empty")
	assert_eq(ld.get_tile(G, 2, 0), 0)

func test_flood_fill_noop_when_same_id():
	var ld := _level()
	ld.set_tile(G, 0, 0, 3)
	var cmd := FloodFillCmd.new(G, Vector2i(0, 0), 3)  # same as target
	var s := UndoStack.new()
	s.execute(ld, cmd)
	assert_eq(ld.get_tile(G, 0, 0), 3)
	s.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 3, "nothing changed, undo is a noop too")

func test_flood_fill_undo_restores_varied_region():
	var ld := _level()
	ld.set_tile(G, 0, 0, 1)
	ld.set_tile(G, 1, 0, 1)
	ld.set_tile(G, 2, 0, 5)  # different id, not filled
	var s := UndoStack.new()
	s.execute(ld, FloodFillCmd.new(G, Vector2i(0, 0), 9))
	assert_eq(ld.get_tile(G, 0, 0), 9)
	s.undo(ld)
	assert_eq(ld.get_tile(G, 0, 0), 1)
	assert_eq(ld.get_tile(G, 1, 0), 1)
	assert_eq(ld.get_tile(G, 2, 0), 5)

