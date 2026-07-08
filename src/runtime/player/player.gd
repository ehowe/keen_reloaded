class_name Player
extends CharacterBody2D
## Player avatar. Two modes selected via set_mode():
##   - LEVEL (default): run, jump (coyote + buffer), toggle pogo, shoot the
##     raygun (ammo-limited) in the facing direction.
##   - OVERWORLD: top-down 4-directional walk (WASD), no gravity/jump/pogo/shoot,
##     drives the OverworldUp/Down/Left/Right sprites.
## Exposes add_score()/add_ammo()/take_damage() for entities.
## Movement constants are @export for tuning.

enum Mode { LEVEL, OVERWORLD }
enum Direction { UP, DOWN, LEFT, RIGHT }

signal score_changed(score: int)
signal health_changed(health: int)
signal ammo_changed(ammo: int)
signal died

const PROJECTILE := preload("res://src/runtime/player/projectile.tscn")
const LEVEL_SPRITES := ["Idle", "Walking", "Jumping", "Shooting", "Pogo"]
const OVERWORLD_SPRITES := ["OverworldUp", "OverworldDown", "OverworldLeft", "OverworldRight"]
const SHOOT_POSE_TIME := 0.12
const DEATH_LAUNCH_ANGLE_DEG := 60.0

@export var gravity: float = 1763.0
@export var run_speed: float = 480.0
@export var overworld_speed: float = 320.0
@export var jump_velocity: float = 823.0
@export var leap_speed: float = 480.0
@export var air_accel: float = 3000.0
@export var pogo_bounce: float = 1019.0
@export var max_fall: float = 1920.0
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10
@export var max_ammo: int = 5
@export var projectile_speed: float = 600.0
@export var jump_cut_gravity: float = 4045.0
## How fast a bounce impulse (from a yorp bump) decays back to 0. Higher = snappier.
@export var bounce_decay: float = 3000.0
@export var death_launch_speed: float = 800.0

var score: int = 0
var health: int = 3
var ammo: int = 0

var _facing: int = 1
var _pogo: bool = false
var _coyote: float = 0.0
var _buffer: float = 0.0
var _shoot_timer: float = 0.0
var _windup: float = 0.0
var _jumping: bool = false
var _jump_dir: float = 0.0
var _anim: String = ""
var _input_locked: bool = false
var _forced_dir: float = 0.0
var _speed_scale: float = 1.0
var _mode: int = Mode.LEVEL
var _overworld_dir: int = Direction.DOWN
var _bounce_vx: float = 0.0  # active bounce impulse; overrides horizontal input while nonzero
var _dead: bool = false


func _ready() -> void:
	add_to_group("player")
	ammo = 0
	ammo_changed.emit(ammo)
	_align_sprite_feet()


## Locks player input and optionally forces horizontal movement (dir = -1/0/1).
## speed_scale multiplies run_speed while locked (e.g. 0.5 = half speed for exits).
func lock_input(dir: float = 0.0, speed_scale: float = 1.0) -> void:
	_input_locked = true
	_forced_dir = dir
	_speed_scale = speed_scale


## Switches the player between LEVEL (platformer) and OVERWORLD (top-down) rules.
## Re-runs sprite alignment so the active sprite set is positioned correctly.
func set_mode(m: int) -> void:
	_mode = m
	_align_sprite_feet()


