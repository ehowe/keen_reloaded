class_name Spike
extends Hazard
## Stationary spike hazard. Instakill on contact (drains all health), like the
## Clapper. Carries a "facing" enum variant (right/left) selecting which
## AnimatedSprite2D child is visible; applied via EntityVariant in setup().


func setup(p_type_id: String, p_props: Dictionary) -> void:
	super(p_type_id, p_props)
	EntityVariant.apply(type_id, properties, self)


func _handle_player(player: Node) -> void:
	_instakill(player)
