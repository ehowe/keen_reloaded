class_name Teleporter
extends Node2D
## Special entity valid in both LEVEL and OVERWORLD maps. Player stands near it
## and presses `interact` to teleport to a destination teleporter (same or
## different map). Directional: each teleporter has one destination; a two-way
## link is two teleporters pointing at each other.
##
## Visual sequence on interact (both sides animate one loop):
##   player hidden+frozen -> source anim plays once -> teleport (scene swap)
##   -> destination spawns -> player hidden+frozen -> dest anim plays once
##   -> player shown+unfrozen.
## GameManager.teleport always rebuilds the runtime scene, so same-map and
## cross-map follow the identical path.
##
## Idle: the static `Visual` (Sprite2D) shows; `AnimatedSprite2D` is hidden.
## Resolution (finding the destination tile) is GameManager's job — this node
## only carries the configured IDs and drives the animation.

signal teleport_requested(destination_level_id: String, destination_teleporter_id: String)
signal arrival_finished()

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the teleporter in each direction (3x3 zone)
const ANIM_NAME := "default"

enum _Phase { IDLE, DEPART, ARRIVE }

var type_id: String = ""
var teleporter_id: String = ""
var destination_level_id: String = ""
var destination_teleporter_id: String = ""

var _phase: int = _Phase.IDLE
var _nearby: bool = false
var _player: Node = null
var _proximity: Area2D
@onready var _visual: CanvasItem = get_node_or_null("Visual")
@onready var _anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, props: Dictionary) -> void:
	type_id = p_type_id
	teleporter_id = String(props.get("teleporter_id", ""))
	destination_level_id = String(props.get("destination_level_id", ""))
	destination_teleporter_id = String(props.get("destination_teleporter_id", ""))


func _ready() -> void:
	_build_proximity()
	# `Visual` + `AnimatedSprite2D` come from the scene. Build a fallback
	# ColorRect only when the scene provided none (e.g. bare Teleporter.new()).
	if _visual == null:
		_visual = _fallback_visual()
		add_child(_visual)
	if _anim != null:
		_anim.animation_finished.connect(_on_animation_finished)


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


func _fallback_visual() -> CanvasItem:
	var vis := ColorRect.new()
	vis.name = "Visual"
	vis.size = Vector2(TILE, TILE)
	vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
	vis.color = Color(0.9, 0.3, 0.9, 1)  # magenta placeholder
	return vis


func _process(_delta: float) -> void:
	attempt_teleport(Input.is_action_just_pressed("interact"))


## Returns true when the departure sequence starts: player nearby, interact
## pressed, both destination fields set, and not already animating. The
## `teleport_requested` signal emits AFTER the source animation finishes (see
## _on_animation_finished), not from this call. `interact_pressed` is a
## parameter so tests stay deterministic.
func attempt_teleport(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	if destination_level_id == "" or destination_teleporter_id == "":
		return false
	if _phase != _Phase.IDLE:
		return false
	_start_phase(_Phase.DEPART)
	return true


## Drive the arrival animation. Called by LevelRuntime after a scene rebuilt by
## GameManager.teleport, once the destination teleporter is spawned. Hides +
## freezes the player for the duration; arrival_finished emits on completion.
func play_arrival(player: Node) -> void:
	_player = player
	_start_phase(_Phase.ARRIVE)


## Undo a departure when the teleport could not resolve (dangling destination).
## Restores the static visual and un-hides/unfreezes the player so the game
## does not soft-lock. Called by LevelRuntime when GameManager.teleport fails.
func restore_after_failed_departure() -> void:
	_phase = _Phase.IDLE
	if _anim != null:
		_anim.visible = false
		_anim.stop()
	if _visual != null:
		_visual.visible = true
	if _player != null:
		_player.visible = true
		_player.set_process_mode(Node.PROCESS_MODE_INHERIT)


func _start_phase(phase: int) -> void:
	_phase = phase
	if _player != null:
		_player.visible = false
		_player.set_process_mode(Node.PROCESS_MODE_DISABLED)
	if _visual != null:
		_visual.visible = false
	if _anim != null:
		_anim.visible = true
		_anim.play(ANIM_NAME)
	else:
		# No animation node (e.g. bare test instance): resolve immediately.
		_on_animation_finished()


func _on_animation_finished() -> void:
	match _phase:
		_Phase.DEPART:
			_phase = _Phase.IDLE
			teleport_requested.emit(destination_level_id, destination_teleporter_id)
		_Phase.ARRIVE:
			_phase = _Phase.IDLE
			if _visual != null:
				_visual.visible = true
			if _anim != null:
				_anim.visible = false
			if _player != null:
				_player.visible = true
				_player.set_process_mode(Node.PROCESS_MODE_INHERIT)
			arrival_finished.emit()


func _on_body_entered(body: Node) -> void:
	# Only the player triggers proximity — tile collision bodies share layer 1
	# and would otherwise permanently set _nearby (causing every teleporter to
	# fire on the same interact press).
	if body != null and body.is_in_group("player"):
		_nearby = true
		_player = body


func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_nearby = false


# --- test seams ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v

func _set_player_for_test(p: Node) -> void:
	_player = p
