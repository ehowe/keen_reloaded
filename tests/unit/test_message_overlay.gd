extends GutTest

func test_dismiss_on_key():
	var ov: MessageOverlay = add_child_autofree(load("res://src/ui/message_overlay.tscn").instantiate())
	watch_signals(ov)
	var key := InputEventKey.new()
	key.pressed = true
	key.echo = false
	ov._unhandled_input(key)
	assert_signal_emit_count(ov, "dismissed", 1, "key press dismisses")

func test_dismiss_on_mouse():
	var ov: MessageOverlay = add_child_autofree(load("res://src/ui/message_overlay.tscn").instantiate())
	watch_signals(ov)
	var click := InputEventMouseButton.new()
	click.pressed = true
	ov._unhandled_input(click)
	assert_signal_emit_count(ov, "dismissed", 1, "mouse click dismisses")

func test_ignored_events_do_not_dismiss():
	var ov: MessageOverlay = add_child_autofree(load("res://src/ui/message_overlay.tscn").instantiate())
	watch_signals(ov)
	var key := InputEventKey.new()
	key.pressed = false  # release, not press
	ov._unhandled_input(key)
	assert_signal_emit_count(ov, "dismissed", 0, "key release does not dismiss")