func _physics_process(delta: float) -> void:
	if _dead:
		move_and_slide()
		_sync_visual()
		return
	if _mode == Mode.OVERWORLD:
		_physics_overworld(delta)
		return
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall

	var on_floor := is_on_floor()
	var dir := _forced_dir if _input_locked else Input.get_axis("move_left", "move_right")
	if _windup > 0.0:
		# wind-up: halt horizontal; direction locked at jump press for launch
		velocity.x = 0.0
	elif on_floor:
		velocity.x = dir * run_speed * (_speed_scale if _input_locked else 1.0)
		if dir != 0:
			_facing = signi(dir)
	elif _jumping and _jump_dir != 0.0 and dir != 0.0:
		# moving jump: slow air steer toward input; releasing input preserves momentum
		velocity.x = move_toward(velocity.x, dir * leap_speed, air_accel * delta)
		_facing = signi(dir)
	# else: stationary jump or fall — preserve horizontal momentum + facing.

	_coyote = coyote_time if on_floor else _coyote - delta

	if not _input_locked and Input.is_action_just_pressed("jump"):
		_buffer = jump_buffer
	else:
		_buffer -= delta

	# Begin a grounded jump wind-up: play the Jump anim once, launch when it ends.
	if _buffer > 0.0 and _coyote > 0.0 and not _pogo and _windup <= 0.0:
		_windup = _jump_anim_duration()
		_jump_dir = sign(dir)
		_buffer = 0.0
		_coyote = 0.0

	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			velocity.y = -jump_velocity
			velocity.x = _jump_dir * leap_speed
			_jumping = true

	if not _input_locked and Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo

	if _pogo and on_floor and _windup <= 0.0:
		velocity.y = -pogo_bounce

	if not _input_locked and Input.is_action_just_pressed("shoot"):
		shoot()

	if _jumping and velocity.y < 0.0 and not Input.is_action_pressed("jump"):
		velocity.y += jump_cut_gravity * delta

	# Bounce impulse (e.g. yorp bump): overrides horizontal velocity and eases to
	# 0, animating Keen backward instead of teleporting him.
	if _bounce_vx != 0.0:
		velocity.x = _bounce_vx
		_bounce_vx = move_toward(_bounce_vx, 0.0, bounce_decay * delta)

	move_and_slide()
	if is_on_floor():
		_jumping = false
	_shoot_timer = maxf(_shoot_timer - delta, 0.0)
	_sync_visual()


## Top-down 4-directional movement for OVERWORLD maps. No gravity, no jump/pogo/shoot.
func _physics_overworld(delta: float) -> void:
	var input_vec: Vector2
	if _input_locked:
		input_vec = Vector2(_forced_dir, 0.0)
	else:
		input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vec * overworld_speed
	if input_vec != Vector2.ZERO:
		# Pick dominant axis. Ties go horizontal to match original Keen feel.
		if absf(input_vec.x) >= absf(input_vec.y):
			_overworld_dir = Direction.RIGHT if input_vec.x > 0.0 else Direction.LEFT
		else:
			_overworld_dir = Direction.DOWN if input_vec.y > 0.0 else Direction.UP
	move_and_slide()
	_sync_visual()


## Fire a projectile from the Muzzle in the facing direction (if ammo remains).
func shoot() -> void:
	if ammo <= 0:
		return
	_shoot_timer = SHOOT_POSE_TIME
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


## Apply a horizontal bounce impulse (e.g. from a yorp bump). Overrides Keen's
## horizontal input while active, decaying to 0 so he slides back smoothly.
func apply_bounce(vx: float) -> void:
	_bounce_vx = vx


func take_damage(amount: int) -> void:
	if _dead:
		return
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	_input_locked = true
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col != null:
		# Defer: _die() may fire from an Area2D body_entered callback (e.g. the
		# Clapper) during the physics query flush, where a direct set is rejected
		# and the shape stays enabled — leaving Keen colliding during death-flight.
		col.set_deferred("disabled", true)
	var rad := deg_to_rad(DEATH_LAUNCH_ANGLE_DEG)
	velocity = Vector2(-cos(rad), -sin(rad)) * death_launch_speed
	died.emit()


func _sync_visual() -> void:
	if _dead:
		_sync_visual_death()
		return
	if _mode == Mode.OVERWORLD:
		_sync_visual_overworld()
		return
	_sync_visual_level()


