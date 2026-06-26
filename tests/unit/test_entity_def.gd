extends GutTest

func test_default_construction():
	var e := EntityDef.new()
	assert_eq(e.type, "", "default type is empty")
	assert_eq(e.x, 0, "default x is 0")
	assert_eq(e.y, 0, "default y is 0")
	assert_eq(e.properties, {}, "default properties is empty dict")

func test_parameterized_construction():
	var e := EntityDef.new("vorticon", 12, 7, {"speed": 30})
	assert_eq(e.type, "vorticon")
	assert_eq(e.x, 12)
	assert_eq(e.y, 7)
	assert_eq(e.properties.get("speed"), 30)

func test_serialization_round_trip():
	var e := EntityDef.new("yorp", 3, 4, {"hp": 2})
	var path := "user://tests/test_entity_def.tres"
	DirAccess.make_dir_recursive_absolute("user://tests/")
	var err := ResourceSaver.save(e, path)
	assert_eq(err, OK, "save should return OK")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EntityDef
	assert_not_null(loaded, "loaded resource should not be null")
	assert_eq(loaded.type, "yorp")
	assert_eq(loaded.x, 3)
	assert_eq(loaded.y, 4)
	assert_eq(loaded.properties.get("hp"), 2)
