extends GutTest


func after_each():
	TileSetRegistry.register_defaults()  # restore defaults after any clear()


func test_register_and_lookup():
	TileSetRegistry.clear()
	TileSetRegistry.register("res://a.tres", "A")
	assert_true(TileSetRegistry.has("res://a.tres"))
	assert_false(TileSetRegistry.has("res://b.tres"))
	assert_eq(TileSetRegistry.get_entries().size(), 1)


func test_available_excludes_missing_resources():
	TileSetRegistry.clear()
	TileSetRegistry.register("res://definitely_missing_xyz.tres", "Bogus")
	assert_eq(TileSetRegistry.available().size(), 0, "missing file filtered out")


func test_defaults_registered():
	assert_true(TileSetRegistry.has("res://assets/tilesets/Invasion of the Vorticons.tres"))
