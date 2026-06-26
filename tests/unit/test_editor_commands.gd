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

func test_add_entity_command():
	var ld := _level()
	var s := UndoStack.new()
	assert_eq(ld.entities.size(), 0)
	s.execute(ld, AddEntityCmd.new(EntityDef.new("vorticon", 1, 2)))
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].type, "vorticon")
	s.undo(ld)
	assert_eq(ld.entities.size(), 0)
	s.redo(ld)
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].x, 1)

func test_remove_entity_command_restores_on_undo():
	var ld := _level()
	ld.entities.append(EntityDef.new("candy", 3, 4, {"value": 100}))
	ld.entities.append(EntityDef.new("yorp", 5, 6))
	var s := UndoStack.new()
	s.execute(ld, RemoveEntityCmd.new(0))  # remove candy
	assert_eq(ld.entities.size(), 1)
	assert_eq(ld.entities[0].type, "yorp")
	s.undo(ld)
	assert_eq(ld.entities.size(), 2)
	assert_eq(ld.entities[0].type, "candy")
	assert_eq(ld.entities[0].properties.get("value"), 100, "restored entity keeps props")
	assert_eq(ld.entities[1].type, "yorp")

func test_remove_entity_out_of_range_is_noop():
	var ld := _level()
	var s := UndoStack.new()
	s.execute(ld, RemoveEntityCmd.new(0))  # empty list
	assert_eq(ld.entities.size(), 0)
	s.undo(ld)
	assert_eq(ld.entities.size(), 0)

func test_set_player_spawn_command():
	var ld := _level()
	ld.player_spawn = Vector2i(0, 0)
	var s := UndoStack.new()
	s.execute(ld, SetPlayerSpawnCmd.new(Vector2i(7, 3)))
	assert_eq(ld.player_spawn, Vector2i(7, 3))
	s.undo(ld)
	assert_eq(ld.player_spawn, Vector2i(0, 0))


