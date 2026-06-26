extends GutTest

func test_gut_is_running():
	assert_true(true, "GUT is wired up correctly")

func test_basic_math():
	assert_eq(2 + 2, 4, "sanity check")
