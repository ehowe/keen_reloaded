class_name PaintCellsCmd
extends EditorCommand
## A paint or erase stroke over a set of cells. Each cell remembers its previous
## tile id so the whole stroke is a single undo step. Call paint() during a drag
## (applies live), then hand the command to UndoStack.push_applied() on mouse-up.

var layer: String
var new_id: int
var _prev: Dictionary = {}  # Vector2i -> int (previous id)

func _init(p_layer: String, p_new_id: int) -> void:
	layer = p_layer
	new_id = p_new_id

## Records the previous id (first time only) and writes the new id. Idempotent per cell.
func paint(level: LevelData, x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	if not _prev.has(cell):
		_prev[cell] = level.get_tile(layer, x, y)
	level.set_tile(layer, x, y, new_id)

func apply(level: LevelData) -> void:
	for cell: Vector2i in _prev:
		level.set_tile(layer, cell.x, cell.y, new_id)

func undo(level: LevelData) -> void:
	restore_tiles(level, layer, _prev)

func describe() -> String:
	return "PaintCells(%s -> %d, %d cells)" % [layer, new_id, _prev.size()]
