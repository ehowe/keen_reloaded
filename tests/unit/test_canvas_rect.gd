extends GutTest


func test_rect_from_corners_normal():
	var r := CanvasEditor.rect_from_corners(Vector2i(2, 3), Vector2i(5, 7))
	assert_eq(r.position, Vector2i(2, 3), "position is min corner")
	assert_eq(r.size, Vector2i(4, 5), "size is inclusive cell count")


func test_rect_from_corners_reversed():
	# Corners given in any order; result is the same normalized rect.
	var r := CanvasEditor.rect_from_corners(Vector2i(5, 7), Vector2i(2, 3))
	assert_eq(r.position, Vector2i(2, 3), "position is min corner regardless of order")
	assert_eq(r.size, Vector2i(4, 5), "size is inclusive cell count")


func test_rect_from_corners_same_cell():
	var r := CanvasEditor.rect_from_corners(Vector2i(4, 4), Vector2i(4, 4))
	assert_eq(r.position, Vector2i(4, 4))
	assert_eq(r.size, Vector2i(1, 1), "single cell -> 1x1")
