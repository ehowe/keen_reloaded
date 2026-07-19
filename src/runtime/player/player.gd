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
## Raygun/blaster inventory item. Find-to-own: granted by the keen1.raygun
## ammo pickup on first contact (see ammo_pickup.gd). Gates shooting — see
## shoot(). Persists across levels + save/load via the Inventory autoload
## (like keen1.pogo).
const BLASTER := ItemIDs.BLASTER
const LEVEL_SPRITES := ["Idle", "Walking", "Jumping", "Shooting"]
const POGO_SPRITES := ["PogoUpright", "PogoBounce"]
const OVERWORLD_SPRITES := ["OverworldUp", "OverworldDown", "OverworldLeft", "OverworldRight"]
const SHOOT_POSE_TIME := 0.12
const DEATH_LAUNCH_ANGLE_DEG := 60.0
## CollisionShape2D node names per mode. Only the active mode's shape is enabled;
## set_mode() toggles them so Keen collides against the right tileset geometry.
const COLLISION_LEVEL := "Level"
const COLLISION_OVERWORLD := "Overworld"

@export var gravity: float = 1763.0
@export var run_speed: float = 480.0
@export var overworld_speed: float = 320.0
@export var jump_velocity: float = 823.0
@export var leap_speed: float = 480.0
@export var air_accel: float = 3000.0
@export var pogo_bounce: float = 823.0
@export var pogo_bounce_max: float = 1211.0
@export var pogo_drag: float = 1200.0
@export var pogo_bounce_hold: float = 0.08
@export var max_fall: float = 1920.0
@export var coyote_time: float = 0.10
@export var jump_buffer: float = 0.10
@export var max_ammo: int = 5
@export var max_health: int = 1
@export var projectile_speed: float = 600.0
@export var jump_cut_gravity: float = 4045.0
## How fast a bounce impulse (from a yorp bump) decays back to 0. Higher = snappier.
@export var bounce_decay: float = 3000.0
@export var death_launch_speed: float = 800.0

var score: int = 0
var health: int = 1
var ammo: int = 0
## Per-level keycard counts. color (String) -> count (int). Auto-cleared: the
## Player node is freed + rebuilt on every level swap, so this Dictionary never
## crosses levels and never reaches save/load.
var keycards: Dictionary = {}

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
var _pogo_bounce_timer: float = 0.0


## First node in the "player" group on `tree`, or null when the tree is null or
## no player is present. Consolidates the get_first_node_in_group + null-tree
## guard duplicated across enemy AI. Returns Node; callers cast/duck-type.
static func find(tree: SceneTree) -> Node:
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")


func _ready() -> void:
	add_to_group("player")
	ammo = 0
	ammo_changed.emit(ammo)
	_apply_collision_for_mode()
	_align_sprite_feet()


## Locks player input and optionally forces horizontal movement (dir = -1/0/1).
## speed_scale multiplies run_speed while locked (e.g. 0.5 = half speed for exits).
func lock_input(dir: float = 0.0, speed_scale: float = 1.0) -> void:
	_input_locked = true
	_forced_dir = dir
	_speed_scale = speed_scale


## Switches the player between LEVEL (platformer) and OVERWORLD (top-down) rules.
## Enables only the matching CollisionShape2D and re-runs sprite alignment so the
## active sprite set is positioned against the active collision box.
func set_mode(m: int) -> void:
	_mode = m
	_apply_collision_for_mode()
	_align_sprite_feet()


## Enables only the current mode's CollisionShape2D and disables the other, so
## Keen collides with level geometry in LEVEL mode and overworld geometry in
## OVERWORLD mode. Called from _ready (default LEVEL) and set_mode.
func _apply_collision_for_mode() -> void:
	var level_active := (_mode == Mode.LEVEL)
	var lvl := get_node_or_null(COLLISION_LEVEL) as CollisionShape2D
	var ow := get_node_or_null(COLLISION_OVERWORLD) as CollisionShape2D
	if lvl != null:
		lvl.disabled = not level_active
	if ow != null:
		ow.disabled = level_active


## Deferred collision disable, safe to call from inside a physics query flush
## (e.g. Area2D body_entered -> take_damage -> _die). No-op if the node is absent.
func _set_collision_disabled_deferred(node_name: String, disabled: bool) -> void:
	var col := get_node_or_null(node_name) as CollisionShape2D
	if col != null:
		col.set_deferred("disabled", disabled)


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
	elif _pogo:
		# Pogo: air control via steer + momentum preservation across bounces.
		# Forward motion continues at the same speed on landing (no friction).
		if dir != 0.0:
			var target := dir * run_speed
			if on_floor:
				velocity.x = target
			else:
				velocity.x = move_toward(velocity.x, target, air_accel * delta)
			_facing = signi(dir)
		elif not on_floor:
			# Air drag: gradual deceleration when no input (smoother feel)
			velocity.x = move_toward(velocity.x, 0.0, pogo_drag * delta)
		# else (on_floor, no input): preserve momentum for the bounce
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
		AudioManager.play_sfx("jump")

	if _windup > 0.0:
		_windup -= delta
		if _windup <= 0.0:
			velocity.y = -jump_velocity
			velocity.x = _jump_dir * leap_speed
			_jumping = true

	if not _input_locked and Inventory.has_item(ItemIDs.POGO) and Input.is_action_just_pressed("pogo"):
		_pogo = not _pogo
		_pogo_bounce_timer = 0.0

	if _pogo and on_floor and _windup <= 0.0:
		velocity.y = -pogo_bounce_max if Input.is_action_pressed("jump") else -pogo_bounce
		AudioManager.play_sfx("pogo")

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
	if _pogo and is_on_floor():
		_pogo_bounce_timer = pogo_bounce_hold
	elif _pogo_bounce_timer > 0.0:
		_pogo_bounce_timer = maxf(_pogo_bounce_timer - delta, 0.0)
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


