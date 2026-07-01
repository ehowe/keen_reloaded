class_name MoveTilesCmd
extends EditorCommand
## Relocates a set of filled tiles by a fixed offset, across one or more layers.
## Only the filled cells handed in via add_layer() move; gaps do not erase the
## destination. One undo step restores both source and destination exactly,
## including overlapping source/destination regions.

var _delta: Vector2i = Vector2i.ZERO
var _layers: Dictionary = {}  # String(layer) -> Dictionary[Vector2i -> int] (filled src cells)
var _dst_prev: Dictionary = {}  # String(layer) -> Dictionary[Vector2i -> int] (dest previous id)


func set_delta(d: Vector2i) -> void:
	_delta = d


## True when no layer has any filled cell queued (nothing will move).
func is_empty() -> bool:
	if _layers.is_empty():
		return true
	for layer in _layers:
		if not (_layers[layer] as Dictionary).is_empty():
			return false
	return true


## Stores the filled-cell map (Vector2i -> id, id > 0) for one layer.
func add_layer(layer: String, cells: Dictionary) -> void:
	_layers[layer] = cells.duplicate()


func apply(level: LevelData) -> void:
	# 1. Snapshot destination previous ids (first time only).
	# 2. Clear source cells.
	# 3. Write source ids to destination cells.
	# Saving dst_prev and clearing src BEFORE writing dest keeps overlapping
	# regions correct (src ids are already captured in _layers).
	for layer in _layers:
		var src: Dictionary = _layers[layer]
		if not _dst_prev.has(layer):
			_dst_prev[layer] = {}
		var dstp: Dictionary = _dst_prev[layer]
		for cell: Vector2i in src:
			var d := cell + _delta
			if not dstp.has(d):
				dstp[d] = level.get_tile(layer, d.x, d.y)
		for cell: Vector2i in src:
			level.set_tile(layer, cell.x, cell.y, 0)
		for cell: Vector2i in src:
			var d := cell + _delta
			level.set_tile(layer, d.x, d.y, int(src[cell]))


func undo(level: LevelData) -> void:
	# 1. Restore destination cells to their pre-move ids.
	# 2. Restore source cells to their original ids.
	# For a cell that is both src and dest (overlap), step 1 restores the
	# pre-move value and step 2 restores the original src id; they agree there
	# because dst_prev captured the pre-move src id.
	for layer in _layers:
		if _dst_prev.has(layer):
			var dstp: Dictionary = _dst_prev[layer]
			for d: Vector2i in dstp:
				level.set_tile(layer, d.x, d.y, int(dstp[d]))
		var src: Dictionary = _layers[layer]
		for cell: Vector2i in src:
			level.set_tile(layer, cell.x, cell.y, int(src[cell]))


func describe() -> String:
	return "MoveTiles(Δ%s, %d layers)" % [str(_delta), _layers.size()]
