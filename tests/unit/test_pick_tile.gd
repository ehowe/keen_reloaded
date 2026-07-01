extends GutTest

const G := "geometry"
const F := "foreground"
const B := "background"


func _editor() -> LevelEditor:
	var scene: PackedScene = load("res://src/editor/level_editor.tscn")
	var inst: LevelEditor = scene.instantiate()
	add_child_autofree(inst)
	return inst


func test_pick_nonempty_sets_brush_and_paint_tool():
	var e := _editor()
	e.level.set_tile(G, 2, 2, 5)
	e.set_tool("erase")
	e.pick_tile_at(Vector2i(2, 2))
	assert_eq(e.selected_tile_id, 5, "picked tile becomes the brush")
	assert_eq(e.active_tool, "paint", "auto-switches to paint")


func test_pick_empty_cell_is_noop():
	var e := _editor()
	e.set_tool("erase")
	e.set_selected_tile_id(3)
	e.pick_tile_at(Vector2i(1, 1))
	assert_eq(e.selected_tile_id, 3, "brush unchanged on empty cell")
	assert_eq(e.active_tool, "erase", "tool unchanged on empty cell")


func test_pick_reads_active_layer_only():
	var e := _editor()
	# tile exists on foreground only; active layer defaults to geometry
	e.set_active_layer(G)
	e.level.set_tile(F, 0, 0, 7)
	e.pick_tile_at(Vector2i(0, 0))
	assert_eq(e.selected_tile_id, 1, "no pick from non-active layer (keeps default)")


func test_pick_after_layer_switch_reads_new_layer():
	var e := _editor()
	e.level.set_tile(B, 4, 4, 9)
	e.set_active_layer(B)
	e.pick_tile_at(Vector2i(4, 4))
	assert_eq(e.selected_tile_id, 9, "picks from newly active layer")
	assert_eq(e.active_tool, "paint")


func test_pick_out_of_bounds_is_noop():
	var e := _editor()
	e.level.set_tile(G, 0, 0, 6)
	e.set_tool("erase")
	# bottom-right valid cell is (width-1, height-1); go past it
	var oob := Vector2i(e.level.width, e.level.height)
	e.pick_tile_at(oob)
	assert_eq(e.selected_tile_id, 1, "brush unchanged out of bounds")
	assert_eq(e.active_tool, "erase", "tool unchanged out of bounds")
