class_name Player
extends CharacterBody2D
## Player avatar. Run, jump (with coyote time + jump buffer), and a toggle pogo
## stick (auto-bounce on landing while active). Exposes add_score()/take_damage()
## for entities. Movement constants are @export for in-editor tuning.

signal score_changed(score: int)
signal health_changed(health: int)
signal died

@export var gravity: float = 980.0
@export var run_speed: float = 120.0
@export var jump_velocity: float = 300.0
@export var pogo_bounce: float = 380.0
@export var max_fall: float = 480.0
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10

var score: int = 0
var health: int = 3

var _pogo: bool = false
var _coyote: float = 0.0
var _buffer: float = 0.0


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * run_speed

	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else _coyote - delta

	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta

	# Normal jump (disabled while pogo is active).
	if _buffer > 0.0 and _coyote > 0.0 and not _pogo:
		velocity.y = -jump_velocity
		_buffer = 0.0
		_coyote = 0.0

	# Toggle pogo stick on P.
	if Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo

	# While pogo active, bounce automatically on each landing.
	if _pogo and on_floor:
		velocity.y = -pogo_bounce

	move_and_slide()


func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		died.emit()
