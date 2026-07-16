class_name Message
extends Entity
## Contact-triggered message entity. On player contact, emits
## `message_requested(target_level_id)`. LevelRuntime resolves the MESSAGE-kind
## LevelData, builds a centered tile overlay, and pauses the tree.
##
## Scene children (message.tscn):
##   "Base"   — Sprite2D, always visible (the entity's resting sprite).
##   "Unread" — AnimatedSprite2D, plays while the message is unread.
##   "Read"   — Sprite2D, shown after a one-shot message is consumed.
##
## `repeat` property: false (default) = one-shot, switches Unread→Read after
## first contact and blocks re-trigger. true = re-readable, stays Unread.

signal message_requested(target_level_id: String)

const COLOR_UNREAD := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_READ := Color(0.5, 0.5, 0.5, 1.0)

var target_level_id: String = ""
var repeat: bool = false
var _read: bool = false


func setup(p_type_id: String, p_props: Dictionary) -> void:
	type_id = p_type_id
	target_level_id = String(p_props.get("target_level_id", ""))
	repeat = bool(p_props.get("repeat", false))


func _ready() -> void:
	super._ready()
	# Hide the fallback ColorRect that Entity._build_contact adds when the
	# scene provides real sprites.
	if has_node("Base"):
		var fallback := get_node_or_null("Visual")
		if fallback is ColorRect:
			fallback.visible = false
	_update_visual()


func _handle_player(_player: Node) -> void:
	if _read and not repeat:
		return
	_read = true
	_update_visual()
	message_requested.emit(target_level_id)


func _update_visual() -> void:
	# A repeatable message never visually flips to "read" — it can always be
	# opened again — so only non-repeat one-shots show the read state.
	var show_read := _read and not repeat
	var unread := get_node_or_null("Unread")
	var read := get_node_or_null("Read")
	if unread != null and read != null:
		var unread_visible := not show_read
		(unread as CanvasItem).visible = unread_visible
		(read as CanvasItem).visible = show_read
		if unread is AnimatedSprite2D:
			if unread_visible:
				(unread as AnimatedSprite2D).play()
			else:
				(unread as AnimatedSprite2D).stop()
	else:
		var vis := get_node_or_null("Visual")
		if vis is ColorRect:
			(vis as ColorRect).color = COLOR_READ if show_read else COLOR_UNREAD


func _color() -> Color:
	return COLOR_UNREAD
