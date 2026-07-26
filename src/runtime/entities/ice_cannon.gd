class_name IceCannon
extends Hazard
## Directional cannon. Solid body — Keen can stand on it or bump into it
## without damage. Periodically fires a straight-line icicle projectile
## from the active facing sprite's muzzle; the projectile instakills on
## contact and despawns on the first solid tile.
##
## Eight Sprite2D children encode per-direction firing solutions as node
## metadata: projectile_start_position (PackedInt32Array x,y offset from
## cannon center) and projectile_vector (degrees, 0=up, CCW visually).
## Selection is by exact-name match against the `facing` enum — NOT
## EntityVariant, because the sprite names substring-collide
## (Up is a substring of UpRight/UpLeft) which breaks EntityVariant's
## first-substring-wins rule.

const _BODY_SIZE := 128.0  # cannon sprite footprint, px
const _PROJECTILE_SCENE := preload("res://src/runtime/entities/ice_cannon_projectile.tscn")

@export var period: float = 1.0       # seconds between shots
@export var projectile_speed: float = 300.0


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	_apply_facing()


func _ready() -> void:
	# Deliberately do NOT call super._ready(): the base builds a player-
	# contact Area2D, but the cannon body must not kill. Build only the
	# solid body + the firing timer.
	collision_layer = 4  # tiles bit -> Keen collides with / lands on body
	collision_mask = 0
	_add_body_shape()
	_add_timer()


func _handle_player(_player: Node) -> void:
	# No contact Area2D is built, so this is never invoked at runtime.
	# Kept as a no-op guard to satisfy the Hazard override contract.
	pass


func _apply_facing() -> void:
	# Exact-name match (case-insensitive). Only one of the eight sprites is
	# visible at a time; the visible one's metadata drives _fire().
	var facing := String(properties.get("facing", "UpRight"))
	var want := facing.to_lower()
	for c in get_children():
		if c is Sprite2D:
			c.visible = (String(c.name).to_lower() == want)


func _add_body_shape() -> void:
	# Idempotent: free any prior code-built body shape so a repeated
	# _ready() (used by tests to re-tune @exports) rebuilds cleanly.
	for c in get_children():
		if c is CollisionShape2D:
			remove_child(c)
			c.free()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_BODY_SIZE, _BODY_SIZE)
	shape.shape = rect
	add_child(shape)


func _add_timer() -> void:
	# Idempotent: free any prior code-built timer so a repeated _ready()
	# (used by tests to re-tune period) reflects the current @export.
	for c in get_children():
		if c is Timer:
			remove_child(c)
			c.free()
	var timer := Timer.new()
	timer.wait_time = period
	timer.autostart = true
	timer.one_shot = false
	timer.timeout.connect(_fire)
	add_child(timer)


func _fire() -> void:
	var muzzle := _active_facing_sprite()
	if muzzle == null:
		return
	var start_offset := _read_start_offset(muzzle)
	var direction := _read_direction(muzzle)
	var proj: IceCannonProjectile = _PROJECTILE_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.global_position = global_position + start_offset
	proj.launch(direction * projectile_speed)


func _active_facing_sprite() -> Sprite2D:
	for c in get_children():
		if c is Sprite2D and c.visible:
			return c
	return null


func _read_start_offset(sprite: Sprite2D) -> Vector2:
	var arr: PackedInt32Array = sprite.get_meta("projectile_start_position", PackedInt32Array())
	if arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


func _read_direction(sprite: Sprite2D) -> Vector2:
	# projectile_vector is degrees, 0 = straight up, counter-clockwise
	# visually on screen (Y-down). Verified against all eight sprites:
	#   Up=0 -> (0,-1), Left=90 -> (-1,0), Down=180 -> (0,1),
	#   Right=270 -> (1,0), UpRight=315 -> (0.707,-0.707), etc.
	var deg := float(sprite.get_meta("projectile_vector", 0.0))
	var rad := deg_to_rad(deg)
	return Vector2(-sin(rad), -cos(rad))
