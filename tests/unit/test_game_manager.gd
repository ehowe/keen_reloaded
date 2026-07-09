extends GutTest

func test_pending_level_round_trip():
	var ld := LevelData.new()
	ld.level_id = "t"
	GameManager.pending_level = ld
	assert_eq(GameManager.pending_level, ld)
	GameManager.pending_level = null

func test_return_scene_round_trip():
	var ps := PackedScene.new()
	GameManager.return_scene = ps
	assert_eq(GameManager.return_scene, ps)
	GameManager.return_scene = null

func test_input_actions_registered():
	# GameManager._ready runs at autoload load, before tests.
	assert_true(InputMap.has_action("move_left"))
	assert_true(InputMap.has_action("move_right"))
	assert_true(InputMap.has_action("move_up"))
	assert_true(InputMap.has_action("move_down"))
	assert_true(InputMap.has_action("jump"))
	assert_true(InputMap.has_action("pogo"))
	assert_true(InputMap.has_action("shoot"))

func test_interact_action_registered():
	assert_true(InputMap.has_action("interact"))


func test_jump_has_gamepad_button():
	var has_a := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			has_a = true
	assert_true(has_a, "jump bound to gamepad A")


func test_pogo_shoot_interact_face_buttons():
	var want := {JOY_BUTTON_B: false, JOY_BUTTON_X: false, JOY_BUTTON_Y: false}
	var map := {"pogo": JOY_BUTTON_B, "shoot": JOY_BUTTON_X, "interact": JOY_BUTTON_Y}
	for action in map:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == map[action]:
				want[map[action]] = true
	for btn in want:
		assert_true(want[btn], "face button %d bound" % btn)


func test_move_left_has_stick_axis_and_dpad():
	var has_axis := false
	var has_dpad := false
	for ev in InputMap.action_get_events("move_left"):
		if ev is InputEventJoypadMotion:
			var m := ev as InputEventJoypadMotion
			if m.axis == JOY_AXIS_LEFT_X and m.axis_value < 0.0:
				has_axis = true
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_LEFT:
			has_dpad = true
	assert_true(has_axis, "move_left bound to left stick (-X)")
	assert_true(has_dpad, "move_left bound to D-pad left")


func test_keyboard_bindings_preserved():
	var move_key := false
	var jump_key := false
	for ev in InputMap.action_get_events("move_left"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_A:
			move_key = true
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SPACE:
			jump_key = true
	assert_true(move_key, "move_left keyboard A preserved")
	assert_true(jump_key, "jump keyboard Space preserved")
