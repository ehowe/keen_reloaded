extends GutTest

func before_each():
	# entity_label() reads the registry; ensure the keen1 roster (incl. spike)
	# is present even if an earlier test script left the registry cleared.
	GameManager.register_episodes()


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


func test_entity_label_appends_enum_variant():
	# A spike EntityDef with facing=left -> "keen1.spike (left)".
	var def := EntityDef.new("keen1.spike", 0, 0, {"facing": "left"})
	assert_eq(CanvasEditor.entity_label(def), "keen1.spike (left)")

func test_entity_label_uses_schema_default_when_property_absent():
	var def := EntityDef.new("keen1.spike", 0, 0, {})
	# Schema default for facing is "right".
	assert_eq(CanvasEditor.entity_label(def), "keen1.spike (right)")

func test_entity_label_no_suffix_for_schemaless_entity():
	# A type with no enum schema (vorticon) -> bare type id.
	var def := EntityDef.new("keen1.vorticon", 0, 0, {"speed": 20})
	assert_eq(CanvasEditor.entity_label(def), "keen1.vorticon")
