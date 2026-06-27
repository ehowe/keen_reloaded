extends GutTest

func test_build_spawns_every_registered_entity_type():
	GameManager.pending_level = null
	var ld := LevelData.new()
	ld.width = 16
	ld.height = 8
	ld.tile_size = 16
	ld.fill_blank()
	ld.player_spawn = Vector2i(1, 1)
	# Add one EntityDef per registered type, spaced along a row.
	var x := 2
	for entry in EntityRegistry.get_palette_entries():
		ld.entities.append(EntityDef.new(String(entry["type_id"]), x, 1))
		x += 1

	var rt := LevelRuntime.new()
	add_child_autofree(rt)
	rt.build(ld)

	assert_eq(rt.entities_spawned.size(), ld.entities.size(), "every entity spawned")
	# Each spawned node must be a real Entity on the tree.
	for node in rt.entities_spawned:
		assert_true(node is Entity)
		assert_true(node.is_inside_tree())
