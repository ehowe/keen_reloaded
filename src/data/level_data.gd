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
@export var tile_size: int = 16

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


## Returns the geometry tile id at (x, y). 0 if out of bounds.
func get_geometry_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return 0
	return geometry_tiles[idx]


## Sets the geometry tile id at (x, y). Ignored if out of bounds.
func set_geometry_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return
	geometry_tiles[idx] = tile_id


## Returns the foreground tile id at (x, y). 0 if out of bounds.
func get_foreground_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return 0
	return foreground_tiles[idx]


## Sets the foreground tile id at (x, y). Ignored if out of bounds.
func set_foreground_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return
	foreground_tiles[idx] = tile_id


## Returns the background tile id at (x, y). 0 if out of bounds.
func get_background_tile(x: int, y: int) -> int:
	var idx := tile_index_at(x, y)
	if idx < 0:
		return 0
	return background_tiles[idx]


## Sets the background tile id at (x, y). Ignored if out of bounds.
func set_background_tile(x: int, y: int, tile_id: int) -> void:
	var idx := tile_index_at(x, y)
	if idx < 0:
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
