class_name Butler
extends Enemy
## Butler Robot: marches in one direction until it hits a wall or ledge, pauses
## (playing a 2-frame idle animation whose frame order depends on facing), then
## reverses and marches the other way. Bullies the player like a Yorp — shoves
## Keen on contact with no damage. ARMORED: projectiles do nothing (cannot be
## defeated by shooting). Cannot be stunned.

@export var pause_time: float = 1.0
@export var bounce_speed: float = 440.0

var _was_in_contact: bool = false


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 0
	patrol_speed = 220.0
	contact_damage = 0
	turns_at_walls = false
	turns_at_ledges = false
	_setup_idle_frames()


## Butler wander: march until blocked (wall or ledge), pause on idle facing the
## boundary that stopped us, then reverse and march the other way. No time-based
## phase cycling — only boundary hits trigger the pause.
func _tick_wander(delta: float) -> void:
	match _state:
		State.WALK:
			if _hit_boundary():
				# Pause facing the wall/ledge we just hit (keep _dir), then reverse
				# after the pause so the idle animation reflects the actual contact.
				_state = State.IDLE
				velocity.x = 0.0
				_phase_timer = pause_time
			else:
				velocity.x = _dir * patrol_speed
		State.IDLE:
			velocity.x = 0.0
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_dir = -_dir
				_state = State.WALK


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_solidify_against_player()


## True when the butler's patrol facing is blocked by a wall or a ledge this frame.
func _hit_boundary() -> bool:
	if is_on_wall() and _pressing_into_wall(_dir, get_wall_normal().x):
		return true
	var rc := get_node_or_null("LedgeProbe") as RayCast2D
	if rc != null and is_on_floor():
		rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
		rc.force_raycast_update()
		if not rc.is_colliding():
			return true
	return false


## Build a second idle animation ("left") with reversed frame order so the
## butler can play its 2-frame idle in either direction depending on facing:
## frame 0 faces right, frame 1 faces left. "default" plays 0,1; "left" plays 1,0.
func _setup_idle_frames() -> void:
	var idle := get_node_or_null("Idle") as AnimatedSprite2D
	if idle == null or idle.sprite_frames == null:
		return
	var sf := idle.sprite_frames
	if not sf.has_animation("default") or sf.has_animation("left"):
		return
	sf.add_animation("left")
	sf.set_animation_loop("left", sf.get_animation_loop("default"))
	sf.set_animation_speed("left", sf.get_animation_speed("default"))
	var count := sf.get_frame_count("default")
	for i in range(count - 1, -1, -1):
		sf.add_frame("left", sf.get_frame_texture("default", i))


func _sync_visual() -> void:
	super._sync_visual()
	var idle := _sprites.get("Idle") as AnimatedSprite2D
	if idle == null or idle.sprite_frames == null:
		return
	# Idle frames natively encode facing (frame 0 = right, frame 1 = left), so
	# never flip them; pick the animation whose frame order matches _dir.
	idle.flip_h = false
	var want := "left" if _dir < 0 else "default"
	if not idle.sprite_frames.has_animation(want):
		return
	if _state == State.IDLE:
		if idle.animation != want:
			idle.animation = want
			idle.frame = 0
			idle.play()
	elif idle.animation != "default" and idle.sprite_frames.has_animation("default"):
		idle.animation = "default"


## Yorp-style bullying: shove Keen each frame on body overlap (no damage), with
## a one-shot bounce impulse on the first frame of contact. If Keen is walled
## in the push direction, skip the shove so the butler walks through him and he
## can escape the other way.
func _solidify_against_player() -> void:
	if _dying:
		return
	var p := _player_body()
	if p == null:
		return
	var yh := ShapeUtil.rect_half(self, "BodyShape")
	var ph := ShapeUtil.rect_half(p, Player.COLLISION_LEVEL)
	if yh == Vector2.ZERO or ph == Vector2.ZERO:
		return
	var dy := p.global_position.y - global_position.y
	if dy < -yh.y or dy > yh.y + ph.y:
		return
	var dx := p.global_position.x - global_position.x
	var overlap: float = (yh.x + ph.x) - absf(dx)
	var in_contact := overlap > 0.0
	var dir := signi(dx) if dx != 0.0 else _dir
	if _should_bounce(in_contact, _was_in_contact) and p.has_method("apply_bounce"):
		p.apply_bounce(float(dir) * bounce_speed)
	_was_in_contact = in_contact
	if not in_contact:
		return
	var blocked := p.test_move(p.global_transform, Vector2(dir * overlap, 0.0))
	var push := _push_away_distance(overlap, dir, blocked)
	if push != 0.0:
		p.global_position.x += push


func _push_away_distance(distance: float, dir: int, blocked: bool) -> float:
	if _dying or distance <= 0.0 or dir == 0:
		return 0.0
	if blocked:
		return 0.0
	return float(dir) * distance


func _should_bounce(in_contact: bool, was_in_contact: bool) -> bool:
	return in_contact and not was_in_contact


func _player_body() -> CharacterBody2D:
	var p := Player.find(get_tree())
	if p is CharacterBody2D:
		return p
	return null


## Butler shoves Keen each frame via _solidify_against_player; suppress the base
## one-shot knockback/damage on side contact.
func _on_side_contact(_player: Node) -> void:
	pass


## Butler cannot be stunned — it has no Stunned sprite and is a relentless robot.
func stun(_duration: float) -> void:
	pass


## Armored: ignore all projectile damage (cannot be defeated by shooting).
func take_damage(_amount: int) -> void:
	pass
