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


func _cache_sprites() -> void:
	_sprites.clear()
	for state in SPRITE_NAMES:
		var n := get_node_or_null(SPRITE_NAMES[state]) as AnimatedSprite2D
		if n != null:
			_sprites[SPRITE_NAMES[state]] = n
			n.stop()
	if _sprites.size() > 0 and has_node("Visual"):
		get_node("Visual").queue_free()


func _sync_visual() -> void:
	var active: String = SPRITE_NAMES.get(_state, "")
	for name in _sprites:
		var n: AnimatedSprite2D = _sprites[name]
		var show: bool = (name == active)
		n.visible = show
		if show:
			if _state != State.SHOT and not n.is_playing() and n.sprite_frames != null:
				n.play()
			if name == "Walking":
				n.flip_h = _dir > 0
		elif n.is_playing():
			n.stop()


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if velocity.y > max_fall:
		velocity.y = max_fall
	velocity.x = _dir * patrol_speed
	if turns_at_walls and is_on_wall():
		_dir = -_dir
	elif turns_at_ledges:
		var rc := get_node_or_null("LedgeProbe") as RayCast2D
		if rc != null:
			rc.target_position = Vector2(_dir * TILE * 0.5, TILE * 0.6)
			rc.force_raycast_update()
			if is_on_floor() and not rc.is_colliding():
				_dir = -_dir
	_ai_tick(delta)
	move_and_slide()
	_sync_visual()


## Subclass hook, called each physics frame just before move_and_slide().
func _ai_tick(_delta: float) -> void:
	pass


func _color() -> Color:
	return Color(0.9, 0.4, 0.6, 1)


func _handle_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(contact_damage)


func take_damage(amount: int) -> void:
	health -= amount
	if health <= 0:
		var tree := get_tree()
		if tree != null:
			var p := tree.get_first_node_in_group("player")
			if p != null and p.has_method("add_score"):
				p.add_score(score_value)
		queue_free()
