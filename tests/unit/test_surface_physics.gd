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

func test_step_ice1_entry_caps_overspeed():
	# landing faster than cap -> clamped to cap, sign preserved
	assert_almost_eq(SurfacePhysics.step_ice1_entry(700.0, 480.0), 480.0, 0.01, "right overspeed capped")
	assert_almost_eq(SurfacePhysics.step_ice1_entry(-700.0, 480.0), -480.0, 0.01, "left overspeed capped")
	# under cap -> unchanged
	assert_almost_eq(SurfacePhysics.step_ice1_entry(300.0, 480.0), 300.0, 0.01, "under cap unchanged")

func test_step_ice1_zero_friction_no_input():
	# CORE assertion: releasing input on ice preserves velocity exactly
	var vx := 480.0
	for i in 60:
		vx = SurfacePhysics.step_ice1(vx, 0.0, 480.0, 1500.0, 0.016)
	assert_almost_eq(vx, 480.0, 0.001, "zero friction: velocity unchanged with no input")

func test_step_ice1_accelerates_with_input():
	var vx := 0.0
	vx = SurfacePhysics.step_ice1(vx, 1.0, 480.0, 1500.0, 0.016)
	assert_almost_eq(vx, 1500.0 * 0.016, 0.01, "accelerates by ice_accel*delta")

func test_step_ice1_turn_decelerates_through_zero():
	# gliding right at full, hold left -> decel through zero toward -cap
	var vx := 480.0
	for i in 200:
		vx = SurfacePhysics.step_ice1(vx, -1.0, 480.0, 1500.0, 0.016)
	assert_lte(vx, 0.0, "reversed sign within 200 frames")
	# and eventually reaches -cap
	vx = 480.0
	for i in 1000:
		vx = SurfacePhysics.step_ice1(vx, -1.0, 480.0, 1500.0, 0.016)
	assert_almost_eq(vx, -480.0, 0.5, "reaches -cap when holding opposite")

func test_step_ice2_pins_entry_direction_speed():
	# pinned exactly to entry_dir * slide_speed regardless of incoming vx
	assert_almost_eq(SurfacePhysics.step_ice2(1.0, 480.0), 480.0, 0.001, "right entry pins +slide_speed")
	assert_almost_eq(SurfacePhysics.step_ice2(-1.0, 480.0), -480.0, 0.001, "left entry pins -slide_speed")
	# incoming velocity is irrelevant once pinned
	assert_almost_eq(SurfacePhysics.step_ice2(1.0, 480.0), 480.0, 0.001, "pin ignores incoming vx")
