class_name Ship
extends Node2D
## Overworld-only entity: Commander Keen's crashed ship. Player presses
## `interact` while nearby to request a ship-parts progress readout. Emits
## `progress_requested` (LevelRuntime wires it to a UI overlay once authored).
##
## Placeholder: REQUIRED_PARTS lists the classic Keen 1 ship parts; collected
## state is held session-only via collect_part() until a real inventory lands.

signal progress_requested(collected: int, total: int, required_parts: Array)

const TILE := 64
const PROXIMITY_RADIUS := 1  # tiles around the ship in each direction (3x3 zone)

const REQUIRED_PARTS := [
	"Battery",
	"Joystick",
	"Vacuum Cleaner",
	"Whisky Bottle (Fuel)",
]

var type_id: String = ""

var _nearby: bool = false
var _proximity: Area2D
var _collected: Dictionary = {}  # part name -> true


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, _props: Dictionary) -> void:
	type_id = p_type_id


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


func _process(_delta: float) -> void:
	attempt_show_progress(Input.is_action_just_pressed("interact"))


## Returns true and emits progress_requested when a player is nearby and the
## interact control is pressed. `interact_pressed` is a parameter (not read from
## Input) so tests are deterministic.
func attempt_show_progress(interact_pressed: bool) -> bool:
	if not _nearby or not interact_pressed:
		return false
	progress_requested.emit(collected_count(), REQUIRED_PARTS.size(), REQUIRED_PARTS)
	return true


func collected_count() -> int:
	return _collected.size()


func total_count() -> int:
	return REQUIRED_PARTS.size()


func is_part_collected(part_name: String) -> bool:
	return _collected.has(part_name)


## Placeholder seam for a future inventory system: mark a part as collected.
## Ignored if the name is not in REQUIRED_PARTS.
func collect_part(part_name: String) -> void:
	if String(part_name) == "" or not REQUIRED_PARTS.has(part_name):
		return
	_collected[part_name] = true


func _on_body_entered(_body: Node) -> void:
	_nearby = true


func _on_body_exited(_body: Node) -> void:
	_nearby = false


# --- test seam ---
func _set_nearby_for_test(v: bool) -> void:
	_nearby = v
