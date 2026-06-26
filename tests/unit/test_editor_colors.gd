extends GutTest

func test_empty_tile_is_transparent():
	assert_eq(EditorColors.tile_color(0).a, 0.0)

func test_positive_tiles_are_opaque():
	assert_eq(EditorColors.tile_color(1).a, 1.0)
	assert_eq(EditorColors.tile_color(7).a, 1.0)

func test_tile_color_is_stable():
	assert_eq(EditorColors.tile_color(3), EditorColors.tile_color(3))

func test_distinct_ids_give_distinct_colors():
	assert_ne(EditorColors.tile_color(1), EditorColors.tile_color(2))

func test_layer_tint_unknown_returns_white():
	assert_eq(EditorColors.layer_tint("nope"), Color(1, 1, 1, 1))
