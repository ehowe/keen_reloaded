class_name Vorticon
extends Enemy
## Keen 1 Vorticon: wanders like garg/yorp (walk/idle cycling, walking animation
## while moving, idle while pausing), randomly hops using a keen-style wind-up +
## launch with randomized height, and takes 4 blaster hits to defeat.

@export var jump_chance: float = 0.4        # expected jumps per second
@export var jump_velocity_min: float = 600.0
# Max launch matches Keen's 3-tile apex (v² = 2 * gravity * 3 * TILE; gravity 3920, TILE 64).
@export var jump_velocity_max: float = 1227.0
@export var leap_speed: float = 240.0       # horizontal speed during a hop

var _windup: float = 0.0
var _windup_duration: float = 0.0
var _jump_dir: int = 0


func _ready() -> void:
	super._ready()
	health = 4
	score_value = 300
	patrol_speed = 140.0
	_windup_duration = _jump_anim_duration()


func _ai_tick(delta: float) -> void:
	if _dying or _stunned:
		return
	if _windup > 0.0:
		# Wind-up: hold still, then launch with a random hop height.
		_windup -= delta
		velocity.x = 0.0
		if _windup <= 0.0:
			velocity.y = -randf_range(jump_velocity_min, jump_velocity_max)
			velocity.x = float(_jump_dir) * leap_speed
			_state = State.JUMP
		return
	if _state == State.JUMP:
		# Hold the jump sprite until landing; base _tick_wander leaves us alone.
		if is_on_floor() and velocity.y >= 0.0:
			_state = State.WALK
			_phase_timer = _walk_phase_time()
		return
	if is_on_floor() and randf() < jump_chance * delta:
		_begin_hop()


## Pure decision: would a hop begin this frame given `roll` (randf result) and
## the vorticon's airborne/dying/stunned state? Extracted so tests can verify
## the gating without depending on RNG timing.
func _should_hop(roll: float, delta: float, on_floor: bool, dying: bool, stunned: bool) -> bool:
	if dying or stunned or not on_floor:
		return false
	if _windup > 0.0 or _state == State.JUMP:
		return false
	return roll < jump_chance * delta


## Begin a hop: capture facing for the leap, freeze horizontal during wind-up.
func _begin_hop() -> void:
	_windup = _windup_duration
	_jump_dir = _dir
	velocity.x = 0.0


## Duration of the Jumping sprite's first animation (frame_count / speed).
## Mirrors Player._jump_anim_duration so hops share keen's wind-up rhythm.
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
