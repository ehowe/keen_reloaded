class_name Projectile
extends Area2D
## Raygun bolt. Linear motion in the launch direction; despawns on lifetime
## expiry, on hitting an enemy (deals 1 damage), or on hitting a wall/solid tile.
## Passes through items (entities without take_damage) and one-way platforms
## (jump-through floors): one-way tile polygons are treated as non-blocking.
##
## Two visual/physics variants share this scene: the player's raygun bolt
## (Variant.PLAYER — "Player" sprite, masks enemies+tiles) and the Tank Robot's
## enemy blaster bolt (Variant.TANK_ROBOT — "Tank Robot" sprite, masks
## player+tiles). Set `variant` BEFORE adding the node to the tree so _ready
## picks the right sprite + collision mask.

enum Variant { PLAYER, TANK_ROBOT }

const _MASK_PLAYER_BOLT := 6   # enemies (2) + tiles (4)
const _MASK_ENEMY_BOLT := 5    # player (1) + tiles (4)

@export var speed: float = 600.0
@export var lifetime: float = 2.0
@export var variant: Variant = Variant.PLAYER

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Show the sprite matching the variant; hide the other so a single scene
	# serves both player and Tank Robot blasters.
	var want := "Player" if variant == Variant.PLAYER else "Tank Robot"
	for n in ["Player", "Tank Robot"]:
		var s := get_node_or_null(n) as Sprite2D
		if s != null:
			s.visible = (n == want)
	# Enemy bolts target the player; player bolts target enemies. Both still
	# collide with solid tiles so they despawn on walls.
	collision_mask = _MASK_ENEMY_BOLT if variant == Variant.TANK_ROBOT else _MASK_PLAYER_BOLT
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


## Launch in facing direction (dir = +1 right / -1 left). Flips the visible
## blaster sprite so the bolt art points the way it travels.
func launch(dir: int) -> void:
	var d := signi(dir)
	velocity = Vector2(d * speed, 0.0)
	var want := "Player" if variant == Variant.PLAYER else "Tank Robot"
	var s := get_node_or_null(want) as Sprite2D
	if s != null:
		s.flip_h = d < 0


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
