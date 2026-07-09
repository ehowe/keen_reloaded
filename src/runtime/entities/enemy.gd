class_name Enemy
extends Entity
## Physics-enabled enemy base. Applies gravity + patrol movement, turns at walls
## and (optionally) ledges, deals contact damage, and awards score_value to the
## player on death. Concrete enemies (Vorticon/Yorp/Butler) extend this and tune
## knobs or override _ai_tick() / _handle_player() / take_damage().

@export var gravity: float = 3920.0
@export var patrol_speed: float = 120.0
@export var max_fall: float = 1920.0
@export var turns_at_walls: bool = true
@export var turns_at_ledges: bool = true
@export var walk_time: float = 2.5
@export var idle_time: float = 1.2
@export var stun_duration: float = 4.0
@export var stomp_bounce: float = 520.0
@export var knockback_x: float = 400.0
@export var knockback_y: float = 300.0

enum State { WALK, IDLE, STUNNED, SHOT }

const SPRITE_NAMES := {
	State.WALK: "Walking",
	State.IDLE: "Idle",
	State.STUNNED: "Stunned",
	State.SHOT: "Shot",
}

var health: int = 1
var contact_damage: int = 1
var score_value: int = 100

var _dir: int = -1  # patrol facing: -1 left, +1 right
var _state: State = State.WALK
var _phase_timer: float = 0.0
var _stunned: bool = false
var _stun_timer: float = 0.0
var _dying: bool = false
var _dead: bool = false
var _leave_corpse: bool = false
var _sprites: Dictionary = {}


func _ready() -> void:
	super._ready()
	collision_layer = 2  # enemies
	collision_mask = 4   # tiles (gravity/patrol collide with floor)
	if not has_node("BodyShape"):
		var s := CollisionShape2D.new()
		s.name = "BodyShape"
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE * 0.8, TILE * 0.9)
		s.shape = rect
		add_child(s)
	if not has_node("LedgeProbe"):
		var rc := RayCast2D.new()
		rc.name = "LedgeProbe"
		rc.enabled = true
		rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
		add_child(rc)
	_cache_sprites()
	_phase_timer = walk_time


func _cache_sprites() -> void:
	_sprites.clear()
	for state in SPRITE_NAMES:
		var n := get_node_or_null(SPRITE_NAMES[state]) as AnimatedSprite2D
		if n != null:
			_sprites[SPRITE_NAMES[state]] = n
			n.stop()
	if _sprites.size() > 0 and has_node("Visual"):
		get_node("Visual").free()  # immediate: placeholder must not flash for a frame
	_align_sprite_feet()


func _align_sprite_feet() -> void:
	# Sprite art may be taller than the (sub-tile) collision box; offset each
	# sprite up so its bottom aligns with the collision (foot) bottom, i.e. the
	# tile floor, instead of sinking through it.
	var body := get_node_or_null("BodyShape") as CollisionShape2D
	if body == null or not (body.shape is RectangleShape2D):
		return
	var foot_y := (body.shape as RectangleShape2D).size.y * 0.5
	for name in _sprites:
		var spr: AnimatedSprite2D = _sprites[name]
		var h := _frame_height(spr)
		if h > 0.0:
			spr.offset.y = -(h * 0.5 - foot_y)


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


func _sync_visual() -> void:
	var active: String = SPRITE_NAMES.get(_state, "")
	for name in _sprites:
		var n: AnimatedSprite2D = _sprites[name]
		var show: bool = (name == active)
		n.visible = show
		n.flip_h = _dir < 0
		if show:
			if _state != State.SHOT and not n.is_playing() and n.sprite_frames != null:
				n.play()
		elif n.is_playing():
			n.stop()


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall
	if _dying:
		velocity.x = 0.0
	elif _stunned:
		velocity.x = 0.0
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_stunned = false
			_on_recover()
	else:
		_tick_wander(delta)
		_ai_tick(delta)
	move_and_slide()
	_sync_visual()


func _tick_wander(delta: float) -> void:
	_phase_timer -= delta
	match _state:
		State.WALK:
			_turn_if_blocked()
			velocity.x = _dir * patrol_speed
			if _phase_timer <= 0.0:
				_state = State.IDLE
				velocity.x = 0.0
				_phase_timer = _idle_phase_time()
		State.IDLE:
			velocity.x = 0.0
			if _phase_timer <= 0.0:
				_dir = _choose_walk_dir()
				_state = State.WALK
				_phase_timer = _walk_phase_time()


## Facing picked when starting a WALK phase. Base: reverse (classic patrol).
func _choose_walk_dir() -> int:
	return -_dir