## Fire a projectile from the Muzzle in the facing direction. Requires the
## blaster (find-to-own inventory item) and at least one shot of ammo. Mirrors the
## post-fire ammo back to GameManager so the stash persists across levels.
func shoot() -> void:
	if not Inventory.has_item(BLASTER):
		return
	if ammo <= 0:
		return
	AudioManager.play_sfx("shoot")
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
	_set_ammo(ammo - 1)


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


## Apply a new ammo total: update the runtime field, write through to the
## persistent store, and notify listeners. Centralizes the invariant that
## every ammo change keeps GameManager.ammo and the HUD in sync.
func _set_ammo(value: int) -> void:
	ammo = value
	GameManager.ammo = ammo
	ammo_changed.emit(ammo)


func add_ammo(amount: int) -> void:
	_set_ammo(clampi(ammo + amount, 0, max_ammo))


## True if the player holds at least one keycard of `color`.
func has_keycard(color: String) -> bool:
	return int(keycards.get(color, 0)) > 0


## Grant one keycard of `color`. Adds to the existing count if any.
func add_keycard(color: String) -> void:
	keycards[color] = int(keycards.get(color, 0)) + 1


## Decrement the `color` count by 1 (floors at 0). Returns true if a keycard
## was actually consumed (player had at least one); false if the player had none.
func consume_keycard(color: String) -> bool:
	if not has_keycard(color):
		return false
	keycards[color] = int(keycards[color]) - 1
	return true


## Apply a horizontal bounce impulse (e.g. from a yorp bump). Overrides Keen's
## horizontal input while active, decaying to 0 so he slides back smoothly.
func apply_bounce(vx: float) -> void:
	_bounce_vx = vx


## Any damage is lethal (classic Keen 1 behavior: Keen has 1 HP). The amount
## is ignored — every call routes through _die() with the up-left launch.
func take_damage(_amount: int) -> void:
	if _dead:
		return
	health = 0
	health_changed.emit(health)
	AudioManager.play_sfx("hurt")
	_die()


func _die() -> void:
	if _dead:
		return
	_dead = true
	AudioManager.play_sfx("die")
	_input_locked = true
	# Defer: _die() may fire from an Area2D body_entered callback (e.g. the
	# Clapper) during the physics query flush, where a direct set is rejected
	# and the shape stays enabled — leaving Keen colliding during death-flight.
	# Disable both mode shapes so the death-flight ignores all tile geometry.
	_set_collision_disabled_deferred(COLLISION_LEVEL, true)
	_set_collision_disabled_deferred(COLLISION_OVERWORLD, true)
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
	_hide_pogo_sprites()
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


func _hide_pogo_sprites() -> void:
	for name in POGO_SPRITES:
		var n := get_node_or_null(name) as Sprite2D
		if n != null:
			n.visible = false


func _sync_visual_level() -> void:
	_hide_sprites(OVERWORLD_SPRITES)
	var on_floor := is_on_floor()
	if _pogo and _shoot_timer <= 0.0:
		# Pogo: static Sprite2D selection. PogoBounce shows on landing (timer-based
		# hold for ~5 frames around ground contact), PogoUpright all other times.
		_hide_sprites(LEVEL_SPRITES)
		var show_bounce := _pogo_bounce_timer > 0.0
		var upright := get_node_or_null("PogoUpright") as Sprite2D
		var bounce := get_node_or_null("PogoBounce") as Sprite2D
		if upright != null:
			upright.visible = not show_bounce
			upright.flip_h = _facing < 0
		if bounce != null:
			bounce.visible = show_bounce
			bounce.flip_h = _facing < 0
		_anim = ""  # force anim restart when leaving pogo
		return
	# Non-pogo: hide pogo sprites, normal animated-sprite logic
	_hide_pogo_sprites()
	var anim := _current_anim(on_floor, absf(velocity.x) > 1.0, _pogo, _shoot_timer > 0.0, _windup > 0.0)
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
	_hide_pogo_sprites()
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
	var col_name := COLLISION_OVERWORLD if _mode == Mode.OVERWORLD else COLLISION_LEVEL
	var col := get_node_or_null(col_name) as CollisionShape2D
	if col == null or not (col.shape is RectangleShape2D):
		return
	var foot_y := (col.shape as RectangleShape2D).size.y * 0.5
	var sprites := OVERWORLD_SPRITES if _mode == Mode.OVERWORLD else LEVEL_SPRITES
	for name in sprites:
		var n := get_node_or_null(name) as AnimatedSprite2D
		if n == null:
			continue
		var h := SpriteUtil.frame_height(n)
		if h > 0.0:
			n.offset.y = SpriteUtil.foot_offset_y(h, foot_y)
	var death := get_node_or_null("Death") as AnimatedSprite2D
	if death != null:
		var dh := SpriteUtil.frame_height(death)
		if dh > 0.0:
			death.offset.y = SpriteUtil.foot_offset_y(dh, foot_y)
	for name in POGO_SPRITES:
		var ps := get_node_or_null(name) as Sprite2D
		if ps == null or ps.texture == null:
			continue
		var ph: float = ps.texture.get_height()
		if ph > 0.0:
			ps.offset.y = SpriteUtil.foot_offset_y(ph, foot_y)
