class_name LevelEntrance
extends Node2D
## Overworld-only entity: a level door. Player presses `interact` while nearby to
## enter the linked level. When `blocks_until_completed` is set and the target
## level is not yet completed, a solid StaticBody2D blocks overworld passage.
##
## Does NOT own completion state — reads GameManager.is_level_completed(). Emits
## `enter_requested(target_level_id, tile)`; LevelRuntime wires it to
## GameManager.enter_level().

signal enter_requested(target_level_id: String, tile: Vector2i)

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the door in each direction (3x3 zone)

var type_id: String = ""
var target_level_id: String = ""
var blocks_until_completed: bool = false
var tile: Vector2i = Vector2i(-1, -1)

var _nearby: bool = false
var _proximity: Area2D
var _blocker: StaticBody2D
var _blocker_shape: CollisionShape2D


## Called by EntityRegistry.instantiate. Reads editor-set properties. Order-
## independent: refresh_blocking() reapplies solidity whether or not _ready has
## run yet (it null-guards the shape).
func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	target_level_id = String(p_props.get("target_level_id", ""))
	blocks_until_completed = bool(p_props.get("blocks_until_completed", false))
	refresh_blocking()


## Called by LevelRuntime after instantiate so the entrance knows its tile.
func set_tile(t: Vector2i) -> void:
	tile = t


func _ready() -> void:
	_build_proximity()
	_build_blocker()
	_build_visual()


func _build_proximity() -> void:
	_proximity = Area2D.new()
	_proximity.name = "Proximity"
	_proximity.monitoring = true
	_proximity.collision_layer = 0
	_proximity.collision_mask = 1  # player bit
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var zone := float(TILE * (1 + PROXIMITY_RADIUS * 2))
	rect.size = Vector2(zone, zone)
	shape.shape = rect
	_proximity.add_child(shape)
	_proximity.body_entered.connect(_on_body_entered)
	_proximity.body_exited.connect(_on_body_exited)
	add_child(_proximity)


func _build_blocker() -> void:
	_blocker = StaticBody2D.new()
	_blocker.name = "Blocker"
	_blocker.collision_layer = 4  # tiles bit -> blocks the player
	_blocker_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	_blocker_shape.shape = rect
	_blocker.add_child(_blocker_shape)
	_blocker.add_to_group("level_entrance_blocker")
	add_child(_blocker)
	_apply_blocking()


func _build_visual() -> void:
	if has_node("Visual"):
		return
	var vis := ColorRect.new()
	vis.name = "Visual"
	vis.size = Vector2(TILE, TILE)
	vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	vis.color = Color(0.95, 0.75, 0.2, 1)
	add_child(vis)


func _process(_delta: float) -> void:
	attempt_enter(Input.is_action_just_pressed("interact"))


## Returns true and emits enter_requested when a player is nearby and the
## interact control is pressed. `interact_pressed` is a parameter (not read from
## Input) so tests are deterministic.
func attempt_enter(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	if target_level_id == "":
		return false
	enter_requested.emit(target_level_id, tile)
	return true


func is_blocking() -> bool:
	return blocks_until_completed and target_level_id != "" and not GameManager.is_level_completed(target_level_id)


## Recompute the blocker's solidity from GameManager state. Called on build and
## after a level is completed.
func refresh_blocking() -> void:
	_apply_blocking()


func _apply_blocking() -> void:
	if _blocker_shape == null:
		return
	_blocker_shape.set_deferred("disabled", not is_blocking())


func _on_body_entered(_body: Node) -> void:
	_nearby = true


func _on_body_exited(_body: Node) -> void:
	_nearby = false


# --- test seam ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v
