class_name Yorp
extends Enemy
## Keen 1 Yorp: slow patrol biased toward Keen; on side contact knocks the player
## back (no damage — classic Yorp is harmless); a stomp from above stuns it
## (recoverable); 1 blaster hit to defeat. Tuning + seek-biased wander override only.

@export var seek_chance: float = 0.7
## Horizontal impulse applied to Keen on each new contact, animating him back
## instead of teleporting. ~440 px/s decays to 0 in ~0.15s ≈ half a tile.
@export var bounce_speed: float = 440.0

var _was_in_contact: bool = false


func _ready() -> void:
	super._ready()
	health = 1
	score_value = 100
	patrol_speed = 70.0
	contact_damage = 0  # classic Yorp: knockback only, no contact damage
	turns_at_ledges = false


func _choose_walk_dir() -> int:
	var tree := get_tree()
	if tree != null:
		var p := tree.get_first_node_in_group("player") as Node2D
		if p != null:
			if randf() < seek_chance:
				return 1 if p.global_position.x > global_position.x else -1
			return -1 if randf() < 0.5 else 1
	return -_dir


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_solidify_against_player()


## Pure decision: how far to slide Keen along x to resolve a body overlap of
## `distance` pixels in direction `dir` (+1 right, -1 left). Returns 0 when Keen
## is blocked by a wall in that direction (so the yorp walks through him and he
## can escape the other way), or when the yorp is stunned/dying.
func _push_away_distance(distance: float, dir: int, blocked: bool) -> float:
	if _stunned or _dying or distance <= 0.0 or dir == 0:
		return 0.0
	if blocked:
		return 0.0
	return float(dir) * distance


## Whether this frame is the first of a new contact (entry edge).
func _should_bounce(in_contact: bool, was_in_contact: bool) -> bool:
	return in_contact and not was_in_contact


## Treats the yorp as a one-way solid for Keen: each frame, if Keen's body
## overlaps the yorp's, Keen is pushed out to the nearest side (so he cannot
## walk through, and a walking yorp shoves him ahead). If Keen is pressed
## against a solid surface in the push direction, the push is skipped and the
## yorp walks through him instead, letting Keen escape the other way.
func _solidify_against_player() -> void:
	if _stunned or _dying:
		return
	var p := _player_body()
	if p == null:
		return
	var yh := ShapeUtil.rect_half(self, "BodyShape")
	var ph := ShapeUtil.rect_half(p, Player.COLLISION_LEVEL)
	if yh == Vector2.ZERO or ph == Vector2.ZERO:
		return
	var dy := p.global_position.y - global_position.y
	# Skip when Keen is above the yorp's top (stomp scenario -> handled by stomp
	# logic) or far below it (different platform).
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
	# Solid: push Keen just out of overlap (no positional bounce — that's animated
	# via the impulse). Skip when he's walled in this direction (yorp passes through).
	var blocked := p.test_move(p.global_transform, Vector2(dir * overlap, 0.0))
	var push := _push_away_distance(overlap, dir, blocked)
	if push != 0.0:
		p.global_position.x += push


func _player_body() -> CharacterBody2D:
	var tree := get_tree()
	if tree == null:
		return null
	var p := tree.get_first_node_in_group("player")
	if p is CharacterBody2D:
		return p
	return null


## Yorp resolves contact by solidifying against Keen each frame; the base
## one-shot knockback would be cancelled by Keen's next input frame anyway.
func _on_side_contact(_player: Node) -> void:
	pass


func _walk_phase_time() -> float:
	return randf_range(walk_time * 0.5, walk_time * 1.5)


func _idle_phase_time() -> float:
	return randf_range(idle_time * 0.5, idle_time * 1.5)
