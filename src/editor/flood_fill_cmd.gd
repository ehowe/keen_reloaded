class_name FloodFillCmd
extends EditorCommand
## Flood-fills the 4-connected region (starting at origin) whose cells equal the
## origin's current id, setting them to new_id. Stores the previous id per changed
## cell so undo fully restores the region.

var layer: String
var origin: Vector2i
var new_id: int
var _changed: Dictionary = {}  # Vector2i -> int (previous id)

func _init(p_layer: String, p_origin: Vector2i, p_new_id: int) -> void:
	layer = p_layer
	origin = p_origin
	new_id = p_new_id

func apply(level: LevelData) -> void:
	_changed.clear()
	var target := level.get_tile(layer, origin.x, origin.y)
	if target == new_id:
		return
	var stack: Array[Vector2i] = [origin]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c):
			continue
		if c.x < 0 or c.y < 0 or c.x >= level.width or c.y >= level.height:
			continue
		if level.get_tile(layer, c.x, c.y) != target:
			continue
		seen[c] = true
		_changed[c] = target
		level.set_tile(layer, c.x, c.y, new_id)
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))

func undo(level: LevelData) -> void:
	for cell: Vector2i in _changed:
		level.set_tile(layer, cell.x, cell.y, int(_changed[cell]))

func describe() -> String:
	return "FloodFill(%s @ %s -> %d)" % [layer, str(origin), new_id]
