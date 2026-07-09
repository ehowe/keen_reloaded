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
var elapsed: float = 0.0
var _completed: bool = false
var _dying: bool = false

var _level: LevelData = null
var _tile_size: int = 64


func _ready() -> void:
	if GameManager != null and GameManager.pending_level != null:
		var lv := GameManager.pending_level
		GameManager.pending_level = null
		build(lv)
		if GameManager.pending_player_spawn.x >= 0 and is_instance_valid(player):
			player.position = _cell_center(GameManager.pending_player_spawn, _tile_size)
		GameManager.pending_player_spawn = Vector2i(-1, -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if GameManager != null and GameManager.return_scene != null:
			get_tree().change_scene_to_packed(GameManager.return_scene)


func _process(delta: float) -> void:
	if not _completed:
		elapsed += delta
	if _dying and not _completed and is_instance_valid(player):
		if _player_offscreen():
			_complete_death()


func _on_player_died() -> void:
	_dying = true


## True when the player has left the visible camera viewport (camera is clamped
## to world bounds, so a flying corpse eventually exits the rendered rect).
func _player_offscreen() -> bool:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	var vp := get_viewport_rect()
	var center := cam.get_screen_center_position() if cam != null else player.global_position
	var visible_rect := Rect2(center - vp.size * 0.5, vp.size)
	return not visible_rect.has_point(player.global_position)


func _complete_death() -> void:
	if _completed:
		return
	_dying = false
	_completed = true
	if GameManager != null and GameManager.return_scene != null:
		get_tree().change_scene_to_packed(GameManager.return_scene)
	elif GameManager != null and GameManager.current_overworld != null:
		GameManager.fail_level()
	else:
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")


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
	_drive_music(level)


## Play the level's music (looping), or stop music if the level has none.
func _drive_music(level: LevelData) -> void:
	if AudioManager == null:
		return
	if level.music is AudioStream:
		AudioManager.play_music(level.music)
	else:
		AudioManager.stop_music()


func _add_tile_layer(level: LevelData, layer_name: String, tileset: TileSet) -> TileMapLayer:
	var tml := TileMapLayer.new()
	tml.name = "Tiles_" + layer_name
	tml.tile_set = tileset
	var has_art := tileset != null and tileset.get_source_count() > 0
	for y in range(level.height):
		for x in range(level.width):
			var id := level.get_tile(layer_name, x, y)
			if id <= 0 or not has_art:
				continue
			# Per-cell source: a tile id packs source_index*STRIDE + cell, so
			# different cells may resolve to different atlas sources.
			var sid := TileAtlas.source_id_for_id(tileset, id)
			var coords := TileAtlas.atlas_coords_for_id(tileset, id)
			if sid >= 0 and coords.x >= 0:
				tml.set_cell(Vector2i(x, y), sid, coords)
	add_child(tml)
	return tml


func _cell_center(cell: Vector2i, ts: int) -> Vector2:
	var f := float(ts)
	return Vector2(cell.x * f + f * 0.5, cell.y * f + f * 0.5)


func _spawn_player(level: LevelData, ts: int) -> void:
	var p := preload("res://src/runtime/player/player.tscn").instantiate()
	p.position = _cell_center(level.player_spawn, ts)
	add_child(p)
	player = p
	var world_bounds := Rect2(
		Vector2.ZERO,
		Vector2(level.width * ts, level.height * ts) * RUNTIME_SCALE
	)
	p.set_camera_bounds(world_bounds)
	if level.map_kind == LevelData.MapKind.OVERWORLD:
		p.set_mode(Player.Mode.OVERWORLD)
	_build_hud(p)
	if p.has_signal("died"):
		p.died.connect(_on_player_died)


func _build_hud(p: Node) -> void:
	if _level.map_kind == LevelData.MapKind.OVERWORLD:
		return  # No score/ammo/HP HUD on the overworld.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var label := Label.new()
	label.name = "HUDLabel"
	label.position = Vector2(12, 8)
	label.text = _hud_text(int(p.get("score")), int(p.get("ammo")), int(p.get("health")))
	layer.add_child(label)
	if p.has_signal("score_changed"):
		p.score_changed.connect(func(s: int) -> void: label.text = _hud_text(s, int(p.get("ammo")), int(p.get("health"))))
	if p.has_signal("ammo_changed"):
		p.ammo_changed.connect(func(a: int) -> void: label.text = _hud_text(int(p.get("score")), a, int(p.get("health"))))
	if p.has_signal("health_changed"):
		p.health_changed.connect(func(h: int) -> void: label.text = _hud_text(int(p.get("score")), int(p.get("ammo")), h))


func _hud_text(score: int, ammo: int, hp: int) -> String:
	return "Score: %d   Ammo: %d   HP: %d" % [score, ammo, hp]


func _spawn_entities(level: LevelData, ts: int) -> void:
	for def: EntityDef in level.entities:
		var node := EntityRegistry.instantiate(def.type, _cell_center(Vector2i(def.x, def.y), ts), def.properties)
		if node != null:
			add_child(node)
			entities_spawned.append(node)
			if node is LevelEntrance:
				(node as LevelEntrance).set_tile(Vector2i(def.x, def.y))
				(node as LevelEntrance).refresh_blocking()
				(node as LevelEntrance).enter_requested.connect(_on_enter_requested)
			elif node.has_signal("level_completed"):
				node.level_completed.connect(_on_level_completed)


func _on_level_completed() -> void:
	if _completed:
		return
	_completed = true
	AudioManager.play_sfx("complete")
	var layer := CanvasLayer.new()
	layer.name = "CompletionOverlay"
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var panel: CompletionOverlay = preload("res://src/ui/completion_overlay.tscn").instantiate()
	layer.add_child(panel)
	var score := 0
	if is_instance_valid(player) and player.get("score") != null:
		score = int(player.score)
	panel.get_node("Label").text = "Level Complete!\nScore: %d\nTime: %.1f s\n\nPress any key / Esc" % [score, elapsed]
	panel.dismissed.connect(_on_completion_dismissed)
	get_tree().paused = true


func _on_enter_requested(target_level_id: String, tile: Vector2i) -> void:
	if GameManager != null:
		GameManager.enter_level(target_level_id, tile)


func _on_completion_dismissed() -> void:
	get_tree().paused = false
	if GameManager != null and GameManager.return_scene != null:
		# Test ▶ from the editor: go back to the editor.
		get_tree().change_scene_to_packed(GameManager.return_scene)
	elif GameManager != null and GameManager.current_overworld != null:
		# Overworld loop: return to the overworld at the entrance tile.
		GameManager.complete_level()
	else:
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")


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
	_completed = false
	_dying = false
	elapsed = 0.0
	for c in get_children():
		c.queue_free()


## Builds invisible collision walls on the top/left/right edges of the map. For
## LEVEL maps, also adds a kill zone below the bottom edge (falls = respawn at
## player_spawn); OVERWORLD maps are non-lethal.
func _build_bounds(level: LevelData, ts: int) -> void:
	var w_px := float(level.width * ts)
	var h_px := float(level.height * ts)
	var t := WALL_THICKNESS
	# Side walls span beyond top/bottom so corners can't be clipped.
	_add_wall("BoundsWall_Left", Vector2(-t * 0.5, h_px * 0.5), Vector2(t, h_px + t * 2.0))
	_add_wall("BoundsWall_Right", Vector2(w_px + t * 0.5, h_px * 0.5), Vector2(t, h_px + t * 2.0))
	_add_wall("BoundsWall_Top", Vector2(w_px * 0.5, -t * 0.5), Vector2(w_px + t * 2.0, t))

	# Bottom kill zone: levels only. Overworld is non-lethal (no fall death).
	if level.map_kind == LevelData.MapKind.LEVEL:
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
	# Damage first. A lethal fall triggers Player._die() inside take_damage,
	# which owns the launch velocity and must not be overwritten.
	if player.has_method("take_damage"):
		player.take_damage(1)
	# Respawn ONLY if still alive.
	if is_instance_valid(player) and int(player.get("health")) > 0:
		player.position = _cell_center(_level.player_spawn, _tile_size)
		player.velocity = Vector2.ZERO
