class_name LevelRuntime
extends Node2D
## Builds a playable scene from a LevelData. Creates 3 TileMapLayers from the
## level's tile arrays (geometry=solid TileSet w/ collision; fg/bg=decor TileSet),
## spawns the Player at player_spawn, and spawns every EntityDef via the registry.
## Test ▶ stashes the level in GameManager.pending_level, which _ready() consumes.

const RUNTIME_SCALE := 3

var layers: Dictionary = {}  # layer_name -> TileMapLayer
var player: Node2D = null
var entities_spawned: Array[Node2D] = []


func _ready() -> void:
	if GameManager != null and GameManager.pending_level != null:
		build(GameManager.pending_level)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		if GameManager != null and GameManager.return_scene != null:
			get_tree().change_scene_to_packed(GameManager.return_scene)


## Tear down any previous build and assemble the world from `level`.
func build(level: LevelData) -> void:
	_clear()
	scale = Vector2(RUNTIME_SCALE, RUNTIME_SCALE)
	var ts := level.tile_size
	var max_id := _max_tile_id(level)
	var solid := ProceduralTileSet.build(max_id, ts, true)
	var decor := ProceduralTileSet.build(max_id, ts, false)
	layers[LevelData.LAYER_BACKGROUND] = _add_tile_layer(level, LevelData.LAYER_BACKGROUND, decor)
	layers[LevelData.LAYER_FOREGROUND] = _add_tile_layer(level, LevelData.LAYER_FOREGROUND, decor)
	layers[LevelData.LAYER_GEOMETRY] = _add_tile_layer(level, LevelData.LAYER_GEOMETRY, solid)
	_spawn_player(level, ts)
	_spawn_entities(level, ts)


func _add_tile_layer(level: LevelData, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var tml := TileMapLayer.new()
	tml.name = "Tiles_" + layer_name
	tml.tile_set = tileset
	var src_id: int = tileset.get_source_id(0) if tileset.get_source_count() > 0 else -1
	for y in range(level.height):
		for x in range(level.width):
			var id := level.get_tile(layer_name, x, y)
			if id > 0 and src_id >= 0:
				tml.set_cell(Vector2i(x, y), src_id, Vector2i(id - 1, 0))
	add_child(tml)
	return tml


func _spawn_player(level: LevelData, ts: int) -> void:
	var p := preload("res://src/runtime/player/player.tscn").instantiate()
	p.position = Vector2(level.player_spawn) * float(ts)
	add_child(p)
	player = p


func _spawn_entities(level: LevelData, ts: int) -> void:
	for def: EntityDef in level.entities:
		var node := EntityRegistry.instantiate(def.type, Vector2(def.x, def.y) * float(ts), def.properties)
		if node != null:
			add_child(node)
			entities_spawned.append(node)


func _max_tile_id(level: LevelData) -> int:
	var m := 0
	for arr in [level.geometry_tiles, level.foreground_tiles, level.background_tiles]:
		for v in arr:
			m = maxi(m, v)
	return m


func _clear() -> void:
	player = null
	entities_spawned.clear()
	layers.clear()
	for c in get_children():
		c.queue_free()
