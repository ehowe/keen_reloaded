class_name GreenDanglyStuff
extends Hazard
## Ceiling hazard: one-way platform on top, instakill dangly mass below.
## Three visual variants (Left Edge / Normal / Right Edge) map to the three
## sprite-sheet rows and are selected via the `variant` schema enum, applied
## by EntityVariant in setup().

const _KILL_HEIGHT := 48.0  # px of the bottom of the tile that kills
const _TOP_SOLID := 16.0    # px of the top of the tile that is non-deadly


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _ready() -> void:
	assert(_TOP_SOLID + _KILL_HEIGHT == TILE)
	# Build the player-contact Area2D via the base, then shrink its shape to
	# the bottom _KILL_HEIGHT px of the tile so only the dangly mass kills.
	# Player standing on top (feet above the kill zone) is safe.
	_build_contact()
	_shrink_contact_to_bottom()
	# Body is a one-way platform: layer=tiles so the player lands on it,
	# one_way_collision=true so the player can rise through from below.
	collision_layer = 4  # tiles bit
	collision_mask = 0
	_add_one_way_body_shape()
	_randomize_variant_start_frames()


## Randomize each variant's starting frame + frame progress so multiple
## instances in a level don't animate in lockstep. Mirrors Fire.gd. All
## three variants are randomized (only the visible one renders), so the
## chosen variant is already desync'd when EntityVariant shows it.
func _randomize_variant_start_frames() -> void:
	var vis := get_node_or_null("Visual")
	if vis == null:
		return
	for c in vis.get_children():
		if not (c is AnimatedSprite2D):
			continue
		var anim := c as AnimatedSprite2D
		if anim.sprite_frames == null:
			continue
		var count := anim.sprite_frames.get_frame_count("default")
		if count <= 0:
			continue
		anim.frame = randi() % count
		anim.frame_progress = randf()


func _handle_player(player: Node) -> void:
	_instakill(player)


func _shrink_contact_to_bottom() -> void:
	var col := _area.get_child(0) as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		var rect := col.shape as RectangleShape2D
		rect.size = Vector2(TILE, _KILL_HEIGHT)
		# Center of the bottom _KILL_HEIGHT strip is (TILE - _KILL_HEIGHT) / 2
		# below the tile's center (which is the body origin).
		col.position = Vector2(0, (TILE - _KILL_HEIGHT) / 2.0)


func _add_one_way_body_shape() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	shape.one_way_collision = true
	add_child(shape)
