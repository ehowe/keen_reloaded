extends GutTest

const ST := preload("res://src/core/surface_type.gd")

func test_step_ground_accelerates_toward_run_speed():
	# from rest, holding right -> advances by ground_accel*delta toward +run_speed
	var vx := SurfacePhysics.step_ground(0.0, 1.0, 480.0, 1.0, 4000.0, 6000.0, 0.016)
	assert_almost_eq(vx, 4000.0 * 0.016, 0.01, "advances by accel*delta")

func test_step_ground_caps_at_run_speed():
	var vx := 470.0
	for i in 50:
		vx = SurfacePhysics.step_ground(vx, 1.0, 480.0, 1.0, 4000.0, 6000.0, 0.016)
	assert_almost_eq(vx, 480.0, 0.5, "never exceeds run_speed")

func test_step_ground_decelerates_to_zero_no_input():
	var vx := 300.0
	for i in 60:
		vx = SurfacePhysics.step_ground(vx, 0.0, 480.0, 1.0, 4000.0, 6000.0, 0.016)
	assert_almost_eq(vx, 0.0, 0.5, "coasts to stop with no input")

func test_step_ground_speed_scale_multiplies_target():
	# input-locked exit walk: speed_scale 0.5 -> target is half run_speed
	var vx := SurfacePhysics.step_ground(0.0, 1.0, 480.0, 0.5, 4000.0, 6000.0, 0.016)
	# first step toward 240 at 4000*delta = 64, capped at 64 (under target 240)
	assert_almost_eq(vx, 64.0, 0.01, "accelerates toward scaled target")
	var capped := 230.0
	for i in 50:
		capped = SurfacePhysics.step_ground(capped, 1.0, 480.0, 0.5, 4000.0, 6000.0, 0.016)
	assert_almost_eq(capped, 240.0, 0.5, "caps at scaled target")
