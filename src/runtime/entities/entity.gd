class_name Entity
extends CharacterBody2D
## Base class for all runtime entities. Builds a contact Area2D (collision_mask =
## player bit) + a procedural visual in _ready(). If the scene provides a child
## named "Visual", it is used as-is (the art seam); otherwise a fallback ColorRect
## is built. Subclasses override _handle_player() to react on contact.
##
## Base defaults to static-item collision (layer=items, mask=0); physics subclasses
## (added in later tasks) override _ready() to set body collision + add a shape.

signal player_touched(player: Node)

const TILE := 64

var type_id: String = ""
var properties: Dictionary = {}

var _area: Area2D


## Called by EntityRegistry.instantiate after constructing the node.
func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	properties = p_props
	# Apply editor-set tuning keys onto matching instance vars.
	for key in p_props:
		if get(key) != null:
			set(key, p_props[key])


func _ready() -> void:
	_build_contact()
	# Static-item defaults; physics subclasses override after calling super.
	collision_layer = 8  # items
	collision_mask = 0


func _build_contact() -> void:
	_area = Area2D.new()
	_area.name = "Area2D"
	_area.monitoring = true
	_area.collision_layer = 0
	_area.collision_mask = 1  # player bit
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE)
	shape.shape = rect
	_area.add_child(shape)
	_area.body_entered.connect(_on_body_entered)
	add_child(_area)

	if not has_node("Visual"):
		var vis := ColorRect.new()
		vis.name = "Visual"
		vis.size = Vector2(TILE, TILE)
		vis.position = Vector2(-TILE / 2.0, -TILE / 2.0)
		vis.color = _color()
		add_child(vis)


func _color() -> Color:
	return Color(0.8, 0.8, 0.8, 1)


func _on_body_entered(body: Node) -> void:
	var p := _as_player(body)
	if p == null:
		return
	player_touched.emit(p)
	_handle_player(p)


func _as_player(body: Node) -> Node:
	if body != null and body.is_in_group("player"):
		return body
	return null


## Override in subclasses to react to the player touching this entity.
func _handle_player(_player: Node) -> void:
	pass
