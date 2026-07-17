extends GutTest

## Unit tests for ShapeUtil (extracted from _rect_half_of in yorp.gd and
## _shape_half_height in garg.gd).


func _node_with_rect(name: String, size: Vector2) -> Node2D:
	var n := Node2D.new()
	var cs := CollisionShape2D.new()
	cs.name = name
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	n.add_child(cs)
	return n


func test_rect_half_returns_half_size():
	var n := _node_with_rect("BodyShape", Vector2(40, 60))
	add_child_autofree(n)
	assert_eq(ShapeUtil.rect_half(n, "BodyShape"), Vector2(20, 30), "full half-extent")


func test_rect_half_missing_node_returns_zero():
	var n := Node2D.new()
	add_child_autofree(n)
	assert_eq(ShapeUtil.rect_half(n, "BodyShape"), Vector2.ZERO, "no shape node -> ZERO")


func test_rect_half_non_rect_shape_returns_zero():
	var n := Node2D.new()
	var cs := CollisionShape2D.new()
	cs.name = "BodyShape"
	var circ := CircleShape2D.new()
	circ.radius = 10.0
	cs.shape = circ
	n.add_child(cs)
	add_child_autofree(n)
	assert_eq(ShapeUtil.rect_half(n, "BodyShape"), Vector2.ZERO, "non-rect shape -> ZERO")
