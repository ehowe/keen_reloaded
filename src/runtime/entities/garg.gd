class_name Garg
extends Enemy
## Keen 1 Garg: wanders randomly and occasionally closes toward Keen. When it
## notices Keen — on the same level (vertical body overlap), within sight range,
## and broadly in front — it charges at full speed. A charge only ends when the
## garg runs into something solid; it then turns around and wanders back the
## other way until it notices Keen again, repeating as long as Keen stays in
## range. Deadly on contact from any angle (instakill). Cannot be stunned.
## 1 blaster shot defeats it. Sprite frames are placeholders pending art pass.

@export var seek_chance: float = 0.4   # chance a wander WALK phase closes toward Keen
@export var charge_speed: float = 360.0
@export var sight_range: float = 480.0     # max horizontal distance to spot Keen
@export var level_slop: float = 8.0        # extra vertical tolerance for "same level"

var _charging: bool = false


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 300
	patrol_speed = 80.0
	contact_damage = 1
	turns_at_ledges = true


## Facing picked when starting a WALK phase during a wander: occasionally closes
## toward Keen, otherwise a random patrol direction.
func _choose_walk_dir() -> int:
	var p := _player_node()
	if p != null and randf() < seek_chance:
		return 1 if p.global_position.x > global_position.x else -1
	return -1 if randf() < 0.5 else 1


## While charging the base wander wall/ledge turning would fight our tracking, so
## suppress it; charge-wall handling lives in _ai_tick instead.
func _turn_if_blocked() -> void:
	if _charging:
		return
	super._turn_if_blocked()


func _ai_tick(_delta: float) -> void:
	if _dying:
		return
	var p := _player_node()
	if p == null:
		_charging = false
		return
	if _charging:
		if _hit_wall():
			# Charge ends at a solid: face away from it and wander back.
			_charging = false
			_dir = signi(get_wall_normal().x)
			_state = State.WALK
			_phase_timer = _walk_phase_time()
			return
		# Keep homing on Keen's current position until something solid stops us.
		_dir = 1 if p.global_position.x > global_position.x else -1
		_state = State.WALK
		_phase_timer = walk_time  # hold WALK for the entire charge
		velocity.x = _dir * charge_speed
	elif _should_charge(p.global_position, _player_half_height(p), _dir):
		_charging = true
		_dir = 1 if p.global_position.x > global_position.x else -1
		_state = State.WALK
		_phase_timer = walk_time
		velocity.x = _dir * charge_speed


## True when we collided with a solid wall in our facing direction last frame.
func _hit_wall() -> bool:
	if not is_on_wall():
		return false
	return _dir * get_wall_normal().x < 0.0


## Pure decision: would the garg notice Keen at `player_pos` (vertical body
## half-extent `player_half_h`) given its current `facing`? Requires Keen to be
## on the same level, within sight range, and broadly in front.
func _should_charge(player_pos: Vector2, player_half_h: float, facing: int) -> bool:
	var dx := player_pos.x - global_position.x
	if absf(dx) > sight_range:
		return false
	var sd := signi(dx) if dx != 0.0 else facing
	if sd != facing and absf(dx) > TILE:
		return false
	var dy := absf(player_pos.y - global_position.y)
	return dy < _body_half_height() + player_half_h + level_slop


func _player_half_height(player: Node) -> float:
	var h := ShapeUtil.rect_half(player, Player.COLLISION_LEVEL).y
	if h > 0.0:
		return h
	return TILE * 0.45


func _body_half_height() -> float:
	var h := ShapeUtil.rect_half(self, "BodyShape").y
	if h > 0.0:
		return h
	return TILE * 0.45


func _player_node() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var p := tree.get_first_node_in_group("player")
	if p is Node2D:
		return p
	return null


## Garg cannot be stunned (a stomp does nothing to it).
func stun(_duration: float) -> void:
	pass


## Contact from any side — including a stomp from above — instantly kills Keen.
func _handle_player(player: Node) -> void:
	if _dying:
		return
	if player.has_method("take_damage") and "health" in player:
		player.take_damage(player.health)
	elif player.has_method("take_damage"):
		player.take_damage(contact_damage)
