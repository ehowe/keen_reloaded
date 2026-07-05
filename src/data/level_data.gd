class_name LevelData
extends Resource
## Full data for a single level. Serialized to .tres. The single source of
## truth: the editor writes it, the runtime reads it.

const LAYER_GEOMETRY := "geometry"
const LAYER_FOREGROUND := "foreground"
const LAYER_BACKGROUND := "background"

@export_group("Metadata")
@export var level_id: String = ""
@export var level_name: String = ""
@export var episode: String = ""
@export var order: int = 0

@export_group("Dimensions")
@export var width: int = 0
@export var height: int = 0
@export var tile_size: int = 64

@export_group("Tile Layers")
@export var geometry_tiles: PackedInt32Array = []
@export var foreground_tiles: PackedInt32Array = []
@export var background_tiles: PackedInt32Array = []

@export_group("Entities")
@export var entities: Array[EntityDef] = []

@export_group("Spawn / Exit")
@export var player_spawn: Vector2i = Vector2i.ZERO
@export var exit_type: String = ""
@export var exit_position: Vector2i = Vector2i.ZERO
@export var exit_target_level_id: String = ""

@export_group("Assets")
@export var tileset_ref: TileSet = null
@export var music: Resource = null
@export var background_ref: Resource = null


## Returns the flat array index for tile (x, y), or -1 if out of bounds.
func tile_index_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return -1
	return x + y * width


## Initializes every tile layer to size width*height filled with 0 (empty).
func fill_blank() -> void:
	var count := width * height
	geometry_tiles.resize(count)
	geometry_tiles.fill(0)
	foreground_tiles.resize(count)
	foreground_tiles.fill(0)
	background_tiles.resize(count)
	background_tiles.fill(0)


## Resizes the level to new_w x new_h, PRESERVING existing tiles. New rows are
## added/removed at the TOP (y=0); new columns at the RIGHT (x=max). The
## bottom-left cell stays anchored. Entities and player_spawn shift vertically
## with added/removed rows; entities landing outside the new bounds are dropped.
func resize(new_w: int, new_h: int) -> void:
	new_w = maxi(new_w, 0)
	new_h = maxi(new_h, 0)
	var old_w := width
	var old_h := height
	var delta_h := new_h - old_h
	geometry_tiles = _remap_tiles(geometry_tiles, old_w, old_h, new_w, new_h, delta_h)
	foreground_tiles = _remap_tiles(foreground_tiles, old_w, old_h, new_w, new_h, delta_h)
	background_tiles = _remap_tiles(background_tiles, old_w, old_h, new_w, new_h, delta_h)
	width = new_w
	height = new_h
	# Columns change at the right -> entity x unchanged. Rows change at the top
	# -> entity y shifts by delta_h; out-of-bounds entities are dropped.
	var kept: Array[EntityDef] = []
	for e in entities:
		var ny := e.y + delta_h
		if e.x < 0 or e.x >= new_w or ny < 0 or ny >= new_h:
			continue
		e.y = ny
		kept.append(e)
	entities = kept
	# Player spawn follows the same vertical shift; clamp into bounds (kept).
	var sx := player_spawn.x
	var sy := player_spawn.y + delta_h
	if new_w > 0:
		sx = clampi(sx, 0, new_w - 1)
	if new_h > 0:
		sy = clampi(sy, 0, new_h - 1)
	player_spawn = Vector2i(sx, sy)


## Rebuilds a tile layer for a resize. Copies each old cell (x, y) to
## (x, y + delta_h) when it lands inside the new bounds; everything else is 0.
static func _remap_tiles(arr: PackedInt32Array, old_w: int, old_h: int, new_w: int, new_h: int, delta_h: int) -> PackedInt32Array:
	var count := maxi(new_w * new_h, 0)
	var out := PackedInt32Array()
	out.resize(count)
	if count > 0:
		out.fill(0)
	if old_w <= 0 or old_h <= 0 or arr.size() == 0:
		return out
	for y in range(old_h):
		var ny := y + delta_h
		if ny < 0 or ny >= new_h:
			continue
		for x in range(old_w):
			if x >= new_w:
				break
			var oi := x + y * old_w
			if oi >= arr.size():
				break
			out[x + ny * new_w] = arr[oi]
	return out


## Returns the geometry tile id at (x, y). 0 if out of bounds.
func get_geometry_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0 or idx >= geometry_tiles.size():
		return 0
	return geometry_tiles[idx]


## Sets the geometry tile id at (x, y). Ignored if out of bounds.
func set_geometry_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0 or idx >= geometry_tiles.size():
		return
	geometry_tiles[idx] = tile_id


## Returns the foreground tile id at (x, y). 0 if out of bounds.
func get_foreground_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0 or idx >= foreground_tiles.size():
		return 0
	return foreground_tiles[idx]


## Sets the foreground tile id at (x, y). Ignored if out of bounds.
func set_foreground_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0 or idx >= foreground_tiles.size():
		return
	foreground_tiles[idx] = tile_id


## Returns the background tile id at (x, y). 0 if out of bounds.
func get_background_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0 or idx >= background_tiles.size():
		return 0
	return background_tiles[idx]


## Sets the background tile id at (x, y). Ignored if out of bounds.
func set_background_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0 or idx >= background_tiles.size():
		return
	background_tiles[idx] = tile_id


## Generic layer access: returns the tile id at (x,y) for the named layer.
## Unknown layers and out-of-bounds cells return 0.
func get_tile(layer: String, x: int, y: int) -> int:
	match layer:
		LAYER_GEOMETRY:
			return get_geometry_tile(x, y)
		LAYER_FOREGROUND:
			return get_foreground_tile(x, y)
		LAYER_BACKGROUND:
			return get_background_tile(x, y)
	return 0


## Generic layer access: sets the tile id at (x,y) for the named layer.
## Unknown layers / out-of-bounds cells are ignored.
func set_tile(layer: String, x: int, y: int, tile_id: int) -> void:
	match layer:
		LAYER_GEOMETRY:
			set_geometry_tile(x, y, tile_id)
		LAYER_FOREGROUND:
			set_foreground_tile(x, y, tile_id)
		LAYER_BACKGROUND:
			set_background_tile(x, y, tile_id)
