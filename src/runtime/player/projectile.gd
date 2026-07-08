class_name Projectile
extends Area2D
## Raygun bolt. Linear motion in the launch direction; despawns on lifetime
## expiry, on hitting an enemy (deals 1 damage), or on hitting a wall/solid tile.
## Passes through items (entities without take_damage) and one-way platforms
## (jump-through floors): one-way tile polygons are treated as non-blocking.

@export var speed: float = 600.0
@export var lifetime: float = 2.0

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if body_entered.is_connected(_on_body_entered) == false:
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	# Per-frame solid-tile check: body_entered fires only once per TileMapLayer,
	# so a bolt entering a one-way platform then crossing into a solid tile would
	# otherwise slip through. One-way polygons are skipped (see is_solid_tile_at).
	for body in get_overlapping_bodies():
		if body is TileMapLayer and is_solid_tile_at(body, global_position):
			queue_free()
			return


## Launch in facing direction (dir = +1 right / -1 left).
func launch(dir: int) -> void:
	velocity = Vector2(signi(dir) * speed, 0.0)


func _on_body_entered(body: Node) -> void:
	# TileMapLayer tiles are validated per-frame in _physics_process so one-way
	# platforms can be honored; skip them here to avoid double-processing.
	if body is TileMapLayer:
		return
	if body.has_method("take_damage"):
		body.take_damage(1)
		queue_free()
	elif not body.is_in_group("entity"):
		queue_free()
	# else: an entity without take_damage (e.g. an item) -> pass through


## Returns true if the tile covering `pos` in `tml` has at least one collision
## polygon that is NOT one-way. Empty cells and pure one-way tiles return false,
## so bolts pass through one-way platforms (jump-through floors) while still
## stopping on solid walls.
##
## NOTE: this project's tilesets use at most one collision polygon per tile per
## layer (polygon index 0 — see procedural_tileset.gd). Godot 4.7's TileData has
## no collision-polygon-count accessor, so we probe index 0 directly.
static func is_solid_tile_at(tml: TileMapLayer, pos: Vector2) -> bool:
	var ts: TileSet = tml.tile_set
	if ts == null:
		return false
	var physics_layers: int = ts.get_physics_layers_count()
	if physics_layers <= 0:
		return false
	var cell := tml.local_to_map(tml.to_local(pos))
	var td: TileData = tml.get_cell_tile_data(cell)
	if td == null:
		return false
	for layer in physics_layers:
		if td.get_collision_polygon_points(layer, 0).is_empty():
			continue
		if not td.is_collision_polygon_one_way(layer, 0):
			return true
	return false
