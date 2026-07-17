class_name ShapeUtil
extends RefCounted
## Shared CollisionShape2D helpers extracted from duplicated statics in
## yorp.gd (_rect_half_of) and garg.gd (_shape_half_height).


## Half-extent (Vector2) of the RectangleShape2D named `shape_name` under
## `node`, or Vector2.ZERO when the node is absent or not a rectangle. Callers
## that only need one axis read `.x` / `.y` from the result.
static func rect_half(node: Node, shape_name: String) -> Vector2:
	var cs := node.get_node_or_null(shape_name) as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		return (cs.shape as RectangleShape2D).size * 0.5
	return Vector2.ZERO
