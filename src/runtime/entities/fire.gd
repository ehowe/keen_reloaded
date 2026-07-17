class_name Fire
extends Hazard
## Animated fire hazard. Randomizes its starting animation frame so that
## multiple fire instances in a level are not synchronized. Instakill on
## contact (drains all health), like the Spike.


func _ready() -> void:
	super()
	var anim := get_node_or_null("Visual") as AnimatedSprite2D
	if anim == null or anim.sprite_frames == null:
		return
	anim.play("default")
	var count := anim.sprite_frames.get_frame_count("default")
	if count > 0:
		anim.frame = randi() % count
		anim.frame_progress = randf()


func _handle_player(player: Node) -> void:
	_instakill(player)