## Duration of the next WALK phase. Base: fixed walk_time.
func _walk_phase_time() -> float:
	return walk_time


## Duration of the next IDLE phase. Base: fixed idle_time.
func _idle_phase_time() -> float:
	return idle_time


func _turn_if_blocked() -> void:
	if turns_at_walls and is_on_wall() and _pressing_into_wall(_dir, get_wall_normal().x):
		_dir = -_dir
	elif turns_at_ledges:
		var rc := get_node_or_null("LedgeProbe") as RayCast2D
		if rc != null:
			rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
			rc.force_raycast_update()
			if is_on_floor() and not rc.is_colliding():
				_dir = -_dir


## True when the patrol facing presses INTO the wall (wall normal points toward
## the body, so facing and normal have opposite signs). Prevents re-flipping
## every frame while still touching a wall we already turned away from.
static func _pressing_into_wall(dir: int, wall_normal_x: float) -> bool:
	return dir * wall_normal_x < 0.0


## Subclass hook, called each physics frame just before move_and_slide().
func _ai_tick(_delta: float) -> void:
	pass


func _color() -> Color:
	return Color(0.9, 0.4, 0.6, 1)


func stun(duration: float) -> void:
	_stunned = true
	_stun_timer = duration
	velocity.x = 0.0
	_state = State.STUNNED


func _is_stomp(player: Node) -> bool:
	if player is CharacterBody2D:
		var cb := player as CharacterBody2D
		return cb.velocity.y > 0.0 and cb.global_position.y < global_position.y - TILE * 0.25
	return false


func _handle_player(player: Node) -> void:
	if _dying:
		return
	if _is_stomp(player):
		_on_stomped(player)
	elif not _stunned:
		_on_side_contact(player)
	# else: side contact while stunned -> harmless (ignored)


## Hook: landed on from above. Default = stun + bounce the player up. A re-stomp
## on an already-stunned enemy refreshes the stun but does NOT bounce again --
## otherwise the small stomp_bounce (~77px) lets the player exit and re-enter the
## contact Area2D every cycle, soft-locking them in an infinite stomp-bounce loop.
func _on_stomped(player: Node) -> void:
	var already_stunned := _stunned
	stun(stun_duration)
	if not already_stunned and player is CharacterBody2D and stomp_bounce > 0.0:
		(player as CharacterBody2D).velocity.y = -stomp_bounce


## Hook: touched from the side. Default = knockback away + contact damage.
func _on_side_contact(player: Node) -> void:
	if player is CharacterBody2D:
		var d := signi(player.global_position.x - global_position.x)
		(player as CharacterBody2D).velocity = Vector2(d * knockback_x, -knockback_y)
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


## Hook: just recovered from being stunned. Default = resume walking.
func _on_recover() -> void:
	_state = State.WALK
	_phase_timer = walk_time


func take_damage(amount: int) -> void:
	if _dying or _dead:
		return
	health -= amount
	if health <= 0:
		AudioManager.play_sfx("enemy_die")
		_enter_shot_death()
	else:
		AudioManager.play_sfx("enemy_hit")


func _enter_shot_death() -> void:
	_dying = true
	velocity = Vector2.ZERO
	_state = State.SHOT
	var shot := _sprites.get("Shot") as AnimatedSprite2D
	if shot != null and shot.sprite_frames != null:
		var names := shot.sprite_frames.get_animation_names()
		if names.size() > 0:
			shot.visible = true
			if not shot.sprite_frames.has_animation(shot.animation):
				shot.animation = names[0]
			if not shot.is_playing():
				shot.play()
			if not shot.animation_finished.is_connected(_on_shot_finished):
				shot.animation_finished.connect(_on_shot_finished)
			_leave_corpse = true
			get_tree().create_timer(0.6).timeout.connect(_die)
			return
	_die()  # no death art -> die immediately


func _on_shot_finished() -> void:
	_die()


## Idempotent death: awards score once, then either frees the node or — if the
## enemy had death art — leaves an inert corpse frozen on the last frame.
func _die() -> void:
	if _dead:
		return
	_dead = true
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group("player")
		if p != null and p.has_method("add_score"):
			p.add_score(score_value)
	if _leave_corpse:
		_become_corpse()
	else:
		queue_free()


## Freeze in place as a non-interactive corpse: stop physics/collision so the
## death frame stays visible where the enemy fell.
func _become_corpse() -> void:
	set_physics_process(false)
	velocity = Vector2.ZERO
	if _area != null:
		_area.set_deferred("monitoring", false)
		_area.set_deferred("monitorable", false)
