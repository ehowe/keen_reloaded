class_name Teleporter
extends Node2D
## Special entity valid in both LEVEL and OVERWORLD maps. Player stands near it
## and presses `interact` to request a teleport to a destination teleporter,
## which may live in this map or a different one. Emits `teleport_requested`;
## LevelRuntime wires it to GameManager.teleport().
##
## Directional: each teleporter has exactly one destination. A two-way link is
## two teleporters pointing at each other. Resolution (finding the destination
## tile) is GameManager's job — this node only carries the configured IDs.

signal teleport_requested(destination_level_id: String, destination_teleporter_id: String)

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the teleporter in each direction (3x3 zone)

var type_id: String = ""
var teleporter_id: String = ""
var destination_level_id: String = ""
var destination_teleporter_id: String = ""

var _nearby: bool = false
var _proximity: Area2D


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, props: Dictionary) -> void:
	type_id = p_type_id
	teleporter_id = String(props.get("teleporter_id", ""))
	destination_level_id = String(props.get("destination_level_id", ""))
	destination_teleporter_id = String(props.get("destination_teleporter_id", ""))


func _ready() -> void:
	_build_proximity()
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


func _build_visual() -> void:
	if has_node("Visual"):
		return
	var vis := ColorRect.new()
	vis.name = "Visual"
	vis.size = Vector2(TILE, TILE)
	vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	vis.color = Color(0.9, 0.3, 0.9, 1)  # magenta placeholder
	add_child(vis)


func _process(_delta: float) -> void:
	attempt_teleport(Input.is_action_just_pressed("interact"))


## Returns true and emits teleport_requested when a player is nearby, the
## interact control is pressed, and both destination fields are set.
## `interact_pressed` is a parameter (not read from Input) so tests are
## deterministic.
func attempt_teleport(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	if destination_level_id == "" or destination_teleporter_id == "":
		return false
	teleport_requested.emit(destination_level_id, destination_teleporter_id)
	return true


func _on_body_entered(_body: Node) -> void:
	_nearby = true


func _on_body_exited(_body: Node) -> void:
	_nearby = false


# --- test seam ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v
