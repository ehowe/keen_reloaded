class_name Player
extends CharacterBody2D
## Player avatar. Run, jump (coyote + buffer), toggle pogo, and shoot the raygun
## (ammo-limited) in the facing direction. Exposes add_score()/add_ammo()/
## take_damage() for entities. Movement constants are @export for tuning.

signal score_changed(score: int)
signal health_changed(health: int)
signal ammo_changed(ammo: int)
signal died

const PROJECTILE := preload("res://src/runtime/player/projectile.tscn")

@export var gravity: float = 3920.0
@export var run_speed: float = 480.0
@export var jump_velocity: float = 1200.0
@export var pogo_bounce: float = 1520.0
@export var max_fall: float = 1920.0
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10
@export var max_ammo: int = 5
@export var projectile_speed: float = 600.0

var score: int = 0
var health: int = 3
var ammo: int = 0

var _facing: int = 1
var _pogo: bool = false
var _coyote: float = 0.0
var _buffer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	ammo = 0
	ammo_changed.emit(ammo)


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * run_speed
	if dir != 0:
		_facing = signi(dir)

	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else _coyote - delta

	if Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta

	if _buffer > 0.0 and _coyote > 0.0 and not _pogo:
		velocity.y = -jump_velocity
		_buffer = 0.0
		_coyote = 0.0

	if Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo

	if _pogo and on_floor:
		velocity.y = -pogo_bounce

	if Input.is_action_just_pressed("shoot"):
		shoot()

	move_and_slide()


## Fire a projectile from the Muzzle in the facing direction (if ammo remains).
func shoot() -> void:
	if ammo <= 0:
		return
	var muzzle := get_node_or_null("Muzzle") as Marker2D
	var origin: Vector2 = global_position
	if muzzle != null:
		origin = to_global(Vector2(muzzle.position.x * _facing, muzzle.position.y))
	var proj: Projectile = PROJECTILE.instantiate()
	var host: Node = get_parent() if get_parent() != null else get_tree().current_scene
	host.add_child(proj)
	proj.global_position = origin
	proj.speed = projectile_speed
	proj.launch(_facing)
	ammo -= 1
	ammo_changed.emit(ammo)


func set_camera_bounds(rect: Rect2) -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = int(rect.position.x)
	cam.limit_top = int(rect.position.y)
	cam.limit_right = int(rect.end.x)
	cam.limit_bottom = int(rect.end.y)


func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)


func add_ammo(amount: int) -> void:
	ammo = clampi(ammo + amount, 0, max_ammo)
	ammo_changed.emit(ammo)


func take_damage(amount: int) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		died.emit()
