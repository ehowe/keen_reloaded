class_name TankRobot
extends Enemy
## Keen 1 Tank Robot: a relentless armored infantry bot. Patrols back and forth
## with the "Moving" animation looping; every few seconds it halts in place —
## freezing the Moving sprite mid-stride — and may fire a blaster bolt (the
## "Tank Robot" projectile variant) in its facing direction. After the halt it
## plays the short "Idle" turn animation and then resumes patrolling, randomly
## reversing direction. Invincible: ignores stuns and blaster damage. Contact
## from any side instakills Keen.

const PROJECTILE_SCENE := preload("res://src/runtime/player/projectile.tscn")

@export var walk_time_min: float = 2.0
@export var walk_time_max: float = 4.0
@export var stop_time: float = 1.0
@export var turn_time: float = 0.4
@export var fire_chance: float = 0.7         # probability of firing during a single stop
@export var turn_reverse_chance: float = 0.5  # probability of reversing facing on a turn
@export var projectile_speed: float = 400.0

# Custom sub-state machine layered over the base Enemy states. Maps to the base
# _state field so the base gravity/move_and_slide loop keeps working without
# modification: WALK -> State.WALK (moving), STOP -> State.IDLE (halt), and TURN
# -> State.IDLE (still halted, but the Idle sprite is shown for the turn).
enum Phase { WALK, STOP, TURN }

var _phase: int = Phase.WALK
var _fired_this_stop: bool = false
var _fire_roll: float = 1.0   # cached randf() rolled on stop entry; decides if this stop fires
var _reverse_roll: float = 1.0  # cached randf() rolled on turn entry; decides reversal


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 0
	patrol_speed = 140.0
	contact_damage = 1
	turns_at_walls = true
	turns_at_ledges = true
	_enter_walk()


## Sprite cache override: the scene ships with "Moving" + "Idle" (not the base
## Enemy's Walking/Idle naming), so cache those names directly. The base
## _align_sprite_feet() then runs against this dict, lifting both sprites so
## their feet sit on the floor despite the taller-than-tile art.
func _cache_sprites() -> void:
	_sprites.clear()
	for n in ["Moving", "Idle"]:
		var spr := get_node_or_null(n) as AnimatedSprite2D
		if spr != null:
			_sprites[n] = spr
			spr.stop()
	if _sprites.size() > 0 and has_node("Visual"):
		get_node("Visual").free()
	_align_sprite_feet()


## Tank Robot wander cycle: WALK (random 2-4s) -> STOP (~1s, may fire) ->
## TURN (~0.4s, Idle anim, maybe reverse) -> WALK. Replaces the base
## walk/idle timer pattern entirely.
func _tick_wander(delta: float) -> void:
	_phase_timer -= delta
	match _phase:
		Phase.WALK:
			_turn_if_blocked()
			velocity.x = _dir * patrol_speed
			if _phase_timer <= 0.0:
				_enter_stop()
		Phase.STOP:
			velocity.x = 0.0
			if not _fired_this_stop and _should_fire(_fire_roll):
				_fire()
				_fired_this_stop = true
			if _phase_timer <= 0.0:
				_enter_turn()
		Phase.TURN:
			velocity.x = 0.0
			if _phase_timer <= 0.0:
				_enter_walk()


## Pure decision: does the cached fire roll trigger a shot this stop? Extracted
## so tests can verify the threshold without depending on RNG.
func _should_fire(roll: float) -> bool:
	return roll < fire_chance


## Pure decision: does the cached reverse roll flip facing this turn?
func _should_reverse(roll: float) -> bool:
	return roll < turn_reverse_chance


func _enter_walk() -> void:
	_phase = Phase.WALK
	_state = State.WALK
	_phase_timer = _next_walk_time()


func _enter_stop() -> void:
	_phase = Phase.STOP
	_state = State.IDLE
	velocity.x = 0.0
	_phase_timer = stop_time
	_fired_this_stop = false
	_fire_roll = randf()


func _enter_turn() -> void:
	_phase = Phase.TURN
	velocity.x = 0.0
	# Stay in State.IDLE so the base loop keeps velocity.x = 0 during the turn.
	_phase_timer = turn_time
	_reverse_roll = randf()
	if _should_reverse(_reverse_roll):
		_dir = -_dir


func _next_walk_time() -> float:
	return randf_range(walk_time_min, walk_time_max)


## Custom visual sync: Moving plays during WALK, freezes on its current frame
## during STOP, and hides during TURN (Idle shows instead). Both sprites flip
## with the current facing.
func _sync_visual() -> void:
	var moving := _sprites.get("Moving") as AnimatedSprite2D
	var idle := _sprites.get("Idle") as AnimatedSprite2D
	var in_turn := _phase == Phase.TURN
	if moving != null:
		moving.flip_h = _dir < 0
		moving.visible = not in_turn
		if not in_turn:
			if _phase == Phase.WALK:
				if not moving.is_playing() and moving.sprite_frames != null:
					moving.play()
			else:  # STOP — keep the Moving sprite on screen but freeze its frame.
				if moving.is_playing():
					moving.pause()
		elif moving.is_playing():
			moving.stop()
	if idle != null:
		idle.flip_h = _dir < 0
		idle.visible = in_turn
		if in_turn:
			if not idle.is_playing() and idle.sprite_frames != null:
				idle.play()
		elif idle.is_playing():
			idle.stop()


## Spawn a Tank Robot blaster bolt from the body's leading edge in the facing
## direction. The projectile's variant + collision mask are configured before
## add_child so its _ready() shows the Tank Robot sprite and targets the player.
func _fire() -> void:
	AudioManager.play_sfx("shoot")
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	proj.variant = Projectile.Variant.TANK_ROBOT
	var host: Node = get_parent() if get_parent() != null else get_tree().current_scene
	host.add_child(proj)
	proj.global_position = global_position + Vector2(_dir * TILE * 0.5, -32.0)
	proj.speed = projectile_speed
	proj.launch(_dir)


## Tank Robot is invincible: stuns and blaster damage are no-ops.
func stun(_duration: float) -> void:
	pass


func take_damage(_amount: int) -> void:
	pass


## Contact from any side — including a stomp from above — drains all of Keen's
## current health (instakill). Matches the Garg contact contract.
func _handle_player(player: Node) -> void:
	if _dying:
		return
	if player.has_method("take_damage") and "health" in player:
		player.take_damage(player.health)
