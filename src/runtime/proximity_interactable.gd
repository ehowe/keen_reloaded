class_name ProximityInteractable
extends Node2D
## Base for overworld entities the player uses by standing near + pressing
## `interact` (Ship, Teleporter, LevelEntrance). Owns the shared 3x3-tile
## player-proximity Area2D: the nearby flag, the player-group enter/exit filter,
## and the test seam. Extracted from byte-identical copies that lived in each
## subclass.
##
## Subclasses override `_on_player_entered/_exited` to capture the player node
## (e.g. Teleporter freezes it during the anim) and keep their own descriptive
## `attempt_*` method + 1-line `_process` that reads `interact` and calls it.

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the entity in each direction (3x3 zone)

var _nearby: bool = false
var _proximity: Area2D


func _ready() -> void:
	_build_proximity()


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


func _on_body_entered(body: Node) -> void:
	# Only the player triggers proximity — tile collision bodies share layer 1
	# and would otherwise permanently set _nearby.
	if body != null and body.is_in_group("player"):
		_nearby = true
		_on_player_entered(body)


func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_nearby = false
		_on_player_exited(body)


## Override to capture the player on entry (e.g. Teleporter stores it so the
## departure/arrival anim can freeze + restore it).
func _on_player_entered(_player: Node) -> void:
	pass


## Override to release the player reference on exit.
func _on_player_exited(_player: Node) -> void:
	pass


# --- test seam ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v
