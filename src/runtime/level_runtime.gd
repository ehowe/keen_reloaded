class_name LevelRuntime
extends Node2D
## Builds a playable scene from a LevelData. Creates 3 TileMapLayers from the
## level's tile arrays, spawns the Player at player_spawn, and spawns every
## EntityDef via the registry. Test ▶ stashes the level in GameManager.pending_level,
## which _ready() consumes.
##
## TileSet selection: when level.tileset_ref is set, all 3 layers share that one
## authored TileSet (its per-tile collision applies to EVERY layer — author
## collision only on tiles meant for the geometry layer, or decor tiles placed
## in fg/bg will become invisible walls). When null, a ProceduralTileSet is built
## per layer (geometry=solid w/ collision; fg/bg=decor, no collision).

const RUNTIME_SCALE := 1
# Collision layers (mirror project.godot [layer_names]): bit 1 = player, bit 3 = tiles.
const COLLISION_LAYER_TILES := 4
const COLLISION_LAYER_PLAYER := 1
const WALL_THICKNESS := 256.0

var layers: Dictionary = {}  # layer_name -> TileMapLayer
var player: Node2D = null
var entities_spawned: Array[Node2D] = []

var _level: LevelData = null
var _tile_size: int = 64


func _ready() -> void:
	if GameManager != null and GameManager.pending_level != null:
		build(GameManager.pending_level)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if GameManager != null and GameManager.return_scene != null:
			get_tree().change_scene_to_packed(GameManager.return_scene)


## Tear down any previous build and assemble the world from `level`.
func build(level: LevelData) -> void:
	_clear()
	_level = level
	_tile_size = level.tile_size
	scale = Vector2(RUNTIME_SCALE, RUNTIME_SCALE)
	var ts := level.tile_size
	var ts_geo: TileSet
	var ts_decor: TileSet
	if level.tileset_ref != null:
		ts_geo = level.tileset_ref
		ts_decor = level.tileset_ref
	else:
		var max_id := _max_tile_id(level)
		ts_geo = ProceduralTileSet.build(max_id, ts, true)
		ts_decor = ProceduralTileSet.build(max_id, ts, false)
	layers[LevelData.LAYER_BACKGROUND] = _add_tile_layer(level, LevelData.LAYER_BACKGROUND, ts_decor)
	layers[LevelData.LAYER_FOREGROUND] = _add_tile_layer(level, LevelData.LAYER_FOREGROUND, ts_decor)
	layers[LevelData.LAYER_GEOMETRY] = _add_tile_layer(level, LevelData.LAYER_GEOMETRY, ts_geo)
	_spawn_player(level, ts)
	_spawn_entities(level, ts)
	_build_bounds(level, ts)


func _add_tile_layer(level: LevelData, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var tml := TileMapLayer.new()
	tml.name = "Tiles_" + layer_name
	tml.tile_set = tileset
	var src_id: int = TileAtlas.source_id(tileset)
	for y in range(level.height):
		for x in range(level.width):
			var id := level.get_tile(layer_name, x, y)
			if id > 0 and src_id >= 0:
				var coords := TileAtlas.atlas_coords_for_id(tileset, id)
				if coords.x >= 0:
					tml.set_cell(Vector2i(x, y), src_id, coords)
	add_child(tml)
	return tml


func _spawn_player(level: LevelData, ts: int) -> void:
	var p := preload("res://src/runtime/player/player.tscn").instantiate()
	p.position = Vector2(level.player_spawn) * float(ts)
	add_child(p)
	player = p
	var world_bounds := Rect2(
		Vector2.ZERO,
		Vector2(level.width * ts, level.height * ts) * RUNTIME_SCALE
	)
	p.set_camera_bounds(world_bounds)


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
	_level = null
	_tile_size = 64
	for c in get_children():
		c.queue_free()


## Builds invisible collision walls on the top/left/right edges of the map and a
## kill zone below the bottom edge (falls = respawn at player_spawn).
func _build_bounds(level: LevelData, ts: int) -> void:
	var w_px := float(level.width * ts)
	var h_px := float(level.height * ts)
	var t := WALL_THICKNESS
	# Side walls span beyond top/bottom so corners can't be clipped.
	_add_wall("BoundsWall_Left", Vector2(-t * 0.5, h_px * 0.5), Vector2(t, h_px + t * 2.0))
	_add_wall("BoundsWall_Right", Vector2(w_px + t * 0.5, h_px * 0.5), Vector2(t, h_px + t * 2.0))
	_add_wall("BoundsWall_Top", Vector2(w_px * 0.5, -t * 0.5), Vector2(w_px + t * 2.0, t))

	# Bottom kill zone: detect player (layer 1), respawn on entry.
	var kz := Area2D.new()
	kz.name = "BoundsKillZone"
	kz.collision_mask = COLLISION_LAYER_PLAYER
	kz.monitorable = true
	kz.monitoring = true
	var kshape := RectangleShape2D.new()
	kshape.size = Vector2(w_px + t * 2.0, t)
	var kcol := CollisionShape2D.new()
	kcol.shape = kshape
	kz.add_child(kcol)
	kz.position = Vector2(w_px * 0.5, h_px + t * 0.5)
	kz.body_entered.connect(_on_kill_zone_body_entered)
	add_child(kz)


func _add_wall(node_name: String, center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.collision_layer = COLLISION_LAYER_TILES
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	wall.add_child(col)
	wall.position = center
	add_child(wall)


func _on_kill_zone_body_entered(body: Node2D) -> void:
	if body != player or not is_instance_valid(player):
		return
	# Respawn at spawn point and zero velocity. take_damage gives the fall a cost.
	player.position = Vector2(_level.player_spawn) * float(_tile_size)
	player.velocity = Vector2.ZERO
	if player.has_method("take_damage"):
		player.take_damage(1)