func _sync_visual_death() -> void:
	_hide_sprites(LEVEL_SPRITES)
	_hide_sprites(OVERWORLD_SPRITES)
	var d := get_node_or_null("Death") as AnimatedSprite2D
	if d == null:
		return
	d.visible = true
	if not d.is_playing():
		d.play()


## Hides (and stops) every sprite in `names`. Used by each mode's sync to keep
## the inactive sprite set from leaking through the active display.
func _hide_sprites(names: Array) -> void:
	for name in names:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		n.visible = false
		if n.is_playing():
			n.stop()


func _sync_visual_level() -> void:
	_hide_sprites(OVERWORLD_SPRITES)
	var anim := _current_anim(is_on_floor(), absf(velocity.x) > 1.0, _pogo, _shoot_timer > 0.0, _windup > 0.0)
	for name in LEVEL_SPRITES:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var show: bool = (name == anim)
		n.visible = show
		n.flip_h = _facing < 0
		if not show and n.is_playing():
			n.stop()
	if anim != _anim:
		_anim = anim
		var nn := get_node_or_null(anim) as AnimatedSprite2D
		if nn != null and nn.sprite_frames != null:
			nn.stop()
			nn.play()


func _overworld_anim_name() -> String:
	match _overworld_dir:
		Direction.UP:
			return "OverworldUp"
		Direction.DOWN:
			return "OverworldDown"
		Direction.LEFT:
			return "OverworldLeft"
		Direction.RIGHT:
			return "OverworldRight"
	return "OverworldDown"


func _sync_visual_overworld() -> void:
	_hide_sprites(LEVEL_SPRITES)
	var picked := _overworld_anim_name()
	var moving := velocity.length() > 1.0
	for name in OVERWORLD_SPRITES:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var show: bool = (name == picked)
		n.visible = show
		n.flip_h = false
		if not show and n.is_playing():
			n.stop()
	var picked_node := get_node_or_null(picked) as AnimatedSprite2D
	if picked_node == null or picked_node.sprite_frames == null:
		return
	if moving:
		if not picked_node.is_playing():
			picked_node.play()
	else:
		if picked_node.is_playing():
			picked_node.stop()
		picked_node.frame = 0


func _current_anim(on_floor: bool, moving: bool, pogo: bool, shooting: bool, winding_up: bool) -> String:
	if shooting:
		return "Shooting"
	if pogo:
		return "Pogo"
	if winding_up or not on_floor:
		return "Jumping"
	return "Walking" if moving else "Idle"


func _jump_anim_duration() -> float:
	var j := get_node_or_null("Jumping") as AnimatedSprite2D
	if j == null or j.sprite_frames == null:
		return 0.0
	var anims := j.sprite_frames.get_animation_names()
	if anims.is_empty():
		return 0.0
	var speed := j.sprite_frames.get_animation_speed(anims[0])
	if speed <= 0.0:
		return 0.0
	return float(j.sprite_frames.get_frame_count(anims[0])) / speed


func _align_sprite_feet() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null or not (col.shape is RectangleShape2D):
		return
	var foot_y := (col.shape as RectangleShape2D).size.y * 0.5
	var sprites := OVERWORLD_SPRITES if _mode == Mode.OVERWORLD else LEVEL_SPRITES
	for name in sprites:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var h := _frame_height(n)
		if h > 0.0:
			n.offset.y = -(h * 0.5 - foot_y)
	var death := get_node_or_null("Death") as AnimatedSprite2D
	if death != null:
		var dh := _frame_height(death)
		if dh > 0.0:
			death.offset.y = -(dh * 0.5 - foot_y)


static func _frame_height(spr: AnimatedSprite2D) -> float:
	if spr.sprite_frames == null:
		return 0.0
	var anims := spr.sprite_frames.get_animation_names()
	if anims.is_empty():
		return 0.0
	var tex := spr.sprite_frames.get_frame_texture(anims[0], 0)
	if tex is AtlasTexture:
		return (tex as AtlasTexture).region.size.y
	return float(tex.get_height())
