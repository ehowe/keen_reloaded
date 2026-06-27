extends GutTest

func test_default_node_per_category():
	EntityRegistry.clear()
	EntityRegistry.register("candy", EntityRegistry.CATEGORY_ITEM, "Candy")
	EntityRegistry.register("spike", EntityRegistry.CATEGORY_HAZARD, "Spike")
	EntityRegistry.register("vort", EntityRegistry.CATEGORY_ENEMY, "Vort")
	EntityRegistry.register("door", EntityRegistry.CATEGORY_SPECIAL, "Door")

	var candy := EntityRegistry.instantiate("candy", Vector2(16, 0))
	assert_not_null(candy)
	assert_true(candy is Collectible)
	assert_eq(candy.position, Vector2(16, 0))
	assert_eq(candy.type_id, "candy")
	assert_true(candy.is_in_group("entity"))

	assert_true(EntityRegistry.instantiate("spike", Vector2.ZERO) is Hazard)
	assert_true(EntityRegistry.instantiate("vort", Vector2.ZERO) is Enemy)
	assert_true(EntityRegistry.instantiate("door", Vector2.ZERO) is Special)


func test_props_applied_via_setup():
	EntityRegistry.clear()
	EntityRegistry.register("candy", EntityRegistry.CATEGORY_ITEM, "Candy")
	var c: Collectible = EntityRegistry.instantiate("candy", Vector2.ZERO, {"score_value": 77})
	assert_eq(c.properties.get("score_value"), 77)


func test_unknown_type_returns_null():
	EntityRegistry.clear()
	assert_null(EntityRegistry.instantiate("does_not_exist", Vector2.ZERO))


## No custom scene on any entry → each category must build a default base-class node.
## Self-contained (does NOT rely on autoload default-roster state).
func test_types_instantiate_without_scenes():
	EntityRegistry.clear()
	EntityRegistry.register("e1", EntityRegistry.CATEGORY_ENEMY, "E1")
	EntityRegistry.register("i1", EntityRegistry.CATEGORY_ITEM, "I1")
	EntityRegistry.register("h1", EntityRegistry.CATEGORY_HAZARD, "H1")
	EntityRegistry.register("s1", EntityRegistry.CATEGORY_SPECIAL, "S1")
	for entry in EntityRegistry.get_palette_entries():
		var tid: String = entry["type_id"]
		var node := EntityRegistry.instantiate(tid, Vector2.ZERO)
		assert_not_null(node, "%s should instantiate" % tid)
		assert_true(node is Entity, "%s should be an Entity" % tid)
	assert_true(EntityRegistry.instantiate("e1", Vector2.ZERO) is Enemy)
	assert_true(EntityRegistry.instantiate("i1", Vector2.ZERO) is Collectible)
	assert_true(EntityRegistry.instantiate("h1", Vector2.ZERO) is Hazard)
	assert_true(EntityRegistry.instantiate("s1", Vector2.ZERO) is Special)
